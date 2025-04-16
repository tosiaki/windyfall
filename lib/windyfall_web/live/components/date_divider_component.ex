defmodule WindyfallWeb.Chat.DateDividerComponent do
  use WindyfallWeb, :live_component

  alias WindyfallWeb.DateTimeHelpers

  def render(assigns) do
    ~H"""
    <div class="relative py-4">
      <div class="absolute inset-0 flex items-center" aria-hidden="true">
        <div class="w-full border-t border-gray-200"></div>
      </div>
      <div class="relative flex justify-center">
        <span class="px-3 bg-white text-sm text-gray-500 font-medium rounded-full border border-gray-200 shadow-sm">
          <%= DateTimeHelpers.format_date(@date) %>
        </span>
      </div>
    </div>
    """
  end
end
