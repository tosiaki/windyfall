defmodule WindyfallWeb.ThreadsComponent do
  use WindyfallWeb, :live_component

  alias Windyfall.Messages
  alias WindyfallWeb.CoreComponents
  alias WindyfallWeb.DateTimeHelpers

  attr :current_user_id, :integer, required: true
  attr :profile_tab, :atom, default: :threads

  def mount(socket) do
    socket =
      socket
      |> assign(:items, [])
      |> assign(:creating, "false")
      |> assign(:bookmark_status_set, MapSet.new())

    {:ok, socket}
  end

  def update(assigns, socket) do
    # --- Assign updated state ---
    socket =
      socket
      |> assign(assigns) # Assign all passed assigns (context, user_id, tab, etc.)
      |> fetch_and_assign_items()

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div id={"threads-component-#{@id}"} class="h-full bg-[var(--color-surface)]">
      In threads live variable
      <%= Enum.join(@bookmark_status_set, ", ") %>
      <%# --- ADD Tabs for User Profile Context --- %>
      <%= if @context.type == :user do %>
        <div class="sticky top-0 z-10 bg-[var(--color-surface)]/80 backdrop-blur-sm border-b border-[var(--color-border)]">
          <nav class="-mb-px flex space-x-6 px-4 justify-center" aria-label="Tabs">
            <.tab_button
              label="Posts"
              active={@profile_tab == :threads}
              click_event="set_profile_tab"
              click_value="threads"
              target={@myself}
            />
            <.tab_button
              label="Bookmarks"
              active={@profile_tab == :bookmarks}
              click_event="set_profile_tab"
              click_value="bookmarks"
              target={@myself}
            />
            <%# Add more tabs like "Likes", "Media" later %>
          </nav>
        </div>
      <% end %>

      <div class="divide-y divide-[var(--color-border)]">
        <%= if @items == [] do %>
          <div class="p-8 text-center text-[var(--color-text-secondary)]">
            <%= if @profile_tab == :bookmarks do %>
              <%# Check if viewing own profile or someone else's %>
              <%= if @context.type == :user && @context.id == @current_user_id do %>
                <%# Viewing own profile, no bookmarks %>
                You haven't bookmarked any posts yet. Use the <.icon name="hero-bookmark" class="inline-block w-4 h-4 align-text-bottom text-yellow-500"/> icon to save posts for later.
              <% else %>
                <%# Viewing someone else's profile, they have no bookmarks %>
                <%= @context.name |> String.replace("'s Profile", "") %> hasn't bookmarked any posts yet.
              <% end %>
            <% else %>
              <%# Empty state for the :threads tab %>
              No posts here yet.
              <%= if @can_post do %>
                Why not start one?
              <% end %>
            <% end %>
          </div>
        <% else %>
          <div class="overflow-y-auto" style="max-height: calc(100vh - 12rem);"> <%# Adjusted height %>
            <%= for %{type: item_type, item: item_data} <- @items do %>
              <%= case item_type do %>
                <% :thread -> %>
                  <% thread_map = item_data %>
                  <div class="relative border-b border-[var(--color-border)]">
                    <%# --- Shared Message Header --- %>
                    <%= if !is_nil(thread_map.spin_off_of_message_id) && @profile_tab != :bookmarks do %>
                      <div class="px-4 pt-2 pb-1 text-xs text-[var(--color-text-secondary)] flex items-center gap-1.5">
                         <.icon name="hero-link" class="w-3.5 h-3.5 text-blue-500" />
                         Shared Message
                      </div>
                    <% end %>

                    <.live_component
                      module={WindyfallWeb.Threads.ThreadItem}
                      id={"thread-item-#{thread_map.id}"}
                      thread={thread_map}
                      selected={thread_map.id == @selected_thread_id}
                      view_mode={@mode}
                      # Pass bookmark status and target
                      is_bookmarked={MapSet.member?(@bookmark_status_set, thread_map.id)}
                      target={@myself}
                    />
                  </div>

                <% :share -> %>
                   <%# --- Share Item Rendering --- %>
                   <%# Only render shares when on the :threads tab %>
                   <%= if @profile_tab == :threads do %>
                      <%# ... existing share rendering logic ... %>
                       <% share = item_data %>
                       <% shared_thread = share.thread %>
                       <% sharer = share.user %>
                       <% creator = shared_thread.creator %>
                       <% first_msg_text = case shared_thread.messages do [m | _] -> m.message; _ -> "" end %>
                       <% preview_text = WindyfallWeb.TextHelpers.truncate(first_msg_text, 280) %>
                       <% thread_display_data = %{ # Reconstruct original thread data
                            id: shared_thread.id, title: shared_thread.title,
                            message_count: shared_thread.message_count, last_message_at: shared_thread.last_message_at,
                            inserted_at: shared_thread.inserted_at, creator_id: shared_thread.creator_id,
                            author_name: creator.display_name, author_avatar: creator.profile_image,
                            user_handle: creator.handle, first_message_preview: preview_text,
                            spin_off_of_message_id: shared_thread.spin_off_of_message_id
                          }
                       %>
                      <div class="relative border-b border-[var(--color-border)]">
                        <%# "Shared by" header %>
                        <div class="px-4 pt-2 pb-1 text-xs text-[var(--color-text-secondary)] flex items-center gap-1.5">
                          <.icon name="hero-arrow-path-rounded-square" class="w-3.5 h-3.5 text-green-500" />
                          Shared by <.link navigate={CoreComponents.user_profile_path(sharer.id, sharer.handle)} class="font-medium hover:underline"><%= sharer.display_name %></.link>
                          <span>· <%= DateTimeHelpers.time_ago(share.inserted_at) %></span>
                        </div>
                        <%# Render the actual ThreadItem using the original thread's data %>
                        <.live_component
                          module={WindyfallWeb.Threads.ThreadItem}
                          id={"shared-item-#{share.id}-thread-#{thread_display_data.id}"}
                          thread={thread_display_data}
                          selected={thread_display_data.id == @selected_thread_id}
                          view_mode={@mode}
                          is_bookmarked={MapSet.member?(@bookmark_status_set, thread_display_data.id)}
                          target={@myself}
                        />
                      </div>
                    <% end %>

                <% _ -> %>
                   <%# Fallback %>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("create_topic", %{ "topic_name" => topic_name }, socket) do
    Messages.create_topic(topic_name, socket.assigns.topic_path) # Ensure topic_path is assigned if used
    topic = Messages.get_topic(socket.assigns.topic_path)
    {:noreply, assign(socket, :topic, topic)}
  end

  @impl true
  def handle_event("toggle_bookmark", %{"thread-id" => thread_id_str}, socket) do
    current_user_id = socket.assigns.current_user_id
    if !current_user_id do
      # Still good practice to check if user is logged in
      {:noreply, put_flash(socket, :error, "You must be logged in to bookmark.")}
    else
      thread_id = String.to_integer(thread_id_str)

      # Attempt the database operation
      case Messages.toggle_bookmark(current_user_id, thread_id) do
        {:ok, action} -> # action is :bookmarked or :unbookmarked
          # --- ONLY Update the local bookmark status set ---
          new_status_set =
            case action do
              :bookmarked -> MapSet.put(socket.assigns.bookmark_status_set, thread_id)
              :unbookmarked -> MapSet.delete(socket.assigns.bookmark_status_set, thread_id)
            end

          # Assign the new set. This assign change is enough to trigger
          # the re-render needed to update the icon in the relevant ThreadItem.
          # DO NOT refetch or modify the @items list here.
          {:noreply, assign(socket, :bookmark_status_set, new_status_set)}

        {:error, reason} ->
          # Handle database errors
          {:noreply, put_flash(socket, :error, "Could not update bookmark: #{reason}")}
      end
    end
  end

  @impl true
  def handle_event("set_profile_tab", %{"tab" => tab_str}, socket) do
    new_tab = String.to_existing_atom(tab_str)

    # Assign the new tab state FIRST
    socket =
      socket
      |> assign(:profile_tab, new_tab)
      |> fetch_and_assign_items()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:update_thread_item, thread_data}, socket) do
    # thread_data is the map received from the broadcast via ChatLive

    # Check if the updated item type is :thread (it should be)
    updated_item = %{type: :thread, item: thread_data, sort_key: thread_data.last_message_at || thread_data.inserted_at}
    updated_thread_id = thread_data.id

    # Update the @items list:
    # 1. Remove the old version of the thread (if it exists)
    # 2. Prepend the new version
    # 3. Re-sort based on the sort_key (which uses last_message_at)
    new_items =
      socket.assigns.items
      # Filter out the old item if present (match on type and id)
      |> Enum.reject(fn %{type: t, item: i} -> t == :thread and i.id == updated_thread_id end)
      # Prepend the new item data
      |> List.insert_at(0, updated_item)
      # Re-sort the list (ensure sort_key is comparable, NaiveDateTime works)
      |> Enum.sort_by(& &1.sort_key, {:desc, NaiveDateTime})

    # Also update the bookmark status for the updated thread if needed
    # (Though bookmark status isn't usually affected by new messages)
    # new_bookmark_status = update_bookmark_status(socket.assigns.bookmark_status_set, updated_thread_id, ...)

    socket =
      socket
      |> assign(:items, new_items)
      # |> assign(:bookmark_status_set, new_bookmark_status) # Assign if updated

    {:noreply, socket}
  end

  # Helper component for tabs
  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click={@click_event}
      phx-value-tab={@click_value}
      phx-target={@target}
      role="tab"
      aria-selected={@active}
      class={[
        "whitespace-nowrap border-b-2 py-3 px-1 text-sm font-medium",
        if(@active,
          do: "border-[var(--color-primary)] text-[var(--color-primary)]",
          else: "border-transparent text-[var(--color-text-secondary)] hover:border-gray-300 hover:text-[var(--color-text)]"
        )
      ]}
    >
      <%= @label %>
    </button>
    """
  end

  defp fetch_and_assign_items(socket) do
    context = socket.assigns.context
    profile_tab = socket.assigns.profile_tab || :threads
    current_user_id = socket.assigns.current_user_id # Visitor's ID

    # --- Fetch items based on tab AND context ---
    items = case {profile_tab, context.type} do
      # On Bookmarks tab AND viewing a User profile -> Fetch THAT user's bookmarks
      {:bookmarks, :user} ->
        profile_owner_id = context.id # ID of the user whose profile is being viewed
        Messages.list_bookmarked_threads(profile_owner_id) # Use profile owner's ID
        |> Enum.map(&%{type: :thread, item: &1, sort_key: &1.bookmarked_at})

      # On Bookmarks tab but NOT a user profile (e.g., topic) -> Show nothing (or maybe error?)
      {:bookmarks, _} ->
        [] # Bookmarks tab only makes sense on user profiles for now

      # On Threads tab (any context) -> Fetch context items (posts/shares)
      {:threads, _} ->
        filter = case context.type do
          :topic -> {:topic_id, context.id}
          :user -> {:user_id, context.id} # Use profile owner's ID
          _ -> nil
        end
        if filter, do: Messages.list_context_items(filter), else: []
    end

    # --- Fetch VISITOR's bookmark status for the DISPLAYED threads ---
    thread_ids =
      items
      |> Enum.filter(&(&1.type == :thread))
      |> Enum.map(& &1.item.id)

    # Fetch status based on the VISITOR (current_user_id)
    bookmark_status_set = if current_user_id && thread_ids != [] do
      Messages.get_user_bookmark_status(current_user_id, thread_ids)
    else
      MapSet.new() # Default to empty if not logged in or no threads displayed
    end

    # --- Assign updated state ---
    socket
    |> assign(:items, items)
    |> assign(:bookmark_status_set, bookmark_status_set) # Visitor's status for displayed items
  end
end
