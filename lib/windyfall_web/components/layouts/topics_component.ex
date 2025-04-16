defmodule WindyfallWeb.Layouts.TopicsComponent do
  use Phoenix.Component
  import Phoenix.VerifiedRoutes
  use WindyfallWeb, :verified_routes

  def topics_nav(assigns) do
    ~H"""
    <nav class="sticky top-[4.5rem] z-10 bg-white/90 backdrop-blur-sm border-b border-[var(--color-border)]">
      <div class="flex items-center px-4 sm:px-6 lg:px-8 overflow-x-auto scrollbar-hide">
        <div class="flex space-x-4 py-3">
          <%= for topic <- @topics do %>
            <.link 
              navigate={~p"/t/#{topic.path}"}
              class={[
                "px-3 py-1 rounded-full text-sm font-medium transition-colors", if(@current_topic == topic.path, do: "bg-[var(--color-primary)] text-white", else: "text-[var(--color-text)] hover:bg-[var(--color-primary)]/10")
              ]}
            >
              <%= topic.name %>
            </.link>
          <% end %>
        </div>
        <div class="flex-1 min-w-[2rem]"/> <%# Spacer for overflow %>
      </div>
    </nav>
    """
  end
end
