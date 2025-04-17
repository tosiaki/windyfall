defmodule WindyfallWeb.Chat.MessageInputComponent do
  use WindyfallWeb, :live_component

  alias Windyfall.Messages
  alias WindyfallWeb.CoreComponents

  def render(assigns) do
    ~H"""
    <div id={@id} class="sticky bottom-0 bg-[var(--color-surface)]/90 backdrop-blur-sm border-t border-[var(--color-border)]">
      <div class="p-3 sm:p-4">
        <%= if @current_user do %>
          <form
            phx-submit="submit_message"
            class="flex gap-2 items-center rounded-xl bg-[var(--color-surface-alt)] border border-[var(--color-border)] focus-within:border-[var(--color-border-accent)] focus-within:ring-1 focus-within:ring-[var(--color-border-accent)] transition-all pl-4"
            id={@id <> "-form"}
          >
            <div class="flex-1 message-editor-wrapper"> <%# Added wrapper %>
              <%= live_react_component(
                    "Components.SlateEditor", # Module name as string
                    %{ # Props Map
                      uniqueId: @id,
                      initialValue: "",
                      formId: @id <> "-form"
                    },
                    # Options Map (for DOM attributes)
                    id: "slate-editor-#{@id}",
                    phx_update: "ignore",
                  ) %>
            </div>
            <button
              type="submit"
              class="mr-1 flex-shrink-0 p-2 rounded-full bg-[var(--color-primary)] text-[var(--color-text-on-primary)] hover:bg-[var(--color-primary-dark)] transition-colors focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1"
              aria-label="Send message"
            >
              <%!-- Keep existing send icon --%>
              <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
              </svg>
            </button>
          </form>
        <% else %>
          <div class="text-center p-4 bg-amber-50/50 rounded-lg border border-amber-100/50">
            <p class="text-amber-700">
              <.link navigate={~p"/users/log_in"} class="font-medium hover:underline text-[var(--color-primary)] hover:text-[var(--color-primary-dark)]">Log in</.link>
              or
              <.link navigate={~p"/users/register"} class="font-medium hover:underline text-[var(--color-primary)] hover:text-[var(--color-primary-dark)]">register</.link>
              to join the conversation.
            </p>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("submit_message", %{"new_message" => message}, socket) do
    case message do
      "" -> {:noreply, socket}
      message_text -> # Renamed variable for clarity
        user = socket.assigns.current_user
        thread_id = socket.assigns.thread_id

        case Messages.create_message(message_text, thread_id, user) do
          {:ok, new_message_struct} -> # Result from DB with :user preloaded
            # Construct the payload map for broadcast
            # Ensure it includes keys needed by format_group/can_group if :user isn't passed
            payload = %{
              id: new_message_struct.id,
              message: new_message_struct.message,
              user_id: new_message_struct.user_id, # Essential for grouping
              inserted_at: new_message_struct.inserted_at, # Essential for grouping/sorting
              # Add display_name and profile_image for format_group fallback
              display_name: user.display_name,
              profile_image: user.profile_image
              # We DON'T include the full :user struct in the broadcast payload itself
            }

            IO.inspect "broadcasting now, inside component"
            WindyfallWeb.Endpoint.broadcast("thread:#{thread_id}", "new_message", payload)
            # Clear input field
            {:noreply, push_event(socket, "sent-message", %{})}
          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to send message")}
        end
    end
  end

  defp broadcast_message(message, thread_id) do
    payload = %{
      id: message.id,
      message: message.message,
      user_id: message.user_id,
      display_name: message.user.display_name,
      profile_image: CoreComponents.user_avatar(message.user.profile_image),
      inserted_at: message.inserted_at
    }
    
    WindyfallWeb.Endpoint.broadcast!("thread:#{thread_id}", "new_message", payload)
  end

  defp escape_javascript(str) do
    # Basic JS string escaping
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
  end
end
