defmodule WindyfallWeb.Chat.MessageInputComponent do
  use WindyfallWeb, :live_component

  alias Windyfall.Messages
  alias WindyfallWeb.CoreComponents

  import WindyfallWeb.NumberHelpers, only: [number_to_human_size: 1]

  def render(assigns) do
    ~H"""
    <div id={@id} class="sticky bottom-0 bg-[var(--color-surface)]/90 backdrop-blur-sm border-t border-[var(--color-border)]">
      <div class="p-3 sm:p-4">
        <%= for entry <- @uploads.attachments.entries do %>
          <div class="flex items-center justify-between gap-2 p-2 mb-2 border rounded-md bg-gray-50 text-sm">
            <div class="flex items-center gap-2 overflow-hidden">
              <.icon name="hero-document" class="w-5 h-5 text-gray-500 flex-shrink-0" />
              <span class="truncate" title={entry.client_name}><%= entry.client_name %></span>
              <span class="text-xs text-gray-400">(<%= number_to_human_size(entry.client_size) %>)</span>
              <%= for err <- upload_errors(@uploads.attachments, entry) do %>
                <p class="text-red-500 text-xs"><%= error_to_string(err) %></p>
              <% end %>
            </div>
            <div class="flex items-center gap-2 flex-shrink-0">
              <progress max="100" value={entry.progress} class="w-16 h-1 appearance-none [&::-webkit-progress-bar]:rounded-lg [&::-webkit-progress-bar]:bg-slate-300 [&::-webkit-progress-value]:rounded-lg [&::-webkit-progress-value]:bg-slate-500 [&::-moz-progress-bar]:rounded-lg [&::-moz-progress-bar]:bg-slate-500"/>
              <button
                type="button"
                phx-click="cancel_upload"
                phx-value-ref={entry.ref}
                aria-label="Cancel upload"
                class="text-gray-500 hover:text-red-600 p-1"
              >
                <.icon name="hero-x-circle-solid" class="w-4 h-4" />
              </button>
            </div>
          </div>
        <% end %>

        <%= if @current_user do %>
          <form
            phx-submit="submit_message"
            phx-change="validate_upload"
            class="flex gap-2 items-center rounded-xl bg-[var(--color-surface-alt)] border border-[var(--color-border)] focus-within:border-[var(--color-border-accent)] focus-within:ring-1 focus-within:ring-[var(--color-border-accent)] transition-all pl-4"
            id={@id <> "-form"}
          >
            <label for={@uploads.attachments.ref} class="cursor-pointer p-2 rounded-full hover:bg-gray-200 text-gray-500 hover:text-gray-700 transition-colors">
              <.icon name="hero-paper-clip" class="w-5 h-5" />
            </label>
            <.live_file_input upload={@uploads.attachments} class="sr-only" multiple />

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
              disabled={Enum.any?(@uploads.attachments.entries, &(!&1.done?))}
            >
              <%!-- Send icon --%>
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

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:not_accepted), do: "You selected a non-accepted file type"
  defp error_to_string({:too_many_files, max}), do: "You selected too many files (max: #{max})"
  defp error_to_string(_), do: "Upload error"
end
