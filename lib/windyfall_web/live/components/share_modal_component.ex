defmodule WindyfallWeb.ShareModalComponent do
  use WindyfallWeb, :live_component

  alias Windyfall.Repo
  alias Windyfall.Messages.Message
  alias Windyfall.Messages
  alias WindyfallWeb.CoreComponents

  @impl true
  def mount(socket) do
    # Initial state, data loading happens in update
    {:ok,
     assign(socket,
       item_preview: nil, # Placeholder for fetched thread/message data
       all_topics: [],
       selected_target: nil # %{type: "topic" | "user", id: integer | string}
     )}
  end

  @impl true
  def update(assigns, socket) do
    # Fetch data needed for the modal when assigns change (especially item_id/item_type)
    socket =
      socket
      |> assign(assigns) # Assign passed values like item_id, item_type, current_user
      |> load_item_preview()
      |> load_all_topics()
      |> assign_new(:selected_target, fn -> nil end) # Keep selection state across updates unless reset

    {:ok, socket}
  end

  # Helper to load item preview data
  defp load_item_preview(socket) do
    item_type = socket.assigns.item_type
    item_id = socket.assigns.item_id
    preview =
      case {item_type, item_id} do
        {:thread, id} when not is_nil(id) ->
          # Fetch thread with needed preview data
          thread =
            Messages.get_thread_preview(id) # Needs a new lightweight context function

          if thread,
            do: %{type: :thread, title: thread.title, preview: thread.first_message_preview, author_name: thread.author_name, author_avatar: thread.author_avatar},
            else: nil

        {:message, id} when not is_nil(id) ->
           message = Repo.get(Message, id) |> Repo.preload(:user)
           if message && message.user do
              %{
                type: :message,
                title: nil, # Messages don't have titles
                preview: message.message, # Use full message or truncate?
                author_name: message.user.display_name || "Anonymous",
                author_avatar: message.user.profile_image
              }
           else
             nil # Message or user not found
           end

        _ ->
          nil
      end

    assign(socket, :item_preview, preview)
  end

   # Add context function Messages.get_thread_preview/1 (simplified version)
   # You'll need to add this to lib/windyfall/messages.ex
   # def get_thread_preview(thread_id) do
   #   from(t in Thread,
   #     where: t.id == ^thread_id,
   #     left_join: u in assoc(t, :user),
   #     # Basic select, adapt based on what list_threads returns
   #     select: %{
   #       id: t.id, title: t.title, user_id: t.user_id,
   #       author_name: u.display_name, author_avatar: u.profile_image,
   #       first_message_preview: fragment("...") # Re-use preview fragment if possible
   #     }
   #   ) |> Repo.one()
   # end


  # Helper to load all topics
  defp load_all_topics(socket) do
    # Cache this result in mount/update if topic list is static
    assign(socket, :all_topics, Messages.list_topics())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal id="share-modal-container" show={@show} on_cancel={JS.push("close_modal", target: @myself)}>
        <div class="p-4">
          <h3 class="text-lg font-medium leading-6 text-gray-900 mb-4">Share Post</h3>

          <%# Item Preview %>
          <%= if @item_preview do %>
            <div class="mb-4 p-3 border rounded-md bg-gray-50 text-sm">
              <div class="flex items-center gap-2 mb-1">
                <img src={CoreComponents.user_avatar(@item_preview.author_avatar)} class="w-5 h-5 rounded-full" alt={@item_preview.author_name} />
                <span class="font-medium text-gray-800"><%= @item_preview.author_name %></span>
              </div>
              <p class="text-gray-600"><%= @item_preview.preview %></p>
            </div>
          <% else %>
            <p class="text-gray-500 mb-4">Loading item...</p>
          <% end %>

          <%# Target Selection %>
          <div class="space-y-3">
            <label class="block text-sm font-medium text-gray-700">Share To:</label>

            <%# Your Profile Option %>
            <button
              type="button"
              class={"w-full text-left p-2 rounded-md border #{target_button_classes("user", @current_user.id, @selected_target)}"}
              phx-click="select_target"
              phx-value-type="user"
              phx-value-id={@current_user.id}
              phx-target={@myself}
            >
              <div class="flex items-center gap-2">
                 <img src={CoreComponents.user_avatar(@current_user.profile_image)} class="w-6 h-6 rounded-full" alt="" />
                 <div>
                   <div class="font-medium">Your Profile</div>
                   <div class="text-xs text-gray-500">Share to your own page</div>
                 </div>
              </div>
            </button>

            <%# Topic List %>
            <div class="max-h-48 overflow-y-auto border rounded-md p-1 space-y-1 bg-white">
              <div class="px-1 py-0.5 text-xs font-semibold text-gray-500 sticky top-0 bg-white/90 backdrop-blur-sm">Topics</div>
              <%= for topic <- @all_topics do %>
                <button
                  type="button"
                  class={"w-full text-left px-2 py-1.5 rounded #{target_button_classes("topic", topic.id, @selected_target)}"}
                  phx-click="select_target"
                  phx-value-type="topic"
                  phx-value-id={topic.id}
                  phx-target={@myself}
                >
                  <%= topic.name %>
                </button>
              <% end %>
               <%= if @all_topics == [] do %>
                 <p class="px-2 py-1.5 text-sm text-gray-400">No topics found.</p>
               <% end %>
            </div>

          </div>

          <%# Action Buttons %>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              class="px-4 py-2 text-sm font-medium rounded-md border border-gray-300 text-gray-700 hover:bg-gray-50"
              phx-click="close_modal"
              phx-target={@myself}
            >
              Cancel
            </button>
            <button
              type="button"
              class="px-4 py-2 text-sm font-medium rounded-md border border-transparent bg-blue-600 text-white hover:bg-blue-700 disabled:opacity-50 disabled:bg-blue-400"
              phx-click="confirm_share"
              disabled={is_nil(@selected_target)}
              phx-disable-with="Sharing..."
              phx-target={@myself}
            >
              Share
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  # Helper for styling target buttons
  defp target_button_classes(type, id, selected) do
    is_selected = selected && selected["type"] == type && selected["id"] == id
    base = "hover:bg-gray-100 focus:outline-none focus:ring-2 focus:ring-offset-1 focus:ring-blue-500 transition-colors"
    if is_selected, do: "#{base} bg-blue-50 border-blue-300 ring-1 ring-blue-400", else: "#{base} border-transparent"
  end

  @impl true
  def handle_event("select_target", %{"type" => type, "id" => id_str}, socket) do
    # Parse ID depending on type - topic ID is int, user ID might be int/string
    id = case type do
           "topic" -> String.to_integer(id_str)
           "user" -> String.to_integer(id_str) # Assuming user ID is passed
           _ -> id_str
         end
    selected = %{"type" => type, "id" => id}
    {:noreply, assign(socket, :selected_target, selected)}
  end

  @impl true
  def handle_event("confirm_share", _, socket) do
    IO.inspect "confirming share in modal"
    # Send necessary info to parent ChatLive
    payload = %{
      item_type: socket.assigns.item_type,
      item_id: socket.assigns.item_id,
      target: socket.assigns.selected_target # %{"type" => "topic"|"user", "id" => id}
    }
    send(self(), {:confirm_share, payload}) # Send to parent LV process
    {:noreply, assign(socket, selected_target: nil)} # Optimistically clear selection
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    send(self(), {:close_share_modal}) # Send to parent LV process
    {:noreply, socket}
  end
end
