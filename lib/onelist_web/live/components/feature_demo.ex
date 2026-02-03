defmodule OnelistWeb.FeatureDemo do
  use OnelistWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:api_response, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full space-y-8" role="region" aria-label="Feature demonstrations">
      <!-- Search Demo Section -->
      <div class="bg-white p-6 rounded-lg shadow-sm" data-test-id="feature-demo-search">
        <h3 class="text-lg font-semibold mb-4">Search Demo</h3>
        <form id="search-demo-form" phx-submit="search" phx-target={@myself}>
          <div class="flex flex-col sm:flex-row gap-4">
            <input
              type="text"
              name="q"
              value={@search_query}
              placeholder="Search notes..."
              class="flex-1 p-2 border rounded-md"
              data-test-id="search-input"
            />
            <button
              type="submit"
              class="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
              data-test-id="search-button"
            >
              Search
            </button>
          </div>
        </form>
        <div class="mt-4" data-test-id="search-results">
          <%= if @search_results == [] and @search_query != "" do %>
            <p class="text-gray-500">No matching results found</p>
          <% else %>
            <%= for result <- @search_results do %>
              <div class="p-2 border-b">
                <p class="text-gray-900"><%= result.title %></p>
                <p class="text-sm text-gray-500"><%= result.excerpt %></p>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
      <!-- API Demo Section -->
      <div class="bg-white p-6 rounded-lg shadow-sm" data-test-id="feature-demo-api">
        <h3 class="text-lg font-semibold mb-4">API Demo</h3>
        <div class="space-y-4">
          <div class="flex flex-col sm:flex-row gap-4">
            <select class="flex-1 p-2 border rounded-md" data-test-id="endpoint-selector">
              <option value="notes">/api/notes</option>
              <option value="tags">/api/tags</option>
              <option value="search">/api/search</option>
            </select>
            <select class="flex-1 p-2 border rounded-md" data-test-id="method-selector">
              <option value="GET">GET</option>
              <option value="POST">POST</option>
              <option value="PUT">PUT</option>
              <option value="DELETE">DELETE</option>
            </select>
          </div>
          <button
            type="button"
            class="w-full px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700"
            data-test-id="try-api-button"
            phx-click="try_api"
            phx-target={@myself}
          >
            Try API
          </button>
          <div class="mt-4" data-test-id="api-response">
            <%= if @api_response do %>
              <pre class="bg-gray-50 p-4 rounded-md overflow-x-auto">
                <code><%= @api_response %></code>
              </pre>
            <% end %>
          </div>
        </div>
      </div>
      <!-- Error Handling Section -->
      <div class="bg-white p-6 rounded-lg shadow-sm" data-test-id="feature-demo-error">
        <h3 class="text-lg font-semibold mb-4">Error Handling</h3>
        <%= if @error do %>
          <div class="p-4 bg-red-50 rounded-md">
            <p class="text-red-700"><%= @error %></p>
            <div class="mt-4 flex gap-4">
              <button
                type="button"
                class="px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700"
                data-test-id="error-retry"
                phx-click="retry"
                phx-target={@myself}
              >
                Retry
              </button>
              <button
                type="button"
                class="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700"
                data-test-id="error-cancel"
                phx-click="cancel"
                phx-target={@myself}
              >
                Cancel
              </button>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    # Simulate search results
    results = [
      %{title: "Example Note 1", excerpt: "This is a sample note about #{query}"},
      %{title: "Example Note 2", excerpt: "Another note containing #{query}"}
    ]

    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  @impl true
  def handle_event("try_api", _, socket) do
    # Simulate API response
    response =
      Jason.encode!(
        %{
          status: "success",
          data: %{
            id: "123",
            title: "Example Note",
            content: "This is an example note"
          }
        },
        pretty: true
      )

    {:noreply, assign(socket, api_response: response)}
  end

  @impl true
  def handle_event("retry", _, socket) do
    {:noreply, assign(socket, error: nil)}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply, assign(socket, error: nil)}
  end
end
