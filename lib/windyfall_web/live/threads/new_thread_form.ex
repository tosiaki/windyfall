defmodule WindyfallWeb.Threads.NewThreadForm do
  use WindyfallWeb, :html

  def form(assigns) do
    ~H"""
    <li class="p-4">
      <form phx-submit={@submit_event} class="space-y-3">
        <div>
          <label class="block text-sm font-medium text-gray-700">Title</label>
          <input 
            type="text" 
            name="title" 
            required
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          >
        </div>
        
        <div>
          <label class="block text-sm font-medium text-gray-700">First Message</label>
          <textarea
            name="message"
            required
            rows="3"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm"
          ></textarea>
        </div>
        
        <div class="flex gap-2">
          <button 
            type="submit"
            class="inline-flex items-center rounded-md border border-transparent bg-blue-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Create Thread
          </button>
          <button 
            type="button"
            phx-click={@cancel_event}
            class="inline-flex items-center rounded-md border border-gray-300 bg-white px-4 py-2 text-sm font-medium text-gray-700 shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
          >
            Cancel
          </button>
        </div>
      </form>
    </li>
    """
  end
end
