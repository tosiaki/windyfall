defmodule WindyfallWeb.Threads.ThreadItem do
  use WindyfallWeb, :live_component

  alias WindyfallWeb.CoreComponents
  alias WindyfallWeb.DateTimeHelpers
  alias WindyfallWeb.TextHelpers

  # --- Render Clause for Feed/Tweet View ---
  # Matches when assigns.view_mode is :feed_item (or :tweet_view if you kept that name)
  def render(%{view_mode: :feed_item} = assigns) do
    ~H"""
    <article
      # Use item_wrapper_classes helper for common attributes
      {item_wrapper_attrs(@thread.id)}
      class="block p-4 border-b border-[var(--color-border)] hover:bg-[var(--color-surface-hover)] transition-colors"
      aria-labelledby={"thread-title-#{@thread.id}"}
    >
      <div class="flex gap-3">
        <%# Avatar Column %>
        <div class="flex-shrink-0">
          <.link navigate={CoreComponents.user_profile_path(@thread.creator_id, @thread.user_handle)} class="block group" tabindex="-1">
            <img
              class="h-10 w-10 sm:h-12 sm:w-12 rounded-full object-cover border border-[var(--color-border)] group-hover:opacity-85 transition-opacity"
              src={CoreComponents.user_avatar(@thread.author_avatar)}
              alt={@thread.author_name}
              loading="lazy"
            />
          </.link>
        </div>

        <%# Content Column %>
        <div class="flex-1 min-w-0">
          <%# Author Info Row %>
          <div class="flex items-baseline gap-1.5 text-sm mb-0.5">
            <.link
              navigate={CoreComponents.user_profile_path(@thread.creator_id, @thread.user_handle)}
              class="font-bold text-[var(--color-text)] hover:underline"
            >
              <%= @thread.author_name %>
            </.link>
            <.link navigate={CoreComponents.user_profile_path(@thread.creator_id, @thread.user_handle)} class="text-[var(--color-text-secondary)] hover:underline truncate">
              @<%= @thread.user_handle %>
            </.link>
            <span class="text-[var(--color-text-tertiary)] flex-shrink-0">
              · <%= DateTimeHelpers.time_ago(@thread.inserted_at) %>
            </span>
          </div>

          <%# Thread Title (Optional) %>
          <%= if @thread.title && @thread.title != "" do %>
            <h2
              id={"thread-title-#{@thread.id}"}
              class="text-sm font-semibold text-[var(--color-text-secondary)] mb-1"
            >
              <%= @thread.title %>
            </h2>
          <% end %>

          <%# Main Message Content %>
          <div class="text-[var(--color-text)] whitespace-pre-wrap break-words text-[0.95rem] leading-relaxed">
            <%= @thread.first_message_preview %>
          </div>

          <%# Interaction Bar %>
          <div class="mt-3 flex items-center justify-between text-[var(--color-text-secondary)] text-xs">
            <button class="flex items-center gap-1 hover:text-[var(--color-primary)] transition-colors" aria-label={TextHelpers.pluralize(@thread.message_count, "reply", "replies")}>
              <.icon name="hero-chat-bubble-left" class="w-4 h-4" />
              <span><%= @thread.message_count %></span>
            </button>
            <button class="flex items-center gap-1 hover:text-red-500 transition-colors" aria-label="Like thread">
              <.icon name="hero-heart" class="w-4 h-4" />
            </button>
            <button
              class="flex items-center gap-1 hover:text-green-500 transition-colors"
              aria-label="Share thread"
              phx-click="initiate_share"
              phx-value-thread-id={@thread.id}
              >
              <.icon name="hero-arrow-path-rounded-square" class="w-4 h-4" />
            </button>
            <button
              class={"flex items-center gap-1 hover:text-yellow-500 transition-colors #{if @is_bookmarked, do: "text-yellow-500"}"}
              aria-label={if @is_bookmarked, do: "Remove bookmark", else: "Bookmark thread"}
              phx-click="toggle_bookmark"
              phx-value-thread-id={@thread.id}
              phx-target={@target}
            >
              <.icon name={if @is_bookmarked, do: "hero-bookmark-solid", else: "hero-bookmark"} class="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </article>
    """
  end

  # --- Render Clause for Compact Sidebar View ---
  # Matches when assigns.view_mode is :compact
  def render(%{view_mode: :compact} = assigns) do
    ~H"""
    <li
      # Use item_wrapper_classes helper for common attributes
      {item_wrapper_attrs(@thread.id)}
      # Apply specific classes for compact view state
      class={"block p-3 cursor-pointer transition-colors #{if @selected, do: "bg-[var(--color-primary)]/10", else: "hover:bg-[var(--color-surface-hover)]"}"}
      aria-current={if @selected, do: "page", else: false}
      role="link" # Role indicates it acts like a link
    >
      <div class="flex items-center gap-2.5">
         <img
           class="w-7 h-7 rounded-full object-cover flex-shrink-0"
           src={CoreComponents.user_avatar(@thread.author_avatar)}
           alt={@thread.author_name}
           loading="lazy"
         />
         <div class="flex-1 min-w-0">
           <div class="font-medium text-[var(--color-text)] text-sm truncate" title={@thread.title}><%= @thread.title %></div>
           <div class="text-xs text-[var(--color-text-secondary)] truncate mt-0.5">
             <span class="font-medium"><%= @thread.author_name %>:</span> <%= @thread.first_message_preview %>
           </div>
           <div class="flex items-center gap-1.5 mt-1 text-xs text-[var(--color-text-tertiary)]">
             <span><%= TextHelpers.pluralize(@thread.message_count, "msg", "msgs") %></span>
             <span>·</span>
             <span><%= DateTimeHelpers.time_ago(@thread.last_message_at) %></span>
           </div>
         </div>
      </div>
    </li>
    """
  end

  # --- Helper for common item attributes ---
  defp item_wrapper_attrs(thread_id) do
    %{
      "phx-click": "select_thread",
      "phx-value-id": thread_id,
      "tabindex": "0" # Make it focusable
    }
  end
end
