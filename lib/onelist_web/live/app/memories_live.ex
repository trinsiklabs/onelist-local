defmodule OnelistWeb.App.MemoriesLive do
  @moduledoc """
  Global memories page - browse all AI-extracted memories.
  """
  use OnelistWeb, :live_view

  alias Onelist.Reader

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Load current (non-superseded) memories
    memories = Reader.get_current_memories(user.id, limit: 100)

    {:ok,
     socket
     |> assign(:page_title, "Memories")
     |> assign(:current_path, "/app/memories")
     |> assign(:memories, memories)
     |> assign(:filter_type, "all")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="memories-page">
      <div class="page-header" style="margin-bottom: var(--space-6);">
        <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
          🧠 Memories
        </h1>
        <p style="color: var(--color-text-muted); margin-top: var(--space-2);">
          Atomic facts extracted from your entries by the Reader agent
        </p>
      </div>
      <!-- Filters -->
      <div class="card" style="margin-bottom: var(--space-4); padding: var(--space-3);">
        <div style="display: flex; gap: var(--space-2); flex-wrap: wrap;">
          <button
            class={["btn", (@filter_type == "all" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="all"
          >
            All
          </button>
          <button
            class={["btn", (@filter_type == "fact" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="fact"
          >
            Facts
          </button>
          <button
            class={["btn", (@filter_type == "preference" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="preference"
          >
            Preferences
          </button>
          <button
            class={["btn", (@filter_type == "event" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="event"
          >
            Events
          </button>
          <button
            class={["btn", (@filter_type == "observation" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="observation"
          >
            Observations
          </button>
          <button
            class={["btn", (@filter_type == "decision" && "btn-secondary") || "btn-ghost"]}
            phx-click="filter"
            phx-value-type="decision"
          >
            Decisions
          </button>
        </div>
      </div>

      <%= if Enum.empty?(@memories) do %>
        <div class="card" style="text-align: center; padding: var(--space-12);">
          <div style="font-size: 3rem; margin-bottom: var(--space-4);">🧠</div>
          <h2 style="font-size: var(--text-xl); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            No memories yet
          </h2>
          <p style="color: var(--color-text-muted); margin-bottom: var(--space-6); max-width: 400px; margin-left: auto; margin-right: auto;">
            The Reader agent will automatically extract atomic memories from your entries. Create some entries to get started.
          </p>
          <a href={~p"/app/library"} class="btn btn-primary">
            Go to Library
          </a>
        </div>
      <% else %>
        <div style="display: flex; flex-direction: column; gap: var(--space-4);">
          <%= for memory <- @memories do %>
            <.memory_card memory={memory} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp memory_card(assigns) do
    ~H"""
    <div class="card">
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: var(--space-3);">
        <span class={"memory-badge memory-badge-#{@memory.memory_type}"}>
          <%= String.upcase(@memory.memory_type) %>
        </span>
        <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
          <%= format_confidence(@memory.confidence) %>% confidence
        </span>
      </div>
      <p style="color: var(--color-text); line-height: var(--leading-relaxed); margin-bottom: var(--space-3);">
        <%= @memory.content %>
      </p>
      <div style="display: flex; justify-content: space-between; align-items: center; padding-top: var(--space-3); border-top: 1px solid var(--color-border-light);">
        <a
          href={~p"/app/library/#{@memory.entry_id}"}
          style="color: var(--color-primary); font-size: var(--text-sm); text-decoration: none;"
        >
          View source entry →
        </a>
        <span style="color: var(--color-text-subtle); font-size: var(--text-xs);">
          Extracted <%= Calendar.strftime(@memory.inserted_at, "%b %d, %Y") %>
        </span>
      </div>
    </div>
    """
  end

  defp format_confidence(confidence) do
    confidence
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    user = socket.assigns.current_user

    memories =
      if type == "all" do
        Reader.get_current_memories(user.id, limit: 100)
      else
        Reader.get_current_memories(user.id, limit: 100, memory_type: type)
      end

    {:noreply,
     socket
     |> assign(:filter_type, type)
     |> assign(:memories, memories)}
  end
end
