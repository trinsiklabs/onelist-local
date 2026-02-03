defmodule OnelistWeb.App.SearchLive do
  @moduledoc """
  Search page - semantic search across entries and memories.
  """
  use OnelistWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Search")
     |> assign(:current_path, "/app/search")
     |> assign(:query, "")
     |> assign(:results, [])
     |> assign(:searching, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="search-page">
      <div class="page-header" style="margin-bottom: var(--space-6);">
        <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
          🔍 Search
        </h1>
        <p style="color: var(--color-text-muted); margin-top: var(--space-2);">
          Semantic search across your entries and memories
        </p>
      </div>
      <!-- Search Input -->
      <div class="card" style="margin-bottom: var(--space-6);">
        <form phx-submit="search" style="display: flex; gap: var(--space-3);">
          <input
            type="text"
            name="query"
            value={@query}
            class="search-input"
            placeholder="Search for anything... (uses AI-powered semantic search)"
            style="flex: 1; padding: var(--space-3) var(--space-4);"
            autofocus
          />
          <button type="submit" class="btn btn-primary" disabled={@searching}>
            <%= if @searching, do: "Searching...", else: "Search" %>
          </button>
        </form>
      </div>
      <!-- Results -->
      <%= if @query != "" do %>
        <%= if Enum.empty?(@results) do %>
          <div class="card" style="text-align: center; padding: var(--space-8);">
            <div style="font-size: 2rem; margin-bottom: var(--space-3);">🔍</div>
            <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
              No results found
            </h3>
            <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
              Try different keywords or a broader search
            </p>
          </div>
        <% else %>
          <div style="margin-bottom: var(--space-4);">
            <span style="color: var(--color-text-muted); font-size: var(--text-sm);">
              <%= length(@results) %> results for "<%= @query %>"
            </span>
          </div>
          <div style="display: flex; flex-direction: column; gap: var(--space-4);">
            <%= for result <- @results do %>
              <.search_result result={result} />
            <% end %>
          </div>
        <% end %>
      <% else %>
        <div class="card" style="text-align: center; padding: var(--space-12);">
          <div style="font-size: 3rem; margin-bottom: var(--space-4);">🔍</div>
          <h2 style="font-size: var(--text-xl); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            Start searching
          </h2>
          <p style="color: var(--color-text-muted); max-width: 400px; margin-left: auto; margin-right: auto;">
            Enter a query to search across your entries and AI-extracted memories using semantic search
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp search_result(assigns) do
    ~H"""
    <a
      href={~p"/app/library/#{@result.id}"}
      class="card card-hover"
      style="display: block; text-decoration: none;"
    >
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: var(--space-2);">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text);">
          <%= @result.title || "Untitled" %>
        </h3>
        <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
          <%= Float.round(@result.score * 100, 1) %>% match
        </span>
      </div>
      <p style="color: var(--color-text-muted); font-size: var(--text-sm); line-height: var(--leading-relaxed);">
        <%= @result.snippet %>
      </p>
    </a>
    """
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    if String.trim(query) == "" do
      {:noreply, assign(socket, query: "", results: [])}
    else
      # TODO: Use Searcher agent for semantic search
      results = []

      {:noreply,
       socket
       |> assign(:query, query)
       |> assign(:results, results)}
    end
  end
end
