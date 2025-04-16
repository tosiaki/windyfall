defmodule WindyfallWeb.BuildItemComponent do
  use WindyfallWeb, :live_component

  def mount(socket) do
    {:ok, assign(socket, :mouseover, false)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <div class="relative" phx-hook="MouseoverHook" phx-target={@myself} id={"mouseover-element-#{@myself}"}>
        <%= render_slot(@inner_block) %>
        <%= if @mouseover do %>
          <div class="absolute border-2 p-2 border-solid bg-lime-100"><%= render_slot(@tooltip) %></div>
        <% end %>
      </div>
    </div>
    """
  end

  def handle_event("mouseover", _params, socket) do
    {:noreply, assign(socket, :mouseover, true)}
  end

  def handle_event("mouseout", _params, socket) do
    {:noreply, assign(socket, :mouseover, false)}
  end
end
