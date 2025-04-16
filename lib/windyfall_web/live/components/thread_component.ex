defmodule WindyfallWeb.Chat.ThreadComponent do
  use WindyfallWeb, :live_component
  
  alias WindyfallWeb.DateTimeHelpers
  alias WindyfallWeb.TextHelpers

  def render(assigns) do
    ~H"""
    <div 
        class="p-4 hover:bg-gray-50 cursor-pointer" 
        phx-click="select_thread" 
        phx-value-id={@thread.id}
      >
      <div class="flex gap-3">
        <img class="h-12 w-12 rounded-full object-cover" 
             src={CoreComponents.user_avatar(@thread.author_avatar)} 
             alt={@thread.author_name} />
        <div class="flex-1">
          <div class="flex items-center gap-2">
            <span class="font-semibold"><%= @thread.author_name %></span>
            <span class="text-gray-500 text-sm">
              <%= DateTimeHelpers.format_datetime(@thread.first_message_at) %>
            </span>
          </div>
          <div class="mt-2 text-gray-800">
            <%= TextHelpers.truncate(@thread.first_message_preview, 280) %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
