defmodule WindyfallWeb.NewThreadComponent do
  use WindyfallWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="p-4 border-b bg-white">
      <form phx-submit="create_thread" class="space-y-4">

        <div>
          <%# Optionally hide label if placeholder is enough %>
          <label for="new-thread-message" class="block text-sm font-medium mb-1">Message</label>
          <textarea
            id="new-thread-message"
            name="message"
            required
            rows="4"
            placeholder="What's happening?" # Add placeholder text
            class="w-full px-3 py-2 border rounded-lg focus:ring-primary focus:border-primary" # Added focus styles
          ></textarea>
        </div>

        <div class="flex gap-2 justify-end"> <%# Align buttons to the right %>
          <button
            type="button"
            phx-click="cancel_new_thread" # Use a dedicated cancel event
            class="px-4 py-2 bg-gray-100 rounded-lg hover:bg-gray-200 text-sm font-medium text-gray-700"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-primary text-white rounded-lg hover:bg-primary-dark text-sm font-medium"
            phx-disable-with="Posting..." # Add disable state
          >
            Post <%# Changed button text %>
          </button>
        </div>
      </form>
    </div>
    """
  end
end
