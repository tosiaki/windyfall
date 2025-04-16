defmodule WindyfallWeb.Threads.EmptyState do
  use WindyfallWeb, :html

  def display(assigns) do
    ~H"""
    <div class="p-4 text-center text-gray-500">
      <div class="mb-2">
        <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 inline-block text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
        </svg>
      </div>
      No threads yet. Start a conversation!
    </div>
    """
  end
end
