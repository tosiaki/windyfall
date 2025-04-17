defmodule WindyfallWeb.Chat.MessageComponent do
  use WindyfallWeb, :live_component

  import Ecto.UUID, only: [generate: 0]

  alias WindyfallWeb.DateTimeHelpers
  alias WindyfallWeb.CoreComponents
  import WindyfallWeb.TextHelpers

  attr :group, :map, required: true
  attr :current_user, :map, required: true

  @impl true
  def mount(socket) do
    {:ok, 
     socket
     |> assign(reactions: %{})
     |> assign(user_reactions: %{})
     |> assign(show_menu: %{})
     |> stream_configure(:reactions, dom_id: &"reaction-#{&1.message_id}-#{&1.emoji}")
     |> stream(:reactions, [])
    }
  end

  @impl true
  def update(assigns, socket) do
    editing_message_id = assigns[:editing_message_id]
    editing_content = assigns[:editing_content] || "" # Default to empty string if nil

    group = assigns.group
    current_user = assigns.current_user
    raw_reactions_map = assigns.reactions # e.g., %{mid => [%{emoji:.., count:.., users:..}]}
    raw_user_reactions_map = assigns.user_reactions # e.g., %{mid => MapSet<emoji>}

    # 1. Calculate the user_reactions set for the current user for styling
    user_reactions_set =
      raw_user_reactions_map
      |> Enum.flat_map(fn {msg_id, emojis_set} ->
           Enum.map(emojis_set, &{msg_id, &1})
         end)
      |> MapSet.new()

    # 2. Prepare stream entries from the raw reactions map
    stream_entries =
      raw_reactions_map
      |> Enum.flat_map(fn {msg_id, reactions_list} ->
           Enum.map(reactions_list, fn reaction ->
             %{
               # Use map structure expected by stream_configure/template
               id: "ignored in reset", # ID is set by dom_id in stream_configure
               emoji: reaction.emoji,
               count: reaction.count,
               message_id: msg_id
             }
           end)
         end)

    replied_to_map_for_group =
      Map.take(assigns.replied_to_map || %{}, Enum.map(assigns.group.messages, & &1.id))

    # 3. Update socket assigns
    socket =
      socket
      |> assign(assigns)
      |> assign(
           group: group,
           current_user: current_user,
           is_user: group.user_id == current_user.id,
           message_count: length(group.messages),
           message_ids: Enum.map(group.messages, & &1.id),
           # Store the calculated set for reaction_classes helper
           user_reactions: user_reactions_set,
           replied_to_map: replied_to_map_for_group,
           # Raw maps might not be needed in assigns if processed fully here
           # reactions: raw_reactions_map, # Optional assign
           # Store show_menu state if needed across updates
           show_menu: socket.assigns.show_menu,
           editing_message_id: editing_message_id,
           editing_content: editing_content
         )
      # 4. Reset and populate the stream with current data
      |> stream(:reactions, stream_entries, reset: true)

    # Removed tracking presence from component, should be handled by parent
    # if connected?(socket), do: track_presence(socket)

    {:ok, socket}
  end

  defp track_presence(socket) do
    message_ids = socket.assigns.group.messages |> Enum.map(& &1.id)
    Enum.each(message_ids, fn mid ->
      WindyfallWeb.Presence.track_active_message(self(), mid)
    end)
  end

  defp process_reaction_updates(socket, new_raw_reactions) do
    # Convert new reactions to counts structure
    new_reaction_counts = 
      new_raw_reactions
      |> Enum.reduce(%{}, fn {msg_id, reactions}, acc ->
        counts = 
          reactions
          |> Enum.map(fn r -> {r.emoji, r.count} end)
          |> Map.new()
        Map.put(acc, msg_id, counts)
      end)

    # Get previous counts
    old_reaction_counts = socket.assigns.reaction_counts

    # Process each message in the group
    Enum.reduce(socket.assigns.message_ids, socket, fn msg_id, acc ->
      process_message_reactions(
        acc,
        msg_id,
        Map.get(old_reaction_counts, msg_id, %{}),
        Map.get(new_reaction_counts, msg_id, %{})
      )
    end)
    |> assign(:reaction_counts, new_reaction_counts)
  end

  defp process_message_reactions(socket, msg_id, old_counts, new_counts) do
    # Combine all emojis that existed in either state
    old_emojis = Map.keys(old_counts) |> MapSet.new()
    new_emojis = Map.keys(new_counts) |> MapSet.new()
    
    all_emojis = 
      MapSet.union(old_emojis, new_emojis)
      |> MapSet.to_list()

    Enum.reduce(all_emojis, socket, fn emoji, acc ->
      reaction_id = "reaction_#{msg_id}_#{emoji}"
      old_count = Map.get(old_counts, emoji, 0)
      new_count = Map.get(new_counts, emoji, 0)

      cond do
        new_count > 0 && new_count != old_count ->
          # Update or insert reaction
          # IO.inspect {reaction_id, emoji, new_count}, label: "This is new reaction thing before stream"
          result = acc
          |> stream_insert(:reactions, %{
            id: reaction_id,
            emoji: emoji,
            count: new_count,
            message_id: msg_id
          })

          # IO.inspect result.assigns.streams.reactions.inserts, label: "after stream_isnert"
          result

        new_count == 0 && old_count > 0 ->
          # Remove reaction
          acc
          |> stream_delete(:reactions, %{id: reaction_id})

        true ->
          # No change needed
          acc
      end
    end)
  end

  defp process_user_reaction_updates(socket, new_user_reactions) do
    # Convert to MapSet of {message_id, emoji} tuples
    new_set = 
      new_user_reactions
      |> Enum.flat_map(fn {msg_id, emojis} -> 
        Enum.map(emojis, &{msg_id, &1})
      end)
      |> MapSet.new()

    assign(socket, :user_reactions, new_set)
  end

  defp current_count(socket, message_id, emoji) do
    socket.assigns.reaction_counts
    |> Map.get(message_id, %{})
    |> Map.get(emoji, 0)
  end

  defp initialize_component(socket, message_ids) do
    # Load reactions only for new messages
    reactions = Messages.get_reactions_for_messages(message_ids)
    user_reactions = Messages.get_user_reactions(message_ids, socket.assigns.current_user.id)

    # Convert to stream items
    stream_items = 
      reactions
      |> Enum.flat_map(fn {msg_id, msg_reactions} ->
        Enum.map(msg_reactions, fn reaction ->
          %{
            id: "reaction_#{msg_id}_#{reaction.emoji}",
            emoji: reaction.emoji,
            count: reaction.count,
            message_id: msg_id
          }
        end)
      end)

    # Subscribe to new message channels
    Enum.each(message_ids, &WindyfallWeb.Endpoint.subscribe("message:#{&1}"))

    # Update socket state
    socket
    |> assign(
      reactions: Map.merge(socket.assigns.reactions || %{}, reactions),
      user_reactions: Map.merge(socket.assigns.user_reactions || %{}, user_reactions)
    )
    |> stream(:reactions, stream_items, reset: false)
  end

  defp diff_message_ids(old_ids, new_ids) do
    added = new_ids -- old_ids
    removed = old_ids -- new_ids
    {added, removed}
  end

  defp unsubscribe_messages(socket, message_ids) do
    Enum.each(message_ids, &WindyfallWeb.Endpoint.unsubscribe("message:#{&1}"))
    # Remove reactions for unsubscribed messages
    socket
    |> update(:reactions, &Map.drop(&1, message_ids))
    |> update(:user_reactions, &Map.drop(&1, message_ids))
  end

  def render(assigns) do
    ~H"""
    <div class={wrapper_classes(@is_user)}>
      <%# Avatar container %>
      <%= if !@is_user do %>
        <div class="shrink-0 self-end pb-1 pr-2"> <%# Align avatar bottom for multi-line messages %>
          <.link navigate={CoreComponents.user_profile_path(@group.user_id, @group.handle)} class="block group" tabindex="-1">
            <img
              class="w-8 h-8 rounded-full object-cover border border-[var(--color-border)] group-hover:opacity-80 transition-opacity"
              src={CoreComponents.user_avatar(@group.profile_image)}
              alt={@group.display_name}
            />
          </.link>
        </div>
      <% end %>

      <div class={"flex flex-col #{if @is_user, do: 'items-end', else: 'items-start'} max-w-[75%] sm:max-w-[65%]"}>
        <%= if !@is_user && @message_count == 1 do %>
          <div class="mb-0.5 text-xs font-medium text-[var(--color-text-secondary)] px-2">
            <.link navigate={CoreComponents.user_profile_path(@group.user_id, @group.handle)} class="hover:underline">
              <%= @group.display_name %>
            </.link>
          </div>
        <% else %>
          <%# Maybe still show name for multi-line groups from others, but don't link every time? Optional styling choice. %>
          <%# Example: show non-linked name for multi-line groups %>
          <%= if !@is_user do %>
            <div class="mb-0.5 text-xs font-medium text-[var(--color-text-secondary)] px-2">
              <%= @group.display_name %>
            </div>
          <% end %>
        <% end %>

        <div class={bubble_classes(@is_user, @message_count)}>
          <%= for {message, idx} <- Enum.with_index(@group.messages) do %>
            <div class="relative group/message message-bubble" 
                 id={"message-#{message.id}"}
                 phx-mouseenter="show_reaction_menu"
                 phx-mouseleave="hide_reaction_menu"
                 phx-value-message-id={message.id}
                 data-message-id={message.id}
                 data-is-user={@is_user}
                 phx-hook="MessageInteractionHook">


              <%# Reaction Picker - positioned by CSS now %>
              <div class="reaction-picker">
                  <%= for emoji <- common_emojis() do %>
                    <span class="reaction-item"> <%# Wrap button in span for styling %>
                      <button
                              phx-click="toggle_reaction"
                              phx-value-emoji={emoji}
                              phx-value-message-id={message.id}
                              phx-target={@myself}
                              aria-label={"React with #{emoji}"}>
                        <%= emoji %>
                      </button>
                    </span>
                  <% end %>
                  <span class="reaction-item">
                    <button
                            title="Reply to this message"
                            phx-click="context_menu_action"
                            phx-value-action="reply"
                            phx-value-message-id={message.id}
                            phx-target={@myself}
                            aria-label="Reply">
                       <.icon name="hero-arrow-uturn-left-mini" class="w-4 h-4 text-[var(--color-text-secondary)]" />
                    </button>
                  </span>
                  <span class="reaction-item">
                    <button
                      type="button"
                      class="more-options-button"
                      aria-label="More message options"
                      data-action="show_context_menu"
                      data-message-id={message.id}
                    >
                      <.icon name="hero-ellipsis-horizontal-mini" class="w-4 h-4" />
                    </button>
                  </span>
              </div>

              <%# Reply Context %>
              <%= if replied_to = @replied_to_map && @replied_to_map[message.id] do %>
                <div
                  class="reply-context"
                  phx-click="jump_to_message"
                  phx-value-jump-to-id={replied_to.id}
                  title={"Replying to #{replied_to.user_display_name}"}
                >
                  <.icon name="hero-arrow-uturn-left-mini" class="icon" />
                  <span class="truncate">
                    <span class="font-medium"><%= replied_to.user_display_name %></span>:
                    <span class="italic">"<%= truncate(replied_to.text, 40) %>"</span>
                  </span>
                </div>
              <% end %>

              <%# Message Content %>
              <div class={message_content_classes(@is_user)}>
                <%= if @editing_message_id == message.id do %>
                  <%# --- Edit Form --- %>
                  <form phx-submit="save_edit"
                        phx-value-message-id={message.id}
                        class="space-y-2"
                        id={"edit-form-#{message.id}"}
                        >
                    <%# --- Replace textarea with React Component --- %>
                    <div class="message-editor-wrapper">
                       <%= live_react_component(
                            "Components.SlateEditor", # Module name as string
                            %{ # Props Map
                              uniqueId: "edit-#{message.id}", # Pass unique ID for editing
                              pushEvent: "update_editor_content",
                              initialValue: @editing_content, # Pass current content
                              hiddenInputName: "content",
                              formId: "edit-form-#{message.id}"
                            },
                            # Options Map (for DOM attributes)
                            id: "slate-editor-edit-#{message.id}",
                            phx_update: "ignore",
                          ) %>
                    </div>

                    <div class="mt-2 flex gap-2 justify-end">
                      <button type="button" phx-click="cancel_edit" class="text-xs text-gray-600 hover:text-gray-900">Cancel</button>
                      <button type="submit" phx-disable-with="Saving..." class="text-xs text-blue-600 hover:text-blue-800 font-medium">Save</button>
                    </div>
                  </form>
                <% else %>
                  <%# --- Render Final Markdown Content --- %>
                  <div class="prose prose-sm max-w-none group/line">
                     <%= render_markdown_with_spoilers(message.text, @myself) %>
                  </div>
                <% end %>

                <%# Timestamp (inside bubble, revealed on hover) %>
                <%= if idx == @message_count - 1 && @editing_message_id != message.id do %>
                  <span class="timestamp">
                    <%= DateTimeHelpers.format_time(message.inserted_at) %>
                  </span>
                <% end %>
              </div>

               <%# Reactions (outside content div for better layout) %>
               <%= if @editing_message_id != message.id do %>
                 <div
                   class="reactions-container"
                   id={"reactions-#{message.id}"}
                   phx-update="stream"
                 >
                   <%= for {dom_id, reaction} <- @streams.reactions do %>
                     <%= if reaction.message_id == message.id do %>
                       <button id={dom_id}
                            class="reaction"
                            phx-click="toggle_reaction"
                            phx-value-emoji={reaction.emoji}
                            phx-value-message-id={message.id}
                            phx-target={@myself}
                            data-count={reaction.count}
                            data-user-reacted={to_string(MapSet.member?(@user_reactions, {message.id, reaction.emoji}))}
                            data-animation={assigns[:reaction_animations][reaction.id] || "none"}
                            aria-label={"#{reaction.count} #{reaction.emoji} reactions"}
                            >
                         <span class="emoji"><%= reaction.emoji %></span>
                         <span class="count"><%= reaction.count %></span>
                       </button>
                     <% end %>
                   <% end %>
                 </div>
               <% end %>

            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp wrapper_classes(is_self) do
    # Base classes for the entire message group row
    "flex mb-1 last:mb-0 #{if is_self, do: 'justify-end pl-10', else: 'justify-start pr-10'}"
  end

  defp bubble_classes(is_self, _count) do
    # Classes for the main bubble container (around all messages in a group)
    base = "flex flex-col w-fit rounded-2xl shadow-sm"
    bg = if is_self, do: "bg-[var(--color-primary)]", else: "bg-[var(--color-surface)] border border-[var(--color-border)]"
    # Adjust corners based on who sent it
    corners = if is_self, do: "rounded-br-md", else: "rounded-bl-md"
    [base, bg, corners] |> Enum.join(" ")
  end

  defp message_content_classes(is_self) do
    # Removed prose here, added to inner div
    color = if is_self, do: "text-[var(--color-text-on-primary)]", else: "text-[var(--color-text)]"
    "relative px-3 pt-1.5 pb-1.5 #{color}" # Keep padding
  end

  defp message_bubble_content_classes(idx, is_self, msg_count) do
    # Extracted for clarity, adjust as needed
    base = ["px-3 py-1"]
    tl = if idx == 0 && !is_self, do: "rounded-tl-lg"
    tr = if idx == 0 && is_self, do: "rounded-tr-lg"
    bl = if idx == msg_count - 1 && !is_self, do: "rounded-bl-lg"
    br = if idx == msg_count - 1 && is_self, do: "rounded-br-lg"
    pt = if idx != 0, do: "pt-0.5"
    pb = if idx != msg_count - 1, do: "pb-0.5"
    [base, tl, tr, bl, br, pt, pb] |> List.flatten() |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end
  defp timestamp_classes(idx, is_self), do: ["absolute top-1/2 -translate-y-1/2 text-xs transition-opacity whitespace-nowrap text-gray-500", if(idx == 0, do: "opacity-100", else: "opacity-0 group-hover/message:opacity-100"), if(!is_self, do: "left-[calc(100%+0.5rem)]", else: "right-[calc(100%+0.5rem)]")] |> Enum.reject(&is_nil/1) |> Enum.join(" ")

  defp reaction_classes(emoji, user_reactions_set, message_id) do
     # Classes for individual reaction buttons
     reacted = MapSet.member?(user_reactions_set, {message_id, emoji})
     # Base classes using Tailwind utilities defined in app.css via @apply
     "reaction"
     |> then(& if reacted, do: &1 <> " reacted", else: &1) # Add custom class if reacted
  end

  defp common_emojis do
    ["👍", "❤️", "😂", "😮", "😢", "🤔", "🎉", "🙏"]
  end

  defp reply_context_color(is_self) do
    # Generate inline style for border/text color based on user
    color = if is_self, do: "rgba(255, 255, 255, 0.6)", else: "var(--color-text-tertiary)"
    "color: #{color}; border-color: #{color};"
  end

  def handle_info(%{event: "reaction_updated", payload: payload}, socket) do
    if payload.optimistic do
      # Apply optimistic update from other users
      new_count = 
        case payload.action do
          :add -> current_count(socket, payload.message_id, payload.emoji) + 1
          :remove -> current_count(socket, payload.message_id, payload.emoji) - 1
        end

      {:noreply,
       socket
       |> update_reaction_count(payload.message_id, payload.emoji, new_count)
       |> update_user_reactions(
            payload.message_id,
            payload.emoji,
            payload.action
          )}
    else
      {:noreply, socket}  # Already handled by parent
    end
  end

  def handle_info(%{event: "reaction_confirmed", payload: payload}, socket) do
    # Remove temporary optimistic state if needed
    {:noreply, socket}
  end

  def handle_info(%{event: "reaction_rollback", payload: payload}, socket) do
    # Rollback to original count
    {:noreply,
     socket
     |> update_reaction_count(payload.message_id, payload.emoji, payload.original_count)
     |> update_user_reactions(
          payload.message_id,
          payload.emoji,
          if(payload.original_count > 0, do: :remove, else: :add)
        )}
  end

  defp reaction_classes(emoji, user_reactions, message_id) do
    # Check if the {message_id, emoji} tuple exists in the MapSet
    reacted = MapSet.member?(user_reactions, {message_id, emoji})
    
    base = "reaction flex items-center gap-1 px-2 py-1 rounded-full bg-gray-100 hover:bg-gray-200 transition-colors cursor-pointer"
    if reacted, do: "#{base} user-reacted border-2 border-blue-400", else: base
  end

  defp subscribe_to_reaction_updates(socket, message_ids) do
    Enum.reduce(message_ids, socket, fn id, sock ->
      WindyfallWeb.Endpoint.subscribe("message:#{id}")
      sock
    end)
  end

  def handle_event("show_reaction_menu", %{"message_id" => message_id}, socket) do
    show_menu = Map.put(socket.assigns.show_menu || %{}, message_id, true)
    {:noreply, assign(socket, show_menu: show_menu)}
  end

  def handle_event("hide_reaction_menu", %{"message_id" => message_id}, socket) do
    show_menu = Map.put(socket.assigns.show_menu || %{}, message_id, false)
    {:noreply, assign(socket, show_menu: show_menu)}
  end

  # Handle toggling reaction - delegate to cache
  @impl true
  def handle_event("toggle_reaction", %{"emoji" => emoji, "message-id" => message_id}, socket) do
    # Perform the action by calling the cache
    Windyfall.ReactionCache.toggle(
      String.to_integer(message_id),
      socket.assigns.current_user.id,
      emoji
    )
    # The parent ChatLive will receive the update via PubSub and send
    # new assigns down, triggering this component's update/render cycle.
    {:noreply, socket}
  end

  @impl true
  def handle_event("context_menu_action", payload, socket) do
    # Get the action
    action = payload["action"]

    # Get the message ID string, checking both possible keys
    message_id_str = payload["message_id"] || payload["message-id"] # Accept underscore OR hyphen

    # Ensure we actually got a message ID
    if is_nil(message_id_str) do
       {:noreply, put_flash(socket, :error, "Internal error: Missing message ID for context action.")}
    else
      # Convert to integer once we have the string
      message_id = String.to_integer(message_id_str)

      # Proceed with the original logic using the extracted action and message_id
      case action do
        "reply" ->
          send(self(), {:start_reply, message_id})
          {:noreply, socket}

        "copy_text" ->
          text_to_copy =
            find_message_in_group_by_id(socket.assigns.group, message_id)
            |> Map.get(:text, "")

          if text_to_copy != "" do
            {:noreply, push_event(socket, "clipboard-copy", %{content: text_to_copy})}
          else
            {:noreply, socket}
          end

        "edit" ->
          send(self(), {:start_edit, message_id})
          {:noreply, socket}

        "delete" ->
           send(self(), {:delete_message, message_id})
           {:noreply, socket}

        "share" ->
          send(self(), {:initiate_share, :message, message_id}) # Send message to ChatLive
          {:noreply, socket}

        "copy_link" ->
          send(self(), {:copy_link, message_id}) # Send message to ChatLive
          {:noreply, socket}

        # Placeholders for unimplemented actions
        "react" ->
          {:noreply, put_flash(socket, :info, "Reaction picker not implemented yet.")}

        "report" ->
           {:noreply, put_flash(socket, :error, "Reporting not implemented yet.")}

        _ ->
          # Unknown action
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("update_edit_content", %{"content" => new_content, "message-id" => mid_str}, socket) do
    # Only update if this component is actually editing this message
    if socket.assigns.editing_message_id == String.to_integer(mid_str) do
      {:noreply, assign(socket, :editing_content, new_content)}
    else
      # Should not happen if element is only rendered when editing, but safety check
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_spoiler", %{"spoiler-id" => id}, socket) do
    # This simply adds/removes a CSS class using JS push_event
    # The actual content is already in the DOM.
    {:noreply, push_event(socket, "js:toggle_spoiler_class", %{id: id})}
  end

  # Add handler in MessageComponent if it handles editing directly
  # OR bubble "update_editor_content" up to ChatLive if needed there.
  # Let's assume MessageComponent handles its own edit state update.
  @impl true
  def handle_event("update_editor_content", payload, socket) do
    # Extract data from the payload map
    markdown_content = payload["markdown"]
    # editor_id_from_event = payload["editorId"] # Assuming React sends this key

    # Get the message ID this component instance is potentially editing
    # current_editing_message_id = socket.assigns.editing_message_id

    # Construct the expected editor ID for this component instance when editing
    # Ensure this matches the `uniqueId` prop passed to SlateEditor in edit mode
    # expected_editor_id = if current_editing_message_id do
    # "edit-#{current_editing_message_id}"
    # else
    # nil # Not editing anything in this instance
    # end

    # Check if:
    # 1. This component is currently editing *any* message.
    # 2. The event came from the specific editor associated with the message being edited.
    # 3. Markdown content exists in the payload.
    # if current_editing_message_id &&
    # editor_id_from_event == expected_editor_id &&
    # !is_nil(markdown_content) do
      # Update the temporary editing content state for *this* component instance
    if socket.assigns.editing_message_id && !is_nil(markdown_content) do
      {:noreply, assign(socket, :editing_content, markdown_content)}
    else
      # Event is not relevant to this component instance (e.g., from another edit box
      # or the editor ID didn't match), so ignore it.
      {:noreply, socket}
    end
  end

  defp update_reaction_count(socket, message_id, emoji, count) do
    counts = socket.assigns.reaction_counts
    msg_counts = Map.get(counts, message_id, %{})
    new_counts = Map.put(msg_counts, emoji, count)
    
    socket
    |> assign(:reaction_counts, Map.put(counts, message_id, new_counts))
  end

  defp update_user_reactions(socket, message_id, emoji, action) do
    key = {message_id, emoji}
    new_set = case action do
      :add -> MapSet.put(socket.assigns.user_reactions, key)
      :remove -> MapSet.delete(socket.assigns.user_reactions, key)
    end
    
    assign(socket, :user_reactions, new_set)
  end

  defp update_stream(socket, message_id, emoji, action, count_change) do
    reaction_id = "reaction_#{message_id}_#{emoji}"

    case action do
      :add ->
        socket
        |> stream_insert(:reactions, %{
          id: reaction_id,
          emoji: emoji,
          count: get_current_count(socket, message_id, emoji) + count_change,
          message_id: message_id
        }, reset: false)

      :remove ->
        socket
        |> stream_delete(:reactions, %{id: reaction_id})
    end
    |> update_user_reactions(message_id, emoji, action)
  end

  defp get_current_count(socket, message_id, emoji) do
    socket.assigns.streams.reactions
    |> Enum.find(fn r -> 
      r.message_id == message_id && r.emoji == emoji
    end)
    |> case do
      nil -> 0
      r -> r.count
    end
  end

  def handle_info({:reaction_synced, message_id, emoji, server_reactions}, socket) do
    # 5. FINAL SYNC IF NEEDED
    server_reaction = server_reactions
      |> Map.get(message_id, [])
      |> Enum.find(& &1.emoji == emoji)

    reaction_id = "reaction_#{message_id}_#{emoji}"

    socket = if server_reaction do
      # Only update if server count differs from optimistic
      if server_reaction.count != get_in(socket.assigns.reactions, [message_id, Access.filter(& &1.emoji == emoji), Access.at(0), :count]) do
        socket
        |> stream_insert(:reactions, %{
          id: reaction_id,
          emoji: emoji,
          count: server_reaction.count,
          message_id: message_id
        })
      else
        socket
      end
    else
      socket
      |> stream_delete(:reactions, %{id: reaction_id})
    end

    {:noreply, socket}
  end

  def handle_info({:reaction_error, message_id, emoji, _error}, socket) do
    # 6. REVERT ON ERROR
    reaction_id = "reaction_#{message_id}_#{emoji}"
    original_count = get_original_count(socket.assigns.reactions, message_id, emoji)

    {:noreply,
     socket
     |> stream_insert(:reactions, %{
       id: reaction_id,
       emoji: emoji,
       count: original_count,
       message_id: message_id
     })
     |> put_flash(:error, "Failed to update reaction")}
  end

  defp update_local_reactions(reactions, user_reactions, message_id, emoji, user_id) do
    message_reactions = Map.get(reactions, message_id, [])
    
    # Find existing reaction for this emoji
    {existing, others} = 
      Enum.split_with(message_reactions, fn r -> r.emoji == emoji end)

    current = 
      case existing do
        [found] -> found
        [] -> %{emoji: emoji, count: 0, users: []}
      end

    # Toggle user reaction
    {new_count, new_users} = 
      if user_id in current.users do
        {current.count - 1, List.delete(current.users, user_id)}
      else
        {current.count + 1, [user_id | current.users]}
      end

    # Update reactions structure
    updated_reactions = 
      cond do
        new_count > 0 ->
          new_entry = %{current | count: new_count, users: new_users}
          Map.put(reactions, message_id, [new_entry | others])
        
        Enum.any?(others) ->
          Map.put(reactions, message_id, others)
        
        true ->
          Map.delete(reactions, message_id)
      end

    # Update user reactions
    updated_user_reactions = 
      Map.update(user_reactions, message_id, %{}, fn msg_reactions ->
        if new_count > current.count do
          Map.put(msg_reactions, emoji, true)
        else
          Map.delete(msg_reactions, emoji)
        end
      end)

    {updated_reactions, updated_user_reactions}
  end

  defp calculate_optimistic_update(current_reactions, current_user_reactions, message_id, emoji, user_id) do
    message_reactions = Map.get(current_reactions, message_id, [])
    
    {action, updated_reactions, updated_user_reactions} = 
      case Enum.filter(message_reactions, & &1.emoji == emoji) do
        [found] ->
          user_reacted = MapSet.member?(found.users, user_id)
          new_count = if user_reacted, do: found.count - 1, else: found.count + 1
          new_users = if user_reacted,
            do: MapSet.delete(found.users, user_id),
            else: MapSet.put(found.users, user_id)

          action = if new_count == 0, do: :delete, else: :update
          
          new_reactions = Map.update(
            current_reactions,
            message_id,
            [],
            & Enum.map(&1, fn
              %{emoji: ^emoji} = r -> %{r | count: new_count, users: new_users}
              r -> r
            end)
          )

          new_user_reacts = update_user_reactions(current_user_reactions, message_id, emoji, user_reacted)
          
          {action, new_reactions, new_user_reacts}

        [] ->
          new_reaction = %{
            emoji: emoji,
            count: 1,
            users: MapSet.new([user_id]),
            message_id: message_id
          }

          new_reactions = Map.update(
            current_reactions,
            message_id,
            [new_reaction],
            & [new_reaction | &1]
          )

          new_user_reacts = update_user_reactions(current_user_reactions, message_id, emoji, false)
          
          {:insert, new_reactions, new_user_reacts}
      end

    {updated_reactions, updated_user_reactions, action}
  end

  defp revert_optimistic_update(socket, message_id, emoji, user_id) do
    # Reverse the optimistic changes
    {reverted_user_reactions, reverted_reactions} = 
      calculate_optimistic_update(
        socket.assigns.reactions,
        socket.assigns.user_reactions,
        message_id,
        emoji,
        user_id
      )
    
    socket
    |> assign(:user_reactions, reverted_user_reactions)
    |> assign(:reactions, reverted_reactions)
  end

  defp update_stream_with_reaction(socket, message_id, emoji, action, reactions) do
    reaction_id = "reaction_#{message_id}_#{emoji}"
    
    case action do
      :delete ->
        socket
        |> stream_delete(:reactions, %{id: reaction_id})  # Minimal structure for deletion

      _ ->
        reaction = 
          get_in(reactions, [message_id])
          |> Enum.find(& &1.emoji == emoji)

        if reaction do
          IO.inspect {DateTime.utc_now, "now inserting reaction into stream", emoji, reaction_id}
          socket
          |> stream_insert(:reactions, %{
            id: reaction_id,
            emoji: emoji,
            count: reaction.count,
            message_id: message_id
          })
        else
          socket
        end
    end
  end

  defp get_original_count(reactions, message_id, emoji) do
    reactions
    |> Map.get(message_id, [])
    |> Enum.find(& &1.emoji == emoji)
    |> case do
      nil -> 0
      reaction -> reaction.count
    end
  end

  defp update_user_reactions(user_reactions, message_id, emoji, was_reacted) do
    current = Map.get(user_reactions, message_id, MapSet.new())
    new_set = if was_reacted,
      do: MapSet.delete(current, emoji),
      else: MapSet.put(current, emoji)

    Map.put(user_reactions, message_id, new_set)
  end

  defp find_message_in_group_by_id(group, message_id) do
    Enum.find(group.messages, fn msg -> msg.id == message_id end) || %{}
  end

  defp render_markdown_with_spoilers(markdown_text, target_component) do
    # Parse Markdown with Earmark, adding the breaks: true option
    html_fragment =
      case Earmark.as_html(markdown_text, # Use original text
                            escape: true,
                            smartypants: true,
                            breaks: true) do # <<< ADD THIS OPTION
        {:ok, html, _} -> html
        {:error, html, _} -> html # Render partial on error
      end

    # 2. Replace ||...|| in the GENERATED HTML
    final_html = replace_spoilers_in_html(html_fragment, target_component)

    # 3. Render raw HTML
    raw(final_html)
  end

  # --- NEW Helper to replace spoilers in HTML output ---
  @spoiler_html_regex ~r/\|\|(.+?)\|\|/s # Same regex, but operates on HTML now

  defp replace_spoilers_in_html(html_text, target_component) do
    String.replace(html_text, @spoiler_html_regex, fn full_match ->
      # Extract content - careful, content might now contain generated HTML tags (e.g., <em>)
      # We need to capture the raw content between the ||
      case Regex.run(@spoiler_html_regex, full_match, capture: :all_but_first) do
         [content_potentially_with_html] ->
           spoiler_id = "spoiler-#{generate()}"
           # Content is already HTML-safe because Earmark processed it (unless user put || around <script>)
           # We pass it directly into the innerHTML of the span.
           """
           <span class="spoiler-text"
                 phx-click="toggle_spoiler"
                 phx-value-spoiler-id="#{spoiler_id}"
                 phx-target="#{target_component}"
                 id="#{spoiler_id}"
                 role="button"
                 tabindex="0"
                 aria-label="Spoiler content"
           >#{content_potentially_with_html}</span>
           """
         _ ->
           # Should not happen if regex matched
           "[INVALID SPOILER]"
      end
    end)
  end
end
