defmodule WindyfallWeb.MessageComponents do
  use Phoenix.Component
  import Phoenix.HTML
  import Phoenix.VerifiedRoutes
  use WindyfallWeb, :verified_routes
  import WindyfallWeb.CoreComponents

  def date_divider(assigns) do
    ~H"""
    <div class="relative py-4">
      <div class="absolute inset-0 flex items-center" aria-hidden="true">
        <div class="w-full border-t border-gray-200"></div>
      </div>
      <div class="relative flex justify-center">
        <span class="px-2 bg-white text-sm text-gray-500">
          <%= @date %>
        </span>
      </div>
    </div>
    """
  end

  def message_group(assigns) do
    ~H"""
    <div class={["flex gap-3", @alignment]}>
      <%= if @show_avatar do %>
        <div class="flex-none">
          <.link navigate={~p"/u/#{@user_id}"} class="block">
            <img 
              class="h-10 w-10 rounded-full object-cover" 
              src={user_avatar(@profile_image)} 
              alt={@display_name}
            />
          </.link>
        </div>
      <% end %>

      <div class="max-w-[85%] sm:max-w-[65%]">
        <div class={["p-4 rounded-2xl", bubble_style(@user_id, @current_user.id)]}>
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  def message_bubble(assigns) do
    assigns = assign_new(assigns, :class, fn -> "" end)
    ~H"""
    <div class={["space-y-1", @class]}>
      <%= if @show_header do %>
        <div class="text-sm font-medium text-gray-900 mb-1">
          <%= @display_name %>
        </div>
      <% end %>
      
      <div class="text-sm text-gray-800">
        <%= @message %>
      </div>
      
      <.timestamp timestamp={@timestamp} />
    </div>
    """
  end

  defp timestamp(assigns) do
    ~H"""
    <div class="relative inline-block mt-1">
      <span class="text-xs cursor-help hover:underline peer">
        <%= @timestamp.text %>
      </span>
      <div class="absolute hidden peer-hover:block bottom-full left-0 mb-2 px-2 py-1 
                  text-xs bg-gray-900 text-white rounded-lg whitespace-nowrap shadow-lg">
        <%= @timestamp.full_text %>
        <div class="absolute top-full left-2 w-2 h-2 bg-gray-900 rotate-45"></div>
      </div>
    </div>
    """
  end

  defp bubble_style(user_id, current_user_id) do
    if user_id == current_user_id, 
      do: "bg-blue-500 text-white", 
      else: "bg-gray-100"
  end
end
