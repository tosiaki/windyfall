defmodule WindyfallWeb.ChatLive do
  use WindyfallWeb, :live_view

  alias Windyfall.Messages
  alias Windyfall.PubSubTopics
  alias WindyfallWeb.CoreComponents
  alias WindyfallWeb.Presence
  alias WindyfallWeb.TextHelpers
  import WindyfallWeb.TextHelpers, only: [truncate: 2]
  alias Windyfall.FileHelpers
  alias Windyfall.Repo
  alias Windyfall.Messages.Message
  alias Windyfall.Accounts

  alias WindyfallWeb.Chat.MessageInputComponent

  alias WindyfallWeb.AttachmentHelpers
  import WindyfallWeb.AttachmentHelpers

  @manual_convert_threshold 1000

  def mount(params, _session, socket) do
    current_user = socket.assigns.current_user
    {context, context_error} = determine_context_from_params(params)

    if context_error do
      # Handle error: Redirect, show flash, etc.
      {:ok, redirect(put_flash(socket, :error, context_error), to: ~p"/chat")}
    else
      # --- Use Context ---
      topics = Messages.list_topics() # Fetch topics if needed globally
      can_post_in_context = can_post_in_context?(context, current_user)

      thread_id = parse_thread_id(params)

      if thread_id do
        WindyfallWeb.Endpoint.subscribe(PubSubTopics.thread(thread_id))
      end

      # Fetch initial messages/reactions using context.id if viewing a specific thread
      initial_load_needed = !is_nil(thread_id)

      {raw_messages, at_beginning, reactions_map, user_reactions_map, replied_to_map, grouped_messages, message_ids} =
        if initial_load_needed do
          {msgs, at_beg} = Messages.get_messages_before_id(thread_id)
          msg_ids = Enum.map(msgs, & &1.id)
          Windyfall.ReactionCache.ensure_cached(msg_ids)
          {reactions, user_reactions_map, replied_to_map} = process_preloaded_reactions(msgs, current_user.id)
          grouped = Messages.group_messages(msgs)
          {msgs, at_beg, reactions, user_reactions_map, replied_to_map, grouped, msg_ids}
        else
          {[], true, %{}, %{}, %{}, [], []} # No initial load if no thread selected
        end

      socket =
        socket
        |> assign(:context, context) # Assign the unified context map
        |> assign(:topics, topics) # Assign topics list
        |> assign(:can_post, can_post_in_context) # Assign permission flag
        |> assign(:thread_id, thread_id)
        # Assign message/reaction data from above
        |> assign(:at_beginning, at_beginning)
        |> assign(:reactions, reactions_map)
        |> assign(:user_reactions, user_reactions_map)
        |> assign(:replied_to_map, replied_to_map) 
        |> assign(:messages, grouped_messages)
        |> assign(subscribed_mids: MapSet.new(message_ids))
        |> assign(:profile_tab, :threads) 
        # Stream messages if needed (consider if bulk streaming is necessary on initial load)
        # |> stream_bulk_messages(raw_messages)
        # Remove assigns for topic_path, user_handle, topic if not needed elsewhere
        |> assign(:creating_new_thread, false)
        |> assign(:show_new_thread, false)
        |> assign(:replying_to, nil)
        |> assign(:editing_message_id, nil)
        |> assign(:editing_content, "")
        |> assign(:show_share_modal, false)
        |> assign(:sharing_item_type, nil)
        |> assign(:sharing_item_id, nil)
        |> assign(:jump_target_id, nil)
        |> assign(:initial_load_type, :latest)
        |> allow_upload(:attachments, # Name matches live_file_input ref
             accept: :any, # Or specify: ~w(.pdf .zip .png .jpg .jpeg .gif .txt .mov .mp4 .mp3) etc.
             max_entries: 10, # Example limit
             max_file_size: 25_000_000, # Example: 25MB
             auto_upload: true
             # progress: {__MODULE__, :handle_progress, []} # Optional: For progress display
           )
        |> assign(:show_text_viewer, false)
        |> assign(:text_viewer_data, nil)
        |> assign(:converted_attachments, []) # List to hold metadata of server-created files
        |> assign(:manual_convert_threshold, @manual_convert_threshold)
        |> assign(:editor_content_length, 0) # Track length for UI button
      # |> put_flash(:error, "You cannot delete this message.")

      socket = assign(socket, :active_message_ids, message_ids)

      if connected?(socket) do
        track_presence(socket)
        setup_subscriptions(message_ids)
        WindyfallWeb.Endpoint.subscribe(PubSubTopics.thread_list_updates())
      end

      {:ok, socket}
    end
  end

  defp determine_context_from_params(params) do
    cond do
      # --- Topic Context ---
      topic_path = params["topic_path"] ->
        case Messages.get_topic(topic_path) do
          nil -> {nil, "Topic not found: #{topic_path}"}
          topic ->
            context = %{type: :topic, id: topic.id, name: topic.name, path: topic.path}
            {context, nil}
        end

      # --- User Context by Handle ---
      handle = params["user_handle"] ->
        case Accounts.get_user_by_handle(handle) do # Look up by handle
          nil -> {nil, "User not found: @#{handle}"}
          user -> # Found the user whose profile it is
            context = %{type: :user, id: user.id, name: "#{user.display_name}'s Profile", handle: user.handle, owner_id: user.id}
            {context, nil}
        end

      # --- User Context by ID ---
      user_id_str = params["user_id"] ->
        case user_id_str |> String.to_integer() |> Accounts.get_user() do # Look up by ID
          nil -> {nil, "User not found: ID #{user_id_str}"}
          user -> # Found the user whose profile it is
            context = %{type: :user, id: user.id, name: "#{user.display_name}'s Profile", handle: user.handle, owner_id: user.id}
            {context, nil}
        end

      # --- Default/Global Context ---
      true ->
        context = %{type: :global, id: nil, name: "All Threads"}
        {context, nil}
    end
  end

  defp process_preloaded_reactions(raw_messages, current_user_id) do

    Enum.reduce(raw_messages, {%{}, %{}, %{}}, fn message, {reactions_acc, user_reactions_acc, replied_to_acc} ->
      message_id = message.id
      preloaded_reactions = message.reactions || []
      preloaded_reply_parent = message.replying_to


      # Process for reactions map (like get_reactions_for_messages)
      grouped_by_emoji = Enum.group_by(preloaded_reactions, & &1.emoji)
      message_reactions =
        Enum.map(grouped_by_emoji, fn {emoji, reactions_list} ->
          users = Enum.map(reactions_list, & &1.user_id) |> MapSet.new()
          %{
            emoji: emoji,
            count: length(reactions_list),
            users: users,
            message_id: message_id
            # Add id like "reaction_..." if needed downstream, but maybe not for the map itself
          }
        end)

      new_reactions_acc = Map.put(reactions_acc, message_id, message_reactions)

      # Process for user_reactions map (like get_user_reactions)
      user_emojis =
        Enum.filter(preloaded_reactions, &(&1.user_id == current_user_id))
        |> Enum.map(& &1.emoji)
        |> MapSet.new()

      new_user_reactions_acc =
        if MapSet.size(user_emojis) > 0 do
          Map.put(user_reactions_acc, message_id, user_emojis)
        else
          user_reactions_acc # Avoid adding empty sets
        end

      new_replied_to_acc =
        if parent = preloaded_reply_parent do
          # Ensure parent's user is also loaded (should be due to nested preload)
          parent_user = parent.user || %{display_name: "Unknown User"}
          reply_info = %{
            id: parent.id,
            text: parent.message,
            user_display_name: parent_user.display_name
          }
          Map.put(replied_to_acc, message_id, reply_info)
        else
          replied_to_acc # No change if not a reply
        end

      {new_reactions_acc, new_user_reactions_acc, new_replied_to_acc}
    end)
  end

  defp track_presence(socket) do
    Phoenix.PubSub.subscribe(Windyfall.PubSub, "presence:chat")
    {:ok, _} = Presence.track(
      self(),
      "chat:thread:#{socket.assigns.thread_id}",
      socket.assigns.current_user.id,
      %{
        user_id: socket.assigns.current_user.id,
        message_ids: get_visible_message_ids(socket)
      }
    )
    socket
  end

  defp get_visible_message_ids(socket) do
    socket.assigns.messages
    |> Enum.flat_map(fn group -> group.messages end)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
  end

  defp setup_subscriptions(message_ids) do
    Enum.each(message_ids, &subscribe_to_reactions/1)
  end

  defp subscribe_to_reactions(mid) do
    Phoenix.PubSub.subscribe(Windyfall.PubSub, "reactions:#{mid}")
  end

  @impl true
  def handle_params(params, uri_string, socket) do
    current_user = socket.assigns.current_user # Assuming already assigned
    thread_id = parse_thread_id(params)

    uri = URI.parse(uri_string)
    fragment = uri.fragment # This holds the string *after* #, or nil

    # Extract target message ID from the fragment string
    target_message_id_str = fragment && String.trim_leading(fragment, "message-")

    {context, context_error} = determine_context_from_params(params)

    if context_error do
       # Handle context error (redirect, flash etc.) - Simplified
       {:noreply, redirect(put_flash(socket, :error, context_error), to: ~p"/chat")}
    else
      # Assign context FIRST
      socket = assign(socket, :context, context)
      can_post_in_context = can_post_in_context?(context, current_user)

      # Clear previous messages/state before loading new thread/target
      socket = assign(socket, :messages, [])
      socket = stream(socket, :messages, [], reset: true)
      socket = stream(socket, :reactions, [], reset: true)
      socket = assign(socket, :at_beginning, true)
      socket = assign(socket, :at_end, true) # Add at_end assign
      socket = assign(socket, :jump_target_id, nil) # Reset jump target

      # Subscribe/Unsubscribe logic (similar to select_thread_and_subscribe)
      old_thread_id = socket.assigns.thread_id
      if old_thread_id && old_thread_id != thread_id do
         WindyfallWeb.Endpoint.unsubscribe(Windyfall.PubSubTopics.thread(old_thread_id))
      end
      if thread_id && thread_id != old_thread_id do
         WindyfallWeb.Endpoint.subscribe(Windyfall.PubSubTopics.thread(thread_id))
      end

      thread_id = parse_thread_id(params) # Keep thread_id parsing separate
      socket = assign(socket, :thread_id, thread_id) # Assign new thread_id

      # --- Get current profile tab state ---
      # We don't get tab from params, it's managed internally via handle_event
      current_profile_tab = socket.assigns.profile_tab || :threads

      {raw_messages, at_beginning, at_end, jump_target_id, load_type} =
        case current_profile_tab do
          :bookmarks ->
            # ChatLive doesn't load messages when bookmarks tab is active unless a thread_id is specified
            if thread_id do # Load thread messages if a specific thread is selected
              {msgs, at_beg} = Messages.get_messages_before_id(thread_id)
              {msgs, at_beg, false, nil, :latest} # Assume not at end on initial thread select
            else # No thread selected, load nothing for messages view here
              {[], true, true, nil, :none}
            end

          :threads -> # Default tab: Load context messages or specific thread
            # Logic for loading latest or around target
            target_message_id_str = fragment && String.trim_leading(fragment, "message-")
            case target_message_id_str |> parse_int_or_nil() do
              target_id when not is_nil(target_id) and not is_nil(thread_id) ->
                # Keep using messages_around for jump-to-target
                {msgs, at_beg, at_end} = Messages.messages_around(thread_id, target_id)
                {msgs, at_beg, at_end, target_id, :around_target}
              _ -> # Load latest
                 if thread_id do
                    {msgs, at_beg} = Messages.get_messages_before_id(thread_id)
                    {msgs, at_beg, false, nil, :latest} # Assume not at end
                 else
                    {[], true, true, nil, :none}
                 end
            end
        end

      # Process messages, reactions, etc. (common logic)
      grouped = Messages.group_messages(raw_messages)
      message_ids = Enum.map(raw_messages, & &1.id)
      {reactions_map, user_reactions_map, replied_to_map} = process_preloaded_reactions(raw_messages, current_user.id)
      Windyfall.ReactionCache.ensure_cached(message_ids)
      setup_subscriptions(message_ids)

      socket = socket
        |> assign(:messages, grouped)
        |> assign(:reactions, reactions_map)
        |> assign(:user_reactions, user_reactions_map)
        |> assign(:replied_to_map, replied_to_map)
        |> assign(:at_beginning, at_beginning)
        |> assign(:at_end, at_end) # Assign at_end state
        |> assign(:active_message_ids, message_ids)
        |> assign(:subscribed_mids, MapSet.new(message_ids))
        |> assign(:initial_load_type, load_type) # Store how load happened
        |> assign(:jump_target_id, jump_target_id) # Store target for JS scroll
        |> assign(:profile_tab, current_profile_tab)

      # Trigger scroll *after* update if jump target exists
      socket = if jump_target_id, do: push_event(socket, "scroll-to-message", %{id: jump_target_id}), else: socket

      {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen">
      In chat live variable
      <button phx-click="debug_messages">Debug Messages</button>
      <%# Navigation Header %>
      <div class="sticky top-0 bg-white border-b z-20">
        <div class="flex items-center justify-between px-4 py-3">
          <h1 class="text-xl font-bold text-gray-800">
            <%= cond do
              @context -> @context.name
              @thread_id -> "Conversation"
              @user_handle -> "Your Threads"
              true -> "All Threads"
            end %>
          </h1>

          <div class="flex items-center gap-4">
            <%= if @thread_id do %>
              <button 
                phx-click="close_thread" 
                class="flex items-center gap-2 text-gray-600 hover:text-gray-800 text-sm px-3 py-1.5 rounded-lg hover:bg-gray-100 transition-colors"
              >
                <.icon name="hero-arrow-left" class="w-4 h-4" />
                <%= cond do
                  @context -> "Back to #{@context.name || "Topic"}"
                  @user_handle -> "Back to Profile"
                  true -> "All Threads"
                end %>
              </button>
            <% else %>
              <%= if @can_post && !@show_new_thread do %>
                <button 
                  phx-click="show_new_thread" 
                  class="flex items-center gap-2 bg-[var(--color-primary)] text-white px-4 py-2 rounded-lg hover:bg-[var(--color-primary-dark)] transition-colors"
                >
                  <.icon name="hero-plus" class="h-5 w-5" />
                  New Post
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>

      <div class="flex-1 flex overflow-hidden">
        <%# Threads Column %>
        <div class={[
          "overflow-y-auto thread-list-column",
          if(@thread_id, 
            do: "w-full md:w-96 xl:w-[600px] border-r border-[var(--color-border)]", 
            else: "flex-1"
          )
        ]}>
          <%= if @show_new_thread do %>
            <.live_component
              module={WindyfallWeb.NewThreadComponent}
              id="new-thread-form"
              context_type={@context.type} # NEW - Get type from context map
              context_id={@context.id}   # NEW - Get ID from context map
              current_user={@current_user}
            />
          <% else %>
            <.live_component 
              module={WindyfallWeb.ThreadsComponent}
              id="threads-list"
              context={@context}
              selected_thread_id={@thread_id}
              current_user={@current_user}
              can_post={@can_post}
              mode={if @thread_id, do: :compact, else: :feed_item}
              profile_tab={@profile_tab}
              current_user_id={@current_user && @current_user.id}
            />
          <% end %>
        </div>

        <%# Messages Column - Only show when thread is selected %>
        <div class={[
          "flex-1 flex-col border-l border-[var(--color-border)] thread-messages-column",
          if(@thread_id, do: "flex", else: "hidden md:hidden")
        ]}>
          <%= if @thread_id do %>
            <div class="flex-1 overflow-y-auto p-4" id="messages" phx-hook="ChatHook">
              <%= if @thread_id do %>
                <%= for {group, group_index} <- Enum.with_index(@messages) do %>
                  <%= if should_show_date_divider(@messages, group_index) do %>
                    <.live_component 
                      module={WindyfallWeb.Chat.DateDividerComponent} 
                      id={"divider-#{group.first_inserted}"}
                      date={group.first_inserted}
                    />
                  <% end %>

                  <div class="mb-4">
                    <div data-user-self={group.user_id == @current_user.id}>
                      <.live_component 
                        module={WindyfallWeb.Chat.MessageComponent}
                        id={"group-#{group_index}"}
                        group={group}
                        is_user={group.user_id == @current_user.id}
                        current_user={@current_user}
                        show_avatar={group.user_id != @current_user.id}
                        show_header={group.user_id != @current_user.id}
                        reactions={get_group_reactions(@reactions, group)}
                        user_reactions={@user_reactions}
                        replied_to_map={@replied_to_map}
                        class="message"
                        editing_message_id={@editing_message_id}
                        editing_content={@editing_content}
                      />
                    </div>
                  </div>
                <% end %>
              <% else %>
                <%# Placeholder for when no thread is selected on larger screens %>
                <div class="hidden md:flex flex-1 items-center justify-center bg-gray-50/50">
                  <div class="text-center p-8 text-[var(--color-text-secondary)]">
                     <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-16 h-16 mx-auto mb-4 text-[var(--color-text-tertiary)]">
                       <path stroke-linecap="round" stroke-linejoin="round" d="M8.625 12a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H8.25m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H12m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0h-.375M21 12c0 4.556-4.03 8.25-9 8.25a9.764 9.764 0 01-2.555-.337A5.972 5.972 0 015.41 20.97a5.969 5.969 0 01-.474-.065 4.48 4.48 0 00.978-2.025c.09-.455.09-.91.09-1.365 0-3.028 2.25-5.5 5.007-5.5s5.007 2.472 5.007 5.5a5.971 5.971 0 01-.474 2.584l.041-.022a5.97 5.97 0 01-.474.065zm-12-8.25a.75.75 0 100-1.5.75.75 0 000 1.5zM12 3.75a.75.75 0 100-1.5.75.75 0 000 1.5z" />
                     </svg>
                    Select a conversation or start a new post.
                  </div>
                </div>
              <% end %>
            </div>
                Outside replying <%= inspect @replying_to %>
            <%= if @replying_to do %>
              <div class="reply-indicator px-4 py-2 text-sm bg-gray-100 border-t border-b text-gray-600 flex justify-between items-center">
                <span>
                  Replying to <%= @replying_to.user_display_name %>:
                  <em class="italic">"<%= truncate(@replying_to.text, 50) %>"</em>
                </span>
                <button phx-click="cancel_reply" aria-label="Cancel reply" class="text-gray-500 hover:text-red-600">
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </div>
            <% end %>

            <%# Message Input %>
            <.live_component 
              module={MessageInputComponent}
              id="message-input"
              current_user={@current_user}
              thread_id={@thread_id}
              uploads={@uploads}
              converted_attachments={@converted_attachments}
              editor_content_length={@editor_content_length}
              manual_convert_threshold={@manual_convert_threshold}
            />
          <% else %>
            <div class="hidden md:flex flex-1 items-center justify-center bg-gray-50">
              <div class="text-center p-8">
                <%# Optional: Add guidance for desktop users %>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <%# Conditionally render the Share Modal %>
      <%= if @show_share_modal do %>
        <.live_component
          module={WindyfallWeb.ShareModalComponent}
          id="share-modal"
          show={true}
          item_type={@sharing_item_type}
          item_id={@sharing_item_id}
          current_user={@current_user}
        />
      <% end %>


  <%# Conditionally render based on ChatLive assign %>
  <%= if @show_text_viewer && @text_viewer_data do %>
    <div id="text-viewer-overlay" class="fixed inset-0 bg-black/70 backdrop-blur-sm flex flex-col p-4 z-[1000]" aria-modal="true" role="dialog" aria-labelledby="text-viewer-filename">
      <%# Header %>
      <div class="flex items-center justify-between mb-3 flex-shrink-0">
        <h3 id="text-viewer-filename" class="text-lg font-medium text-white truncate pr-4">
          <%= @text_viewer_data.filename %>
        </h3>
        <button id="text-viewer-close" phx-click="close_text_viewer" aria-label="Close text viewer" class="text-white/70 hover:text-white bg-black/30 rounded-full p-2">
          <.icon name="hero-x-mark" class="w-6 h-6" />
        </button>
      </div>

      <%# Content Area %>
      <div class="flex-1 bg-gray-800/80 border border-gray-600 rounded-md overflow-auto text-white relative">
        <pre class="p-4 text-sm font-mono whitespace-pre-wrap break-words"><code><%= @text_viewer_data.content %></code></pre>

        <%# Navigation (similar to image gallery) %>
        <%= if length(@text_viewer_data.attachments) > 1 do %>
          <button id="text-viewer-prev"
                  phx-click="navigate_text_viewer"
                  phx-value-direction="-1"
                  disabled={@text_viewer_data.index <= 0}
                  aria-label="Previous file"
                  class="text-viewer-nav prev">
             <.icon name="hero-chevron-left" class="w-8 h-8" />
          </button>
          <button id="text-viewer-next"
                  phx-click="navigate_text_viewer"
                  phx-value-direction="1"
                  disabled={@text_viewer_data.index >= length(@text_viewer_data.attachments) - 1}
                  aria-label="Next file"
                  class="text-viewer-nav next">
             <.icon name="hero-chevron-right" class="w-8 h-8" />
          </button>
        <% end %>
      </div>
    </div>
  <% end %>
    </div>
    """
  end

  def handle_info(%{event: "presence_diff"}, socket) do
    active_ids = Presence.list_active_message_ids()
    {:noreply, assign(socket, active_message_ids: active_ids)}
  end

  def handle_info(%{event: "new_message", payload: message_payload}, socket) do
    # The `message_payload` is the map broadcasted above (no :user key)

    # Update replied_to_map if info is in payload
    new_reply_info = message_payload[:replying_to]
    socket =
      if new_reply_info do
        update(socket, :replied_to_map, &Map.put(&1, message_payload.id, new_reply_info))
      else
        # If info wasn't in payload, we might need to fetch it here,
        # OR rely on the next load cycle to get it via preload.
        # For simplicity now, assume preload handles it eventually.
        socket
      end

    # Flatten existing groups. Ensure flatten_groups produces a structure
    # compatible with what group_messages expects (or make group_messages handle it).
    # Let's assume flatten_groups also produces the flatter structure.
    all_messages = [message_payload | flatten_groups(socket.assigns.messages)]

    # Regroup all messages. group_messages is now robust to handle both structures.
    grouped_messages = Messages.group_messages(all_messages)

    socket =
      socket
      |> assign(:messages, grouped_messages)
      |> push_event("new-message", %{}) # Notify JS hooks if needed

    # Subscribe to reactions for the *new* message ID
    WindyfallWeb.Endpoint.subscribe("reactions:#{message_payload.id}") # Subscribe to reactions PubSub
    subscribe_to_reactions(message_payload.id) # Add to presence tracking if needed


    {:noreply, socket}
  end

  def handle_info({:initialize_thread, thread_id}, socket) when is_integer(thread_id) do
    {:noreply, select_thread_and_subscribe(socket, thread_id)}
  end

  def handle_info({:initialize_thread, id}, socket) do
    case Integer.parse(id) do
      {thread_id, ""} -> 
        {:noreply, select_thread_and_subscribe(socket, thread_id)}
      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:update, mid, emoji, count}, socket) do
    # Update reactions state
    new_reactions = update_reaction_count(socket.assigns.reactions, mid, emoji, count)
    {:noreply, assign(socket, reactions: new_reactions)}
  end

  # --- Handle Starting Edit ---
  def handle_info({:start_edit, message_id}, socket) do
    # Find the message to get its current content
    message_details = find_message_in_groups(socket.assigns.messages, message_id)

    if message_details && message_details.user_id == socket.assigns.current_user.id do
      socket =
        socket
        |> assign(:editing_message_id, message_id)
        |> assign(:editing_content, message_details.text)
        # Maybe push focus to an edit input later
        |> push_event("focus-edit-input", %{message_id: message_id})

      # We need to tell the specific MessageComponent to re-render in edit mode.
      # This is tricky without direct component communication. Options:
      # 1. Pass editing_message_id down to *all* MessageComponents and let them
      #    conditionally render an input based on `message.id == @editing_message_id`.
      # 2. Use send_update (requires MessageComponent to handle it).

      # Let's go with option 1 for simplicity now. MessageComponent's render
      # will need to check for edit mode.
      {:noreply, socket}
    else
      # Not found or not authorized
      {:noreply, put_flash(socket, :error, "Cannot edit this message.")}
    end
  end

  def handle_event("load-before", _params, socket) do
    current_messages_flat = flatten_groups(socket.assigns.messages)
    thread_id = socket.assigns.thread_id
    current_user_id = socket.assigns.current_user.id

    oldest_visible_id =
      case socket.assigns.messages do
        # Get the ID of the first message in the first group
        [%{messages: [first_msg | _]} | _] -> first_msg.id
        # Handle empty list case (shouldn't happen if load-before is triggered, but safety)
        _ -> nil
      end
 
    # Should not attempt to load if oldest_visible_id is nil unless it's a weird state
    if is_nil(oldest_visible_id) do
       Logger.warn("load-before triggered with no visible messages?")
       {:noreply, socket} # Do nothing if no cursor
    else
      {new_raw_messages, at_beginning} = 
        Messages.get_messages_before_id(thread_id, oldest_visible_id)

      # --- Process reactions for newly loaded messages ---
      new_message_ids = Enum.map(new_raw_messages, & &1.id)
      {new_reactions_map, new_user_reactions_map, new_replied_to_map} =
        process_preloaded_reactions(new_raw_messages, current_user_id)
      # --- End reaction processing ---

      # Group only the newly fetched messages
      new_groups = Messages.group_messages(new_raw_messages)

      # Merge new groups before existing ones
      updated_messages = merge_message_groups(socket.assigns.messages, new_groups)

      # Subscribe to reaction topics for new messages
      setup_subscriptions(new_message_ids)

      # Prime the reaction cache
      Windyfall.ReactionCache.ensure_cached(new_message_ids)

      socket =
        socket
        # |> stream_messages(new_raw_messages)
        |> update(:reactions, &Map.merge(&1, new_reactions_map))
        |> update(:user_reactions, &Map.merge(&1, new_user_reactions_map))
        |> update(:replied_to_map, &Map.merge(&1, new_replied_to_map))
        |> assign(:messages, updated_messages)
        |> assign(:at_beginning, at_beginning)
        |> assign(:at_end, false)
        |> update(:active_message_ids, & Enum.uniq(&1 ++ new_message_ids))
        |> update(:subscribed_mids, &MapSet.union(&1, MapSet.new(new_message_ids)))

      {:noreply, socket}
    end
  end

  # Placeholder for load-after (if needed later)
  # def handle_event("load-after", _params, socket) do
  #   # ... fetch messages newer than newest visible ...
  #   # ... merge messages, update reactions ...
  #   # ... assign(socket, :at_beginning, false) ...
  #   # ... assign(socket, :at_end, new_at_end_value) ...
  #   {:noreply, socket}
  # end

  # --- Handle Saving Edit ---
  def handle_event("save_edit", %{"content" => new_content, "message-id" => mid_str}, socket) do
    message_id = String.to_integer(mid_str)
    user_id = socket.assigns.current_user.id

    # Double-check we are actually in edit mode for this message (basic auth check)
    if socket.assigns.editing_message_id != message_id do
       {:noreply, put_flash(socket, :error, "Cannot save edit for this message.")}
    else
      case Messages.update_message(message_id, user_id, new_content) do
        {:ok, updated_message} ->
          # Broadcast the update to other clients
          WindyfallWeb.Endpoint.broadcast(
            PubSubTopics.thread(socket.assigns.thread_id),
            "message_updated",
            %{id: updated_message.id, message: updated_message.message} # Send minimal payload
          )

          # Clear editing state locally
          socket =
            socket
            |> assign(:editing_message_id, nil)
            |> assign(:editing_content, "") # Clear temp content
            |> put_flash(:info, "Message updated.")

          {:noreply, socket}

        {:error, :not_found} ->
          # Message might have been deleted concurrently
          {:noreply,
            socket
            |> assign(:editing_message_id, nil) # Exit edit mode
            |> assign(:editing_content, "")
            |> put_flash(:error, "Message not found, could not save edit.")}

        {:error, :unauthorized} ->
          # Should ideally not happen if start_edit checked, but good safety measure
          {:noreply,
            socket
            |> assign(:editing_message_id, nil) # Exit edit mode
            |> assign(:editing_content, "")
            |> put_flash(:error, "You are not authorized to edit this message.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          # Validation error (e.g., message empty)
          # Keep user in edit mode, show error
          error_message = traverse_errors(changeset) # Use existing helper
          {:noreply, put_flash(socket, :error, "Could not save edit: #{error_message}")}

        {:error, reason} ->
           # Other unexpected DB errors
           {:noreply, put_flash(socket, :error, "Failed to save edit: #{reason}")}
      end
    end
  end

  # --- Handle Cancelling Edit ---
  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_message_id: nil, editing_content: "")}
  end

  defp merge_message_groups(existing_groups, new_groups) do
    existing_ids = existing_groups |> Enum.flat_map(& &1.messages) |> Enum.map(& &1.id) |> MapSet.new()
    
    new_groups
    |> Enum.reject(fn group ->
      group.messages |> Enum.any?(&MapSet.member?(existing_ids, &1.id))
    end)
    |> case do
      [] -> existing_groups
      groups -> groups ++ existing_groups
    end
  end

  def handle_event("submit_message", %{"new_message" => message_text}, socket) do
    # --- Consume Uploads ---
    # Assume the callback raises on error (e.g., using File.cp!)
    # consume_uploaded_entries will return the list of metadata directly
    # or raise if the callback fails. We can wrap in try/rescue if needed.
    try do
      consumed_upload_metadata =
        consume_uploaded_entries(socket, :attachments, fn %{path: temp_path}, entry ->
          dest_dir = Path.expand("./priv/static/uploads/messages")
          File.mkdir_p!(dest_dir) # Ensure directory exists
          extension = Path.extname(entry.client_name)
          unique_filename = "#{Ecto.UUID.generate()}#{extension}"
          dest_path = Path.join(dest_dir, unique_filename)

          # Use File.cp! which raises on error
          File.cp!(temp_path, dest_path)

          web_path = "/uploads/messages/#{unique_filename}"
          metadata = %{
            filename: entry.client_name, web_path: web_path,
            content_type: entry.client_type, size: entry.client_size
          }
          # Callback MUST return {:ok, metadata}
          {:ok, metadata}
        end)
      # If we reach here, successful_metadata is a list like: [meta1, meta2, ...]

      converted_metadata = socket.assigns.converted_attachments
      all_successful_metadata = consumed_upload_metadata ++ converted_metadata

      # --- Proceed with Message Creation ---
      has_text = message_text && String.trim(message_text) != ""
      has_attachments = all_successful_metadata != []

      if !has_text and !has_attachments do
        {:noreply, put_flash(socket, :error, "Message cannot be empty without attachments.")}
      else
        # Call create_message with text and successful metadata
        user = socket.assigns.current_user
        thread_id = socket.assigns.thread_id
        replying_to_id = socket.assigns.replying_to && socket.assigns.replying_to.id

        case Messages.create_message(message_text, thread_id, user, replying_to_id, all_successful_metadata) do
          {:ok, new_message_struct_with_attachments} -> # Message includes preloaded attachments now
            # Construct payload for broadcast, including attachments
            payload = %{
              id: new_message_struct_with_attachments.id,
              message: new_message_struct_with_attachments.message, # Might be "" or nil
              user_id: new_message_struct_with_attachments.user_id,
              inserted_at: new_message_struct_with_attachments.inserted_at,
              display_name: user.display_name,
              profile_image: user.profile_image,
              replying_to_message_id: new_message_struct_with_attachments.replying_to_message_id,
              replying_to: maybe_get_reply_parent_info(new_message_struct_with_attachments),
              # Add attachments to payload
              attachments: Enum.map(new_message_struct_with_attachments.attachments || [], fn att ->
                %{id: att.id, filename: att.filename, web_path: att.web_path, content_type: att.content_type, size: att.size}
              end)
            }

            WindyfallWeb.Endpoint.broadcast(PubSubTopics.thread(thread_id), "new_message", payload)

            # Clear reply state, converted attachments, AND editor length tracker
            socket =
              socket
              |> assign(:replying_to, nil)
              |> assign(:converted_attachments, []) # Clear converted list
              |> assign(:editor_content_length, 0) # Reset length tracker

            {:noreply, push_event(socket, "sent-message", %{})}

          {:error, :content_required} ->
            {:noreply, put_flash(socket, :error, "Message content or attachment required.")}
          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to send message: #{inspect(changeset.errors)}")}
          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to send message: #{reason}")}
        end
      end # End if !has_text and !has_attachments
    rescue
      # Catch errors raised during consumption (e.g., from File.cp!)
      e in [File.Error, RuntimeError] -> # Catch specific errors if possible
        Logger.error("Error consuming uploads: #{Exception.format(:error, e, __STACKTRACE__)}")
        {:noreply, put_flash(socket, :error, "Error processing uploaded files. Please try again.")}
    end # End try
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
    # This handler is primarily needed to trigger LiveView's internal
    # upload processing when the file input changes.
    # We don't need to do much here for now, as allow_upload handles
    # basic validation (size, type, count).
    # If you needed more complex validation based on form state,
    # you could add it here.
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("select_thread", %{"id" => id}, socket) do
    thread_id = String.to_integer(id)
    context = socket.assigns.context # Get the unified context

    # Construct the path based on the context type
    IO.inspect context, label: "this is the context"
    path = case context.type do
      :topic ->
        # Use the path stored in the context map
        ~p"/t/#{context.path}/thread/#{thread_id}"
      :user ->
        # Use the handle stored in the context map
        ~p"/u/#{context.handle}/thread/#{thread_id}"
      :global ->
        # Path for selecting a thread from a global/all view
        ~p"/chat/thread/#{thread_id}" # Or just "/thread/#{thread_id}" if you prefer
      _ ->
        # Fallback or error path if context is unexpected
        ~p"/chat" # Go back to default chat view
    end

    # push_patch remains the same, it just uses the dynamically constructed path
    # select_thread_and_subscribe already handles loading data based on thread_id
    {:noreply,
     socket
     |> push_patch(to: path)
     |> select_thread_and_subscribe(thread_id)} # This function loads the new thread's data
  end

  defp select_thread_and_subscribe(socket, thread_id) when is_integer(thread_id) do
    current_thread_id = socket.assigns.thread_id

    # Unsubscribe from the old thread ONLY if it's different and not nil
    if current_thread_id && current_thread_id != thread_id do
      WindyfallWeb.Endpoint.unsubscribe(Windyfall.PubSubTopics.thread(current_thread_id))
    end

    # Subscribe to the new thread ONLY if it's different and not nil
    if thread_id && thread_id != current_thread_id do
       WindyfallWeb.Endpoint.subscribe(Windyfall.PubSubTopics.thread(thread_id))
    end

    # Reset streams for the new messages
    socket =
      socket
      |> stream(:messages, [], reset: true)
      |> stream(:reactions, [], reset: true) 
      # Consider resetting :reactions stream too if it's populated here
      # |> stream(:reactions, [], reset: true)
      |> assign(:messages, []) # Clear old grouped messages

    # --- Assign the NEW thread_id IMMEDIATELY ---
    socket = assign(socket, :thread_id, thread_id)

    # Load data for the new thread
    # (Keep using the batch loading logic from previous refactors)
    {raw_messages, at_beginning} = Messages.get_messages_before_id(thread_id)
    IO.inspect raw_messages, label: "raw mesages are this"
    grouped = Messages.group_messages(raw_messages)
    message_ids = Enum.map(raw_messages, & &1.id)
    {reactions_map, user_reactions_map, replied_to_map} = process_preloaded_reactions(raw_messages, socket.assigns.current_user.id)

    # Prime cache for the new messages
    Windyfall.ReactionCache.ensure_cached(message_ids)
    setup_subscriptions(message_ids)

    # Assign the newly loaded data
    socket = socket
      |> assign(:messages, grouped)
      |> assign(:reactions, reactions_map)
      |> assign(:user_reactions, user_reactions_map)
      |> assign(:replied_to_map, replied_to_map) 
      |> assign(:at_beginning, at_beginning)
      |> assign(:active_message_ids, message_ids) # Update active IDs
      # Review stream_bulk_messages - is it needed if assigns drive components?
      # |> stream_bulk_messages(raw_messages)

    # Return the fully updated socket
    socket
  end

  # Add a clause for selecting "no thread" (going back to list view)
  defp select_thread_and_subscribe(socket, nil) do
    current_thread_id = socket.assigns.thread_id

    # Unsubscribe if switching away from a thread
    if current_thread_id do
      WindyfallWeb.Endpoint.unsubscribe(Windyfall.PubSubTopics.thread(current_thread_id))
    end

    # Reset state for "no thread" view
    socket
    |> stream(:messages, [], reset: true)
    # |> stream(:reactions, [], reset: true)
    |> assign(:messages, [])
    |> assign(:reactions, %{})
    |> assign(:user_reactions, %{})
    |> assign(:thread_id, nil) # Explicitly set thread_id to nil
    |> assign(:at_beginning, true)
    |> assign(:active_message_ids, [])
  end

  defp should_show_date_divider(groups, index) do
    cond do
      index == 0 -> true
      is_nil(Enum.at(groups, index)) -> false
      is_nil(Enum.at(groups, index - 1)) -> false
      true ->
        current_group = Enum.at(groups, index)
        previous_group = Enum.at(groups, index - 1)
        
        current_date = Timex.to_date(current_group.first_inserted)
        previous_date = Timex.to_date(previous_group.last_inserted)
        
        current_date != previous_date
    end
  end

  defp flatten_groups(groups) do
    Enum.flat_map(groups || [], fn group ->
      # Group structure: %{user_id: ..., display_name: ..., profile_image: ..., messages: [%{id:.., text:..., inserted_at:...}]}
      Enum.map(group.messages, fn msg ->
        %{
          id: msg.id,
          message: msg.text, # Use :text key from message_struct
          user_id: group.user_id, # Get from group
          display_name: group.display_name, # Get from group
          profile_image: group.profile_image, # Get from group
          inserted_at: msg.inserted_at,
          attachments: msg.attachments || []
          # No :user key here
        }
      end)
    end)
  end

  def handle_event("close_thread", _, socket) do
    context = socket.assigns.context # Get the unified context map

    # Determine the parent path based on the context type
    path = case context do
      %{type: :topic, path: topic_path} when not is_nil(topic_path) ->
        ~p"/t/#{topic_path}"

      %{type: :user, handle: user_handle} when not is_nil(user_handle) ->
        ~p"/u/#{user_handle}"

      # Default fallback (e.g., if context is :global or unexpected)
      _ ->
        ~p"/chat"
    end

    # Unsubscribe from the closed thread's PubSub topic
    if thread_id = socket.assigns.thread_id do
      WindyfallWeb.Endpoint.unsubscribe(Windyfall.PubSubTopics.thread(thread_id))
    end

    # Reset thread-specific state and navigate back
    {:noreply,
     socket
     |> assign(:thread_id, nil)
     |> assign(:messages, [])
     |> assign(:reactions, %{})
     |> assign(:user_reactions, %{})
     |> assign(:replied_to_map, %{})
     |> assign(:replying_to, nil)
     |> assign(:at_beginning, true) # Reset pagination
     |> assign(:active_message_ids, []) # Reset active message IDs
     |> assign(:subscribed_mids, MapSet.new()) # Clear message subscriptions
     |> stream(:messages, [], reset: true) # Reset message stream
     |> stream(:reactions, [], reset: true) # Reset reaction stream
     |> push_patch(to: path)}
  end

  defp parse_thread_id(%{"thread_id" => thread_id}), do: String.to_integer(thread_id)
  defp parse_thread_id(_params), do: nil

  def handle_event("new_thread", %{ "creating" => creating }, socket) do
    {:noreply, assign(socket, :creating, creating)}
  end

  def handle_event("cancel_new_thread", _params, socket) do
    {:noreply, assign(socket, :show_new_thread, false)}
  end

  def handle_event("create_thread", params, socket) do
    title = params["title"] # Might be nil or ""
    message = params["message"]

    # Check if message is blank
    if !message || String.trim(message) == "" do
       {:noreply, put_flash(socket, :error, "Message cannot be empty.")}
    else
       # Proceed with creation...
       context = socket.assigns.context
       user = socket.assigns.current_user

       create_result = case context.type do
         :topic ->
           # Pass title (even if nil) and message
           Messages.create_thread_with_message(title, message, :topic, context.id, user)
         :user ->
           if user && user.id == context.id do
             # Pass title (even if nil) and message
             Messages.create_thread_with_message(title, message, :user, context.id, user)
           else
             {:error, :unauthorized}
           end
         _ ->
            {:error, :invalid_context}
       end

      case create_result do
        {:ok, _thread} ->
          {:noreply, socket |> assign(:creating, "false") |> reload_threads()} # reload_threads uses context now

        {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
           # ... format changeset errors ...
           {:noreply, put_flash(socket, :error, "Could not create thread: " <> traverse_errors(changeset))} 
        {:error, :unauthorized} ->
           {:noreply, put_flash(socket, :error, "You do not have permission to create a thread here.")}
        {:error, :invalid_context} ->
           {:noreply, put_flash(socket, :error, "Cannot create a thread in this context.")}

      end
    end
  end

  defp get_context(socket) do
    cond do
      socket.assigns[:topic_path] && socket.assigns.topic ->
        {:topic, socket.assigns.topic.id}
      socket.assigns[:user_handle] ->
        {:user, socket.assigns.current_user.id}
      true ->
        :global
    end
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} -> 
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k} #{v}" end)
  end

  def handle_event("show_new_thread", _, socket) do
    {:noreply, assign(socket, :show_new_thread, true)}
  end

  def handle_event("toggle_reaction", %{"emoji" => emoji, "message-id" => message_id}, socket) do
    user_id = socket.assigns.current_user.id
    message_id = String.to_integer(message_id)

    case Messages.add_reaction(message_id, user_id, emoji) do
      {:ok, _} ->
        # Update local state
        reactions = Messages.get_reactions_for_messages([message_id])
        user_reactions = Messages.get_user_reactions([message_id], user_id)
        
        updated_reactions = Map.merge(socket.assigns.reactions, reactions)
        updated_user_reactions = Map.merge(socket.assigns.user_reactions, user_reactions)
        
        # Broadcast to other users
        WindyfallWeb.Endpoint.broadcast!("message:#{message_id}", "reaction_updated", %{message_id: message_id})

        {:noreply,
          socket
          |> assign(:reactions, updated_reactions)
          |> assign(:user_reactions, updated_user_reactions)
        }

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update reaction")}
    end
  end

  def handle_event("debug_messages", _, socket) do
    IO.inspect(socket.assigns.messages, label: "Grouped Messages")
    IO.inspect(socket.assigns.streams, label: "Streams")
    {:noreply, socket}
  end

  def handle_info({:start_reply, message_id}, socket) do
    # Find the message details in the already loaded state
    # This requires searching through the grouped @messages
    reply_target = find_message_in_groups(socket.assigns.messages, message_id)

    socket =
      if reply_target do
        # Prepare minimal info needed for display
        replying_to_info = %{
          id: reply_target.id,
          user_display_name: reply_target.user_display_name, # Assumes find_message... returns this
          text: reply_target.text # Assumes find_message... returns this
        }

        # Assign state and potentially push focus to input
        socket
        |> assign(:replying_to, replying_to_info)
        |> push_event("focus-reply-input", %{})
      else
        # Message not found (shouldn't happen ideally)
        put_flash(socket, :error, "Cannot reply to message.")
      end

    {:noreply, socket}
  end

  def handle_event("cancel_reply", _, socket) do
    {:noreply, assign(socket, :replying_to, nil)}
  end

  def handle_event("jump_to_message", %{"jump-to-id" => target_id_str}, socket) do
    target_id = String.to_integer(target_id_str)
    # Check if message is already loaded by looking at message_ids in assigns
    is_loaded = target_id in socket.assigns.active_message_ids

    if is_loaded do
      # Message is loaded, just trigger JS scroll
      {:noreply, push_event(socket, "scroll-to-message", %{id: target_id})}
    else
      # V1: Message not loaded - Trigger a full jump load
      # Defer incremental loading/closeness check
      IO.inspect({target_id}, label: "Jumping to unloaded message")
      # We use push_patch to change the URL fragment, which handle_params will detect
      current_path = current_path_with_fragment(socket, "message-#{target_id}")
      {:noreply, push_patch(socket, to: current_path)}
      # Alternative: Trigger a custom event handled by ChatLive to perform the load
      # send(self(), {:perform_jump_load, target_id})
      # {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_profile_tab", %{"tab" => tab_str}, socket) do
    new_tab = String.to_existing_atom(tab_str)
    # Clear thread selection when changing tabs? Makes sense for now.
    # Unsubscribe from current thread if any
    if old_thread_id = socket.assigns.thread_id do
       WindyfallWeb.Endpoint.unsubscribe(Windyfall.PubSubTopics.thread(old_thread_id))
    end

    # Determine the base path without thread_id for push_patch
    context = socket.assigns.context
    base_path = case context.type do
       :topic -> ~p"/t/#{context.path}"
       :user -> ~p"/u/#{context.handle}"
       _ -> ~p"/chat"
    end

    socket =
      socket
      |> assign(:profile_tab, new_tab)
      # Clear thread-specific data
      |> assign(:thread_id, nil)
      |> assign(:messages, [])
      |> assign(:reactions, %{})
      |> assign(:user_reactions, %{})
      |> assign(:replied_to_map, %{})
      |> assign(:replying_to, nil)
      |> assign(:at_beginning, true)
      |> assign(:at_end, true)
      |> assign(:active_message_ids, [])
      |> assign(:subscribed_mids, MapSet.new())
      |> stream(:messages, [], reset: true)
      |> stream(:reactions, [], reset: true)
      # Navigate back to the base user/topic page without a thread ID
      |> push_patch(to: base_path)

    {:noreply, socket}
  end

  @impl true
  def handle_event("show_text_viewer", %{"message-id" => msg_id_str, "attachment-id" => att_id_str}, socket) do
    message_id = String.to_integer(msg_id_str)
    attachment_id_to_find = att_id_str # Keep as string/binary for comparison

    # Fetch the message with attachments
    message = Repo.get(Message, message_id) |> Repo.preload(:attachments)

    if !message do
      {:noreply, put_flash(socket, :error, "Message not found.")}
    else
      # Filter only displayable text attachments first
      all_text_attachments = Enum.filter(message.attachments, &is_displayable_text?/1)

      # --- Use Enum.reduce_while to find the attachment and its index ---
      find_result = Enum.reduce_while(all_text_attachments, {:not_found, 0}, fn attachment, {:not_found, index} ->
        # Compare IDs: Use Ecto.UUID.dump! if attachment.id is a binary UUID
        current_attachment_id_str = if Map.has_key?(attachment, :binary_id), do: Ecto.UUID.dump!(attachment.id), else: to_string(attachment.id)

        if current_attachment_id_str == attachment_id_to_find do
           # Found it! Halt the reduction and return the found state
          {:halt, {:found, index, attachment}}
        else
          # Not found yet, continue with the next index
          {:cont, {:not_found, index + 1}}
        end
      end)
      # find_result will be {:found, index, attachment} or {:not_found, final_index}
      # --- End Enum.reduce_while ---

      case find_result do
        {:found, clicked_index, clicked_attachment} ->
          # Proceed with reading the file content (existing logic)
          relative_path = String.trim_leading(clicked_attachment.web_path, "/")
          file_path = Path.join(["priv", "static" | String.split(relative_path, "/")])

          case File.read(file_path) do
            {:ok, content} ->
              viewer_data = %{
                filename: clicked_attachment.filename,
                content: content,
                # Store the *filtered* list of text attachments for navigation
                attachments: all_text_attachments,
                index: clicked_index
              }
              socket =
                socket
                |> assign(:show_text_viewer, true)
                |> assign(:text_viewer_data, viewer_data)
              {:noreply, socket}

            {:error, reason} ->
              Logger.error("Failed to read text attachment #{file_path}: #{reason}")
              {:noreply, put_flash(socket, :error, "Could not load file content.")}
          end

        {:not_found, _} ->
          # Clicked attachment not found in the filtered text list
          {:noreply, put_flash(socket, :error, "Attachment not found or is not a viewable text file.")}
      end
    end
  end

  @impl true
  def handle_event("close_text_viewer", _, socket) do
    {:noreply, assign(socket, show_text_viewer: false, text_viewer_data: nil)}
  end

  @impl true
  def handle_event("navigate_text_viewer", %{"direction" => direction_str}, socket) do
    data = socket.assigns.text_viewer_data
    if !data, do: {:noreply, socket} # Should not happen if viewer is open

    direction = String.to_integer(direction_str) # Expecting "1" or "-1"
    new_index = data.index + direction

    if new_index >= 0 and new_index < length(data.attachments) do
      next_attachment = Enum.at(data.attachments, new_index)

      # Fetch content for the new file
      relative_path = String.trim_leading(next_attachment.web_path, "/")
      file_path = Path.join(["priv", "static" | String.split(relative_path, "/")])

      case File.read(file_path) do
        {:ok, new_content} ->
          new_viewer_data = %{data |
            filename: next_attachment.filename,
            content: new_content,
            index: new_index
          }
          {:noreply, assign(socket, :text_viewer_data, new_viewer_data)}
        {:error, reason} ->
           Logger.error("Failed to read next text attachment #{file_path}: #{reason}")
           {:noreply, put_flash(socket, :error, "Could not load next file content.")}
      end
    else
      # Index out of bounds, do nothing
      {:noreply, socket}
    end
  end

  def handle_event("editor_length_update", %{"length" => length}, socket) do
    {:noreply, assign(socket, editor_content_length: length)}
  end

  # Event from "Convert to File" button
  def handle_event("convert_to_file", %{"content" => content}, socket) do 

    if String.length(content) >= @manual_convert_threshold do
      case FileHelpers.create_text_attachment(content, "message_snippet") do
        {:ok, metadata} ->
          new_converted = [metadata | socket.assigns.converted_attachments]
          # Clear editor via JS and reset tracked length
          socket =
            socket
            |> assign(:converted_attachments, new_converted)
            |> assign(:editor_content_length, 0) # Reset length after conversion
            |> push_event("clear_editor", %{uniqueId: "message-input"}) # Target specific input
          {:noreply, socket}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to convert message to file: #{reason}")}
      end
    else
      # Should not happen if button is only shown when long, but handle anyway
      {:noreply, put_flash(socket, :warn, "Message is not long enough to convert.")}
    end
  end

  # Event from JS on long paste
  def handle_event("handle_paste_conversion", %{"content" => pasted_content}, socket) do
     case FileHelpers.create_text_attachment(pasted_content, "pasted_text") do
       {:ok, metadata} ->
         new_converted = [metadata | socket.assigns.converted_attachments]
        IO.inspect new_converted, label: "new converted text"
         socket =
           socket
           |> assign(:converted_attachments, new_converted)
           |> put_flash(:info, "Pasted content added as attachment.") # User feedback
         {:noreply, socket}
       {:error, reason} ->
         {:noreply, put_flash(socket, :error, "Failed to save pasted content as file: #{reason}")}
     end
  end

  # Event from JS to remove a *converted* attachment before sending
  def handle_event("remove_converted_attachment", %{"web_path" => web_path_to_remove}, socket) do
    # Note: We don't delete the actual file here, only remove it from the pending list.
    # File cleanup might need a separate process or happen on message deletion.
    new_converted = Enum.reject(socket.assigns.converted_attachments, &(&1.web_path == web_path_to_remove))
    {:noreply, assign(socket, :converted_attachments, new_converted)}
  end

  @impl true
  def handle_info({:initiate_share, item_type, item_id}, socket) do
    # item_type will be :thread or :message
    IO.inspect({:initiate_share, item_type, item_id}, label: "Sharing (handle_info)")

    socket =
      socket
      |> assign(:show_share_modal, true)
      |> assign(:sharing_item_type, item_type)
      |> assign(:sharing_item_id, item_id)

    {:noreply, socket}
  end

  # Helper to find message details across groups
  defp find_message_in_groups(groups, message_id) do
    Enum.find_value(groups || [], fn group ->
      # Find the message within the current group's messages list
      found_message = Enum.find(group.messages, fn msg -> msg.id == message_id end)

      # If the message was found in this group, construct and return the desired map
      if found_message do
        %{
          id: found_message.id,
          text: found_message.text,
          user_display_name: group.display_name, # Get display name from the group
          # Add profile_image from group if needed later
          user_id: group.user_id
          # profile_image: group.profile_image
        }
      else
        # Message not in this group, continue searching (find_value implicit behavior)
        nil
      end
    end)
    # Enum.find_value returns the first non-nil map constructed, or nil if not found in any group
  end

  def handle_info({:thread_created, thread}, socket) do
    # Convert Ecto struct to map and enhance data
    thread_data = %{
      id: thread.id,
      title: thread.title,
      message_count: 1,
      last_message_at: NaiveDateTime.utc_now(),
      first_message_at: thread.inserted_at,
      first_message_preview: String.slice(thread.title || "New thread", 0..100) <> "...",
      author_name: socket.assigns.current_user.display_name,
      author_avatar: CoreComponents.user_avatar(socket.assigns.current_user.profile_image),
      user_handle: socket.assigns.current_user.handle || "user-#{socket.assigns.current_user.id}"
    }

    # Update the threads list component
    send_update(
      WindyfallWeb.ThreadsComponent,
      id: "threads-list",
      action: :prepend_thread,
      thread: thread_data
    )

    {:noreply, assign(socket, show_new_thread: false)}
  end

  def handle_info(:cancel_new_thread, socket) do
    {:noreply, assign(socket, :show_new_thread, false)}
  end

  defp context_type(topic_path, user_handle) do
    cond do
      topic_path -> :topic
      user_handle -> :user
      true -> :global
    end
  end

  defp context_id(topic, user_handle, current_user) do
    cond do
      topic -> topic.id
      user_handle -> current_user.id
      true -> nil
    end
  end

  def handle_info({:thread_created, thread}, socket) do
    Phoenix.PubSub.broadcast(
      Windyfall.PubSub,
      "threads",
      {:new_thread, 
        Map.from_struct(thread) 
        |> Map.take([:id, :title, :message_count, :inserted_at, :user_id])
        |> Map.put(:title, thread.title || "New thread")
      }
    )
    
    {:noreply, socket |> assign(:show_new_thread, false)}
  end

  @doc """
  Handles updates when a reaction's count or user list changes.
  Receives the full reaction map from the cache.
  """
  def handle_info({:reaction_updated, mid, updated_reaction_map}, socket) do
    emoji = updated_reaction_map.emoji
    current_user_id = socket.assigns.current_user.id

    # 1. Update socket.assigns.reactions (This part seems okay)
    new_reactions = Map.update(socket.assigns.reactions, mid, [updated_reaction_map], fn existing_reactions ->
      others = Enum.reject(existing_reactions, &(&1.emoji == emoji))
      [updated_reaction_map | others]
    end)

    # 2. Update socket.assigns.user_reactions (Revised Logic)
    # Get the current set for the message, defaulting to an empty set if the message ID doesn't exist yet
    current_emojis_set = Map.get(socket.assigns.user_reactions, mid, MapSet.new())

    # Determine the new set based on whether the current user is in the broadcasted user list
    new_emojis_set =
      if MapSet.member?(updated_reaction_map.users, current_user_id) do
        MapSet.put(current_emojis_set, emoji) # Add the emoji
      else
        MapSet.delete(current_emojis_set, emoji) # Remove the emoji
      end

    # Update the user_reactions map, removing the key if the set becomes empty
    new_user_reactions =
      if MapSet.size(new_emojis_set) > 0 do
        Map.put(socket.assigns.user_reactions, mid, new_emojis_set)
      else
        # If the set is empty after update, remove the message ID key entirely
        Map.delete(socket.assigns.user_reactions, mid)
      end

    {:noreply,
      socket
      |> assign(:reactions, new_reactions)
      |> assign(:user_reactions, new_user_reactions)} # Assign the correctly updated map
  end

  @doc """
  Handles updates when a reaction is completely removed (count becomes 0).
  """
  def handle_info({:reaction_removed, mid, removed_reaction_info}, socket) do
    # `removed_reaction_info` is %{emoji: ..., message_id: ...}
    emoji_to_remove = removed_reaction_info.emoji

    # 1. Update socket.assigns.reactions
    new_reactions = Map.update(socket.assigns.reactions, mid, [], fn existing_reactions ->
      # Remove the reaction entry for this emoji
      Enum.reject(existing_reactions, &(&1.emoji == emoji_to_remove))
    end)
    # Optional: If the list for `mid` becomes empty, remove the `mid` key itself
    new_reactions = if Map.get(new_reactions, mid) == [] do
      Map.delete(new_reactions, mid)
    else
      new_reactions
    end

    # 2. Update socket.assigns.user_reactions (for the current user)
    new_user_reactions = Map.update(socket.assigns.user_reactions, mid, MapSet.new(), fn current_emojis_set ->
      # Ensure the removed emoji is not in the set for the current user
      MapSet.delete(current_emojis_set, emoji_to_remove)
    end)
    # Optional: Clean up empty MapSets
    new_user_reactions = if Map.get(new_user_reactions, mid) == MapSet.new() do
        Map.delete(new_user_reactions, mid)
    else
        new_user_reactions
    end

    {:noreply, 
      socket
      |> assign(:reactions, new_reactions)
      |> assign(:user_reactions, new_user_reactions)}
  end

  def handle_info(%{event: "reaction_rollback", payload: payload}, socket) do
    # Rollback parent state if needed
    {rolled_reactions, rolled_user_reactions} = 
      rollback_reaction_state(
        socket.assigns.reactions,
        socket.assigns.user_reactions,
        payload.message_id,
        payload.emoji,
        payload.user_id,
        payload.original_count,
        payload.action
      )

    {:noreply,
     socket
     |> assign(:reactions, rolled_reactions)
     |> assign(:user_reactions, rolled_user_reactions)}
  end

  defp rollback_reaction_state(reactions, user_reactions, message_id, emoji, user_id, original_count, original_action) do
    # Update reactions structure
    updated_reactions =
      Map.update(reactions, message_id, [], fn reactions_list ->
        case Enum.split_with(reactions_list, &(&1.emoji == emoji)) do
          {[found], rest} ->
            # Reaction exists - update count and users
            updated_users =
              case original_action do
                :add -> MapSet.delete(found.users, user_id)
                :remove -> MapSet.put(found.users, user_id)
              end

            [%{found | count: original_count, users: updated_users} | rest]

          {[], _} when original_action == :remove ->
            # Reaction was optimistically removed - recreate it
            [%{
              emoji: emoji,
              count: original_count,
              users: MapSet.new([user_id]),
              message_id: message_id
            } | reactions_list]

          {[], rest} ->
            # No reaction found and no recreation needed
            rest
        end
        |> Enum.sort_by(& &1.emoji)  # Maintain consistent order
      end)

    # Update user reactions
    updated_user_reactions =
      Map.update(user_reactions, message_id, MapSet.new(), fn emojis ->
        case original_action do
          :add -> MapSet.delete(emojis, emoji)
          :remove -> MapSet.put(emojis, emoji)
        end
      end)

    {updated_reactions, updated_user_reactions}
  end

  def handle_info({:handle_reaction, payload}, socket) do
    # 1. Optimistically update parent state
    {new_reactions, new_user_reactions} = 
      update_reaction_state(
        socket.assigns.reactions,
        socket.assigns.user_reactions,
        payload.message_id,
        payload.emoji,
        payload.user_id,
        payload.action
      )

    # 2. Immediately broadcast to all clients
    WindyfallWeb.Endpoint.broadcast!(
      "thread:#{socket.assigns.thread_id}",
      "reaction_updated",
      Map.merge(payload, %{
        optimistic: true,
        transaction_id: payload.transaction_id
      })
    )

    # 3. Update parent state optimistically
    socket = socket
      |> assign(:reactions, new_reactions)
      |> assign(:user_reactions, new_user_reactions)

    # 4. Perform DB operation async
    Task.start(fn ->
      add_message_result = Messages.add_reaction(payload.message_id, payload.user_id, payload.emoji)
      case add_message_result do
        {:ok, :add} ->
          # Confirmation not needed - already broadcasted
          :noop

        {:ok, :remove} ->
          :noop

        {:ok, :confirmed} ->
          # Broadcast confirmation to stabilize UI
          WindyfallWeb.Endpoint.broadcast!(
            "thread:#{socket.assigns.thread_id}",
            "reaction_confirmed",
            %{
              message_id: payload.message_id,
              emoji: payload.emoji,
              user_id: payload.user_id
            }
          )

        {:error, _} ->
          # Broadcast rollback
          WindyfallWeb.Endpoint.broadcast!(
            "thread:#{socket.assigns.thread_id}",
            "reaction_rollback",
            %{
              transaction_id: payload.transaction_id,
              message_id: payload.message_id,
              emoji: payload.emoji,
              original_count: payload.original_count
            }
          )
      end
    end)

    {:noreply, socket}
  end

  # --- Handle Message Updated Broadcast ---
  def handle_info(%{event: "message_updated", payload: %{id: message_id, message: new_content}}, socket) do
     # Find the message in the groups and update its text
     updated_messages = update_message_content(socket.assigns.messages, message_id, new_content)
     {:noreply, assign(socket, :messages, updated_messages)}
  end

  # --- Handle Deletion ---
  def handle_info({:delete_message, message_id}, socket) do
    user_id = socket.assigns.current_user.id

    case Messages.delete_message(message_id, user_id) do
      {:ok, _deleted_message} ->
        # Broadcast deletion event
        WindyfallWeb.Endpoint.broadcast(PubSubTopics.thread(socket.assigns.thread_id), "message_deleted", %{id: message_id})

        # Remove message locally (will be handled by message_deleted handler)
        {:noreply, socket} # No immediate state change, rely on broadcast handler

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Message not found.")}

      {:error, :unauthorized} ->
        IO.inspect "unauthorized delete"
        {:noreply, put_flash(socket, :error, "You cannot delete this message.")}

      {:error, _changeset_or_reason} ->
         {:noreply, put_flash(socket, :error, "Could not delete message.")}
    end
  end

  # --- Handle Message Deleted Broadcast ---
  def handle_info(%{event: "message_deleted", payload: %{id: message_id}}, socket) do
    # Remove the message from the grouped list
    new_messages = remove_message_from_groups(socket.assigns.messages, message_id)

    # Also remove associated reactions etc.
    new_reactions = Map.delete(socket.assigns.reactions, message_id)
    new_user_reactions = Map.delete(socket.assigns.user_reactions, message_id)
    new_replied_to = Map.delete(socket.assigns.replied_to_map, message_id)

    # TODO: If a deleted message was being replied to by another message,
    # we might need to update the reply context display of the child message.

    {:noreply,
      socket
      |> assign(:messages, new_messages)
      |> assign(:reactions, new_reactions)
      |> assign(:user_reactions, new_user_reactions)
      |> assign(:replied_to_map, new_replied_to)
    }
  end

  @impl true
  def handle_info({:copy_link, message_id}, socket) when is_integer(message_id) do
    # Fetch the message struct - needed by generate_message_link
    case Repo.get(Message, message_id) do
      nil ->
        # Message not found (maybe deleted?)
        {:noreply, put_flash(socket, :error, "Could not find message to copy link.")}

      message ->
        # Generate the full URL using the context helper
        full_url = Messages.generate_message_link(message)

        # Construct the absolute URL (needed for clipboard in some cases)
        # Use the endpoint URL helper
        absolute_url = WindyfallWeb.Endpoint.url() <> full_url

        # Push the event to the browser with the content to copy
        {:noreply, push_event(socket, "clipboard-copy", %{content: absolute_url})}
    end
  end

  @impl true
  def handle_info({:close_share_modal}, socket) do
    # Reset modal state when closed
    socket =
      socket
      |> assign(:show_share_modal, false)
      |> assign(:sharing_item_type, nil)
      |> assign(:sharing_item_id, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:confirm_share, details}, socket) do
    %{item_type: item_type, item_id: item_id, target: target} = details
    target_type = String.to_existing_atom(target["type"]) # :topic or :user
    target_id = target["id"] # Topic ID or User ID

    IO.inspect({:confirm_share, item_type, item_id, target_type, target_id}, label: "Confirming Share")

    case Messages.share_item(item_type, item_id, target_type, target_id, socket.assigns.current_user) do
      {:ok, _share} ->
        socket =
          socket
          |> put_flash(:info, "Successfully shared!")
          |> assign(:show_share_modal, false) # Close modal on success
          |> assign(:sharing_item_type, nil)
          |> assign(:sharing_item_id, nil)
        {:noreply, socket}

      {:error, reason} ->
         # Keep modal open, show error
        IO.inspect reason, label: "failed to share reason"
        IO.inspect format_share_error(reason), label: "formatted share reason"
        error_msg = "Failed to share: #{format_share_error(reason)}"
        {:noreply, put_flash(socket, :error, error_msg)}
    end
  end

  @impl true
  def handle_info(%{event: "thread_updated", payload: thread_preview_data}, socket) do
    # Get the context this ChatLive instance is currently displaying
    current_context = socket.assigns.context

    # Check if the updated thread belongs to the current context
    is_relevant = case current_context.type do
      :topic ->
        thread_preview_data.topic_id == current_context.id
      :user ->
        thread_preview_data.user_id == current_context.id
      :global ->
        # In a global view, all updates might be relevant, or maybe filter somehow?
        # Let's assume global shows all for now.
        true # Or add specific filtering if needed for global view
      _ ->
        false # Unknown context type
    end

    if is_relevant do
      # Send the updated preview data to the ThreadsComponent instance
      send_update(
        WindyfallWeb.ThreadsComponent,
        id: "threads-list", # Ensure this matches the component's ID
        action: :update_thread_item,
        thread_data: thread_preview_data
      )
    end

    {:noreply, socket}
  end

  defp update_reaction_state(reactions, user_reactions, message_id, emoji, user_id, action) do
    current_reactions = Map.get(reactions, message_id, [])
    current_user_reacts = Map.get(user_reactions, message_id, MapSet.new())

    {new_reaction_list, new_user_reacts} = 
      case action do
        :add ->
          updated_reactions = 
            case Enum.find(current_reactions, &(&1.emoji == emoji)) do
              nil -> [%{emoji: emoji, count: 1, users: MapSet.new([user_id])} | current_reactions]
              reaction -> 
                updated = %{
                  reaction | 
                  count: reaction.count + 1,
                  users: MapSet.put(reaction.users, user_id)
                }
                [Map.put(updated, :message_id, message_id) | Enum.reject(current_reactions, &(&1.emoji == emoji))]
            end
          {updated_reactions, MapSet.put(current_user_reacts, emoji)}

        :remove ->
          updated_reactions = 
            case Enum.find(current_reactions, &(&1.emoji == emoji)) do
              nil -> current_reactions
              reaction ->
                updated = %{
                  reaction | 
                  count: max(reaction.count - 1, 0),
                  users: MapSet.delete(reaction.users, user_id)
                }
                if updated.count > 0 do
                  [updated | Enum.reject(current_reactions, &(&1.emoji == emoji))]
                else
                  Enum.reject(current_reactions, &(&1.emoji == emoji))
                end
            end
          {updated_reactions, MapSet.delete(current_user_reacts, emoji)}
      end

    new_reactions = Map.put(reactions, message_id, new_reaction_list)
    new_user_reactions = Map.put(user_reactions, message_id, new_user_reacts)

    {new_reactions, new_user_reactions}
  end

  defp stream_messages(socket, messages) do
    Enum.reduce(messages, socket, fn msg, sock ->
      reactions = Messages.process_reactions2(msg)
      sock
      |> stream(:messages, %{
        id: msg.id,
        content: msg.content,
        inserted_at: msg.inserted_at,
        user_id: msg.user.id,
        display_name: msg.user.name,
        profile_image: msg.user.avatar
      })
      |> stream(:reactions, reactions, for: msg.id)
    end)
  end

  defp stream_bulk_messages(socket, raw_messages) do
    processed_messages = Enum.map(raw_messages, fn msg ->
      # Ensure user is preloaded and provide defaults if missing
      user = msg.user || %{id: nil, display_name: "Anonymous", profile_image: "/images/default-avatar.png"}
      %{
        id: msg.id,
        message: msg.message,
        inserted_at: msg.inserted_at,
        user_id: user.id,
        display_name: user.display_name,
        profile_image: user.profile_image,
        # Maybe remove reactions from here if components rely solely on assigns?
        # reactions: ... # Or format them as needed by stream consumers
      }
    end)

    # Decide if :reactions stream is still needed. If MessageComponent relies
    # entirely on the assigns passed during update, this might be redundant.
    # Let's assume it's still used for now, but it might be optimizable later.
    # The reaction data needs formatting suitable for the stream consumers.
    # Let's pass an empty list for reactions stream here and rely on component updates.
    socket
    |> stream(:messages, processed_messages, reset: true)
    # |> stream(:reactions, processed_reactions) # Potentially remove or format differently
  end

  defp get_group_reactions(all_reactions, group) do
    group_messages = Enum.map(group.messages, & &1.id)
    Map.take(all_reactions, group_messages)
  end

  defp get_group_user_reactions(all_user_reactions, group) do
    group_messages = Enum.map(group.messages, & &1.id)
    Map.take(all_user_reactions, group_messages)
  end

  defp update_reaction_count(reactions, mid, emoji, count) do
    message_reactions = Map.get(reactions, mid, %{})
    updated = Map.put(message_reactions, emoji, count)
    Map.put(reactions, mid, updated)
  end

  defp maybe_get_reply_parent_info(message) do
    # This requires message to have preloaded :replying_to and its :user
    if parent = message.replying_to do
       parent_user = parent.user || %{display_name: "Unknown User"}
       %{
          id: parent.id,
          text: parent.message,
          user_display_name: parent_user.display_name
       }
    else
      nil
    end
  end

  defp reload_threads(socket) do
    context = socket.assigns.context
    filter = case context.type do
      :topic -> {:topic_id, context.id}
      :user -> {:user_id, context.id}
      _ -> nil
    end

    threads = if filter, do: Messages.list_threads(filter), else: []

    socket
    |> assign(:threads, threads)
    |> assign(:show_new_thread, false)
  end

  defp traverse_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} -> 
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k} #{v}" end)
    |> Enum.join(", ")
  end

  # --- Helper to update message content in groups ---
  defp update_message_content(groups, message_id, new_content) do
    Enum.map(groups, fn group ->
      %{group | messages: Enum.map(group.messages, fn msg ->
                   if msg.id == message_id do
                     %{msg | text: new_content}
                   else
                     msg
                   end
                 end)}
    end)
  end

  # --- Helper to remove message from groups ---
  defp remove_message_from_groups(groups, message_id_to_remove) do
    groups
    |> Enum.map(fn group ->
        # Filter out the message from the current group
        filtered_messages = Enum.reject(group.messages, fn msg -> msg.id == message_id_to_remove end)
        # Update the group with the filtered messages
        %{group | messages: filtered_messages}
      end)
    |> Enum.reject(fn group -> Enum.empty?(group.messages) end) # Remove groups that become empty
    # Optional: Consider regrouping if a deletion splits a group, but might be complex.
    # For now, just remove the message. Regrouping might happen naturally on next load.
  end

  defp parse_int_or_nil(nil), do: nil
  defp parse_int_or_nil(""), do: nil
  defp parse_int_or_nil(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # Helper to get current path and add/replace fragment
  defp current_path_with_fragment(socket, fragment) do
    # Use the stored full URI string
     uri = URI.parse(socket.assigns.current_path || "/")
     %{uri | fragment: fragment} |> URI.to_string()
  end

  defp format_share_error(:invalid_item_type), do: "Invalid item type."
  defp format_share_error(:invalid_target_type), do: "Invalid share target."
  defp format_share_error({:changeset, changeset}), do: traverse_errors(changeset) # Reuse existing helper
  defp format_share_error(other), do: Atom.to_string(other)

  defp determine_context_from_params(params, current_user) do
    cond do
      # --- Topic Context ---
      topic_path = params["topic_path"] ->
        case Messages.get_topic(topic_path) do
          nil -> {nil, "Topic not found: #{topic_path}"}
          topic ->
            context = %{type: :topic, id: topic.id, name: topic.name, path: topic.path}
            {context, nil}
        end

      # --- User Context by Handle ---
      handle = params["user_handle"] ->
        case Accounts.get_user_by_handle(handle) do # Assumes Accounts.get_user_by_handle exists
          nil -> {nil, "User not found: @#{handle}"}
          user ->
            context = %{type: :user, id: user.id, name: "#{user.display_name}'s Threads", handle: user.handle}
            {context, nil}
        end

      # --- User Context by ID ---
      user_id_str = params["user_id"] ->
        case user_id_str |> String.to_integer() |> Accounts.get_user() do # Assumes Accounts.get_user/1 exists
          nil -> {nil, "User not found: ID #{user_id_str}"}
          user ->
            # Use handle in context map if available, otherwise maybe just name
            context = %{type: :user, id: user.id, name: "#{user.display_name}'s Threads", handle: user.handle}
            {context, nil}
        end

      # --- Default/Global Context ---
      true ->
        context = %{type: :global, id: nil, name: "All Threads"}
        {context, nil}
    end
  end

  # Helper to load messages (extracted logic from handle_params)
  defp load_messages_based_on_params(thread_id, fragment) do
    target_message_id_str = fragment && String.trim_leading(fragment, "message-")
    case target_message_id_str |> parse_int_or_nil() do
        target_id when not is_nil(target_id) and not is_nil(thread_id) ->
          {msgs, at_beg, at_end} = Messages.messages_around(thread_id, target_id)
          {msgs, at_beg, at_end, target_id, :around_target}
        _ ->
           if thread_id do
             {msgs, at_beg} = Messages.messages_before([], thread_id)
             {msgs, at_beg, false, nil, :latest}
           else
             {[], true, true, nil, :none}
           end
      end
  end

  defp can_post_in_context?(context, current_user) do
    case context.type do
      :topic ->
        # Allow posting in topics if logged in (adjust rule if needed)
        !is_nil(current_user)

      :user ->
        # Allow posting on a user page ONLY if the visitor is the owner
        !is_nil(current_user) && context.owner_id == current_user.id

      :global ->
        # Disallow posting in global context
        false

      _ ->
        # Default deny
        false
    end
  end
end
