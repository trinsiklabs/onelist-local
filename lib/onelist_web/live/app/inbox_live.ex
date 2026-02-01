defmodule OnelistWeb.App.InboxLive do
  @moduledoc """
  Inbox view - shows new/unprocessed entries.
  """
  use OnelistWeb, :live_view

  alias Onelist.Entries

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    
    # Get unprocessed entries (no memories extracted yet)
    entries = Entries.list_entries(user.id, 
      limit: 50,
      preload: [:tags]
    )
    
    # For MVP, show all entries in inbox
    # TODO: Filter to only unprocessed once Reader agent is integrated
    
    {:ok, 
      socket
      |> assign(:page_title, "Inbox")
      |> assign(:current_path, "/app")
      |> assign(:entries, entries)
      |> assign(:inbox_count, length(entries))
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inbox-page">
      <div class="page-header" style="margin-bottom: var(--space-6);">
        <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
          📥 Inbox
        </h1>
        <p style="color: var(--color-text-muted); margin-top: var(--space-2);">
          New and unprocessed entries
        </p>
      </div>
      
      <%= if Enum.empty?(@entries) do %>
        <div class="card" style="text-align: center; padding: var(--space-12);">
          <div style="font-size: 3rem; margin-bottom: var(--space-4);">📭</div>
          <h2 style="font-size: var(--text-xl); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            Inbox is empty
          </h2>
          <p style="color: var(--color-text-muted); margin-bottom: var(--space-6);">
            Create your first entry to get started
          </p>
          <button class="btn btn-primary" phx-click="new_entry">
            + New Entry
          </button>
        </div>
      <% else %>
        <div class="entry-list" style="display: flex; flex-direction: column; gap: var(--space-4);">
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
    <a href={~p"/app/library/#{@entry.id}"} class="card card-hover" style="display: block; text-decoration: none;">
      <div style="display: flex; justify-content: space-between; align-items: flex-start;">
        <div style="flex: 1;">
          <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            <%= @entry.title || "Untitled" %>
          </h3>
          <p style="color: var(--color-text-muted); font-size: var(--text-sm); line-height: var(--leading-relaxed);">
            <%= truncate_content(@entry) %>
          </p>
        </div>
        <div style="display: flex; flex-direction: column; align-items: flex-end; gap: var(--space-2);">
          <span class="status-badge status-pending">
            Pending
          </span>
          <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
            <%= format_date(@entry.inserted_at) %>
          </span>
        </div>
      </div>
      
      <%= if @entry.tags && length(@entry.tags) > 0 do %>
        <div style="display: flex; gap: var(--space-2); margin-top: var(--space-3); flex-wrap: wrap;">
          <%= for tag <- Enum.take(@entry.tags, 5) do %>
            <span style="background: var(--color-bg-subtle); color: var(--color-text-muted); padding: 0.125rem 0.5rem; border-radius: var(--radius-full); font-size: var(--text-xs);">
              🏷️ <%= tag.name %>
            </span>
          <% end %>
        </div>
      <% end %>
    </a>
    """
  end

  defp truncate_content(entry) do
    content = entry.content || ""
    if String.length(content) > 150 do
      String.slice(content, 0, 150) <> "..."
    else
      content
    end
  end

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  @impl true
  def handle_event("new_entry", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/entries/new")}
  end
end
