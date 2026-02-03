defmodule OnelistWeb.App.EntryDetailLive do
  @moduledoc """
  Entry detail view with tabs for Content, Memories, Assets, History.
  """
  use OnelistWeb, :live_view

  alias Onelist.Entries
  alias Onelist.Reader

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_user

    case Entries.get_entry(user.id, id, preload: [:tags]) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Entry not found")
         |> push_navigate(to: ~p"/app/library")}

      entry ->
        # Load memories for this entry
        memories = Reader.get_memories_for_entry(entry.id)

        {:ok,
         socket
         |> assign(:page_title, entry.title || "Untitled")
         |> assign(:current_path, "/app/library/#{id}")
         |> assign(:entry, entry)
         |> assign(:active_tab, "content")
         |> assign(:memories, memories)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="entry-detail-page">
      <!-- Header -->
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: var(--space-6);">
        <div>
          <a
            href={~p"/app/library"}
            style="color: var(--color-text-muted); text-decoration: none; font-size: var(--text-sm); display: inline-flex; align-items: center; gap: var(--space-2); margin-bottom: var(--space-2);"
          >
            ← Back to Library
          </a>
          <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
            <%= @entry.title || "Untitled" %>
          </h1>
          <div style="display: flex; gap: var(--space-4); margin-top: var(--space-2); color: var(--color-text-muted); font-size: var(--text-sm);">
            <span>Created <%= format_date(@entry.inserted_at) %></span>
            <span>•</span>
            <span>Updated <%= format_date(@entry.updated_at) %></span>
          </div>
        </div>
        <div style="display: flex; gap: var(--space-2);">
          <a href={~p"/app/entries/#{@entry.id}/edit"} class="btn btn-ghost">
            ✏️ Edit
          </a>
          <button
            class="btn btn-ghost"
            style="color: var(--color-error);"
            phx-click="delete"
            data-confirm="Are you sure you want to delete this entry?"
          >
            🗑️ Delete
          </button>
        </div>
      </div>
      <!-- Tabs -->
      <div style="display: flex; gap: var(--space-1); border-bottom: 1px solid var(--color-border); margin-bottom: var(--space-6);">
        <button
          class={["tab-button", @active_tab == "content" && "active"]}
          phx-click="switch_tab"
          phx-value-tab="content"
          style={tab_style(@active_tab == "content")}
        >
          📄 Content
        </button>
        <button
          class={["tab-button", @active_tab == "memories" && "active"]}
          phx-click="switch_tab"
          phx-value-tab="memories"
          style={tab_style(@active_tab == "memories")}
        >
          🧠 Memories
          <span style="background: var(--color-secondary-light); color: var(--color-secondary); padding: 0.125rem 0.5rem; border-radius: var(--radius-full); font-size: var(--text-xs); margin-left: var(--space-2);">
            <%= length(@memories) %>
          </span>
        </button>
        <button
          class={["tab-button", @active_tab == "assets" && "active"]}
          phx-click="switch_tab"
          phx-value-tab="assets"
          style={tab_style(@active_tab == "assets")}
        >
          📎 Assets
        </button>
        <button
          class={["tab-button", @active_tab == "history" && "active"]}
          phx-click="switch_tab"
          phx-value-tab="history"
          style={tab_style(@active_tab == "history")}
        >
          📜 History
        </button>
      </div>
      <!-- Tab Content -->
      <div class="tab-content">
        <%= case @active_tab do %>
          <% "content" -> %>
            <.content_tab entry={@entry} />
          <% "memories" -> %>
            <.memories_tab memories={@memories} entry={@entry} />
          <% "assets" -> %>
            <.assets_tab entry={@entry} />
          <% "history" -> %>
            <.history_tab entry={@entry} />
        <% end %>
      </div>
    </div>
    """
  end

  defp tab_style(active) do
    base =
      "padding: var(--space-3) var(--space-4); border: none; background: transparent; cursor: pointer; font-size: var(--text-sm); font-weight: var(--font-medium); display: inline-flex; align-items: center; border-bottom: 2px solid transparent; margin-bottom: -1px;"

    if active do
      base <> " color: var(--color-primary); border-bottom-color: var(--color-primary);"
    else
      base <> " color: var(--color-text-muted);"
    end
  end

  defp content_tab(assigns) do
    ~H"""
    <div class="card">
      <div style="white-space: pre-wrap; line-height: var(--leading-relaxed); color: var(--color-text);">
        <%= @entry.content || "No content" %>
      </div>
    </div>
    <!-- Tags -->
    <%= if @entry.tags && length(@entry.tags) > 0 do %>
      <div class="card" style="margin-top: var(--space-4);">
        <h3 style="font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-3);">
          🏷️ Tags
        </h3>
        <div style="display: flex; gap: var(--space-2); flex-wrap: wrap;">
          <%= for tag <- @entry.tags do %>
            <span style="background: var(--color-bg-subtle); color: var(--color-text-muted); padding: var(--space-1) var(--space-3); border-radius: var(--radius-full); font-size: var(--text-sm);">
              <%= tag.name %>
            </span>
          <% end %>
        </div>
      </div>
    <% end %>
    """
  end

  defp memories_tab(assigns) do
    ~H"""
    <%= if Enum.empty?(@memories) do %>
      <div class="card" style="text-align: center; padding: var(--space-8);">
        <div style="font-size: 2rem; margin-bottom: var(--space-3);">🧠</div>
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
          No memories yet
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
          The Reader agent will extract atomic memories from this entry
        </p>
      </div>
    <% else %>
      <div style="display: flex; flex-direction: column; gap: var(--space-3);">
        <%= for memory <- @memories do %>
          <.memory_card memory={memory} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp memory_card(assigns) do
    ~H"""
    <div class="card">
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: var(--space-2);">
        <span class={"memory-badge memory-badge-#{@memory.memory_type}"}>
          <%= String.upcase(@memory.memory_type) %>
        </span>
        <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
          <%= format_confidence(@memory.confidence) %>% confidence
        </span>
      </div>
      <p style="color: var(--color-text); line-height: var(--leading-relaxed);">
        <%= @memory.content %>
      </p>
    </div>
    """
  end

  defp format_confidence(confidence) do
    confidence
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  defp assets_tab(assigns) do
    ~H"""
    <div class="card" style="text-align: center; padding: var(--space-8);">
      <div style="font-size: 2rem; margin-bottom: var(--space-3);">📎</div>
      <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
        No assets
      </h3>
      <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
        Attachments and files will appear here
      </p>
    </div>
    """
  end

  defp history_tab(assigns) do
    ~H"""
    <div class="card" style="text-align: center; padding: var(--space-8);">
      <div style="font-size: 2rem; margin-bottom: var(--space-3);">📜</div>
      <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
        Version history
      </h3>
      <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
        Previous versions of this entry will appear here
      </p>
    </div>
    """
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    entry = socket.assigns.entry
    user = socket.assigns.current_user

    case Entries.delete_entry(user.id, entry.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Entry deleted")
         |> push_navigate(to: ~p"/app/library")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete entry")}
    end
  end
end
