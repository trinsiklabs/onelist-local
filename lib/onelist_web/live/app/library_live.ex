defmodule OnelistWeb.App.LibraryLive do
  @moduledoc """
  Library view - browse all entries with filtering and search.
  """
  use OnelistWeb, :live_view

  alias Onelist.Entries

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    entries =
      Entries.list_entries(user.id,
        limit: 50,
        preload: [:tags]
      )

    {:ok,
     socket
     |> assign(:page_title, "Library")
     |> assign(:current_path, "/app/library")
     |> assign(:entries, entries)
     |> assign(:filter_type, "all")
     |> assign(:search_query, "")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="library-page">
      <div
        class="page-header"
        style="display: flex; justify-content: space-between; align-items: center; margin-bottom: var(--space-6);"
      >
        <div>
          <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
            📚 Library
          </h1>
          <p style="color: var(--color-text-muted); margin-top: var(--space-2);">
            <%= length(@entries) %> entries
          </p>
        </div>
        <button class="btn btn-primary" phx-click="new_entry">
          + New Entry
        </button>
      </div>
      <!-- Filters -->
      <div class="card" style="margin-bottom: var(--space-4); padding: var(--space-3);">
        <div style="display: flex; gap: var(--space-4); align-items: center; flex-wrap: wrap;">
          <div style="display: flex; gap: var(--space-2);">
            <button
              class={["btn", (@filter_type == "all" && "btn-primary") || "btn-ghost"]}
              phx-click="filter"
              phx-value-type="all"
            >
              All
            </button>
            <button
              class={["btn", (@filter_type == "note" && "btn-primary") || "btn-ghost"]}
              phx-click="filter"
              phx-value-type="note"
            >
              📝 Notes
            </button>
            <button
              class={["btn", (@filter_type == "article" && "btn-primary") || "btn-ghost"]}
              phx-click="filter"
              phx-value-type="article"
            >
              📄 Articles
            </button>
            <button
              class={["btn", (@filter_type == "file" && "btn-primary") || "btn-ghost"]}
              phx-click="filter"
              phx-value-type="file"
            >
              📁 Files
            </button>
          </div>

          <div style="flex: 1; max-width: 300px;">
            <input
              type="text"
              class="search-input"
              placeholder="Filter entries..."
              value={@search_query}
              phx-keyup="search"
              phx-debounce="300"
              style="width: 100%; padding: var(--space-2) var(--space-3);"
            />
          </div>
        </div>
      </div>
      <!-- Entry Grid -->
      <%= if Enum.empty?(@entries) do %>
        <div class="card" style="text-align: center; padding: var(--space-12);">
          <div style="font-size: 3rem; margin-bottom: var(--space-4);">📚</div>
          <h2 style="font-size: var(--text-xl); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            No entries yet
          </h2>
          <p style="color: var(--color-text-muted); margin-bottom: var(--space-6);">
            Start building your personal knowledge base
          </p>
          <button class="btn btn-primary" phx-click="new_entry">
            + Create Your First Entry
          </button>
        </div>
      <% else %>
        <div
          class="entry-grid"
          style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: var(--space-4);"
        >
          <%= for entry <- @entries do %>
            <.entry_card entry={entry} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp entry_card(assigns) do
    ~H"""
    <a
      href={~p"/app/library/#{@entry.id}"}
      class="card card-hover"
      style="display: flex; flex-direction: column; text-decoration: none; height: 100%;"
    >
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: var(--space-3);">
        <span style="font-size: 1.5rem;"><%= entry_icon(@entry) %></span>
        <.processing_status entry={@entry} />
      </div>

      <h3 style="font-size: var(--text-base); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2); line-height: var(--leading-tight);">
        <%= @entry.title || "Untitled" %>
      </h3>

      <p style="color: var(--color-text-muted); font-size: var(--text-sm); line-height: var(--leading-relaxed); flex: 1;">
        <%= truncate_content(@entry) %>
      </p>

      <div style="display: flex; justify-content: space-between; align-items: center; margin-top: var(--space-3); padding-top: var(--space-3); border-top: 1px solid var(--color-border-light);">
        <div style="display: flex; gap: var(--space-1); flex-wrap: wrap;">
          <%= for tag <- Enum.take(@entry.tags || [], 3) do %>
            <span style="background: var(--color-bg-subtle); color: var(--color-text-muted); padding: 0.125rem 0.375rem; border-radius: var(--radius-sm); font-size: var(--text-xs);">
              <%= tag.name %>
            </span>
          <% end %>
        </div>
        <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
          <%= format_date(@entry.inserted_at) %>
        </span>
      </div>
    </a>
    """
  end

  defp processing_status(assigns) do
    # TODO: Check actual processing status from Reader agent
    ~H"""
    <span class="status-badge status-complete">
      ✓ Processed
    </span>
    """
  end

  defp entry_icon(entry) do
    case entry.entry_type do
      "note" -> "📝"
      "article" -> "📄"
      "bookmark" -> "🔖"
      "file" -> "📁"
      "image" -> "🖼️"
      "audio" -> "🎵"
      "video" -> "🎬"
      _ -> "📝"
    end
  end

  defp truncate_content(entry) do
    content = entry.content || ""

    if String.length(content) > 100 do
      String.slice(content, 0, 100) <> "..."
    else
      content
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d")
  end

  @impl true
  def handle_event("new_entry", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/entries/new")}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    user = socket.assigns.current_user

    opts = [limit: 50, preload: [:tags]]
    opts = if type != "all", do: Keyword.put(opts, :entry_type, type), else: opts

    entries = Entries.list_entries(user.id, opts)

    {:noreply,
     socket
     |> assign(:filter_type, type)
     |> assign(:entries, entries)}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    user = socket.assigns.current_user

    entries =
      if String.trim(query) == "" do
        Entries.list_entries(user.id, limit: 50, preload: [:tags])
      else
        # TODO: Use Searcher agent for semantic search
        Entries.list_entries(user.id,
          limit: 50,
          preload: [:tags],
          search: query
        )
      end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:entries, entries)}
  end
end
