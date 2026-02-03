defmodule OnelistWeb.App.SettingsLive do
  @moduledoc """
  Settings page - configure agents, storage, and account.
  """
  use OnelistWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    section = params["section"] || "general"

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:current_path, "/app/settings")
     |> assign(:section, section)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = params["section"] || "general"
    {:noreply, assign(socket, :section, section)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="settings-page" style="display: flex; gap: var(--space-6);">
      <!-- Settings Navigation -->
      <nav style="width: 200px; flex-shrink: 0;">
        <div class="card" style="padding: var(--space-2);">
          <a
            href={~p"/app/settings"}
            class={["nav-item", @section == "general" && "active"]}
            style="display: block;"
          >
            ⚙️ General
          </a>
          <a
            href={~p"/app/settings/reader"}
            class={["nav-item", @section == "reader" && "active"]}
            style="display: block;"
          >
            🧠 Reader Agent
          </a>
          <a
            href={~p"/app/settings/searcher"}
            class={["nav-item", @section == "searcher" && "active"]}
            style="display: block;"
          >
            🔍 Searcher Agent
          </a>
          <a
            href={~p"/app/settings/enrichment"}
            class={["nav-item", @section == "enrichment" && "active"]}
            style="display: block;"
          >
            ✨ Asset Enrichment
          </a>
          <a
            href={~p"/app/settings/storage"}
            class={["nav-item", @section == "storage" && "active"]}
            style="display: block;"
          >
            💾 Storage
          </a>
          <a
            href={~p"/app/settings/api"}
            class={["nav-item", @section == "api" && "active"]}
            style="display: block;"
          >
            🔑 API Keys
          </a>
          <a
            href={~p"/app/settings/billing"}
            class={["nav-item", @section == "billing" && "active"]}
            style="display: block;"
          >
            💳 Billing
          </a>
        </div>
      </nav>
      <!-- Settings Content -->
      <div style="flex: 1;">
        <%= case @section do %>
          <% "general" -> %>
            <.general_settings socket={@socket} />
          <% "reader" -> %>
            <.reader_settings socket={@socket} />
          <% "searcher" -> %>
            <.searcher_settings socket={@socket} />
          <% "enrichment" -> %>
            <.enrichment_settings socket={@socket} />
          <% "storage" -> %>
            <.storage_settings socket={@socket} />
          <% "api" -> %>
            <.api_settings socket={@socket} />
          <% "billing" -> %>
            <.billing_settings socket={@socket} />
          <% _ -> %>
            <.general_settings socket={@socket} />
        <% end %>
      </div>
    </div>
    """
  end

  defp general_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        ⚙️ General Settings
      </h1>

      <div class="card" style="margin-bottom: var(--space-4);">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Account
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
          Manage your account settings in the
          <a href={~p"/users/settings"} style="color: var(--color-primary);">Account Settings</a>
          page.
        </p>
      </div>

      <div class="card">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Data Export
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Download all your data including entries, memories, and tags.
        </p>
        <button class="btn btn-ghost">
          📥 Export Data
        </button>
      </div>
    </div>
    """
  end

  defp reader_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        🧠 Reader Agent Settings
      </h1>

      <div class="card" style="margin-bottom: var(--space-4);">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Memory Extraction
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Configure how the Reader agent extracts atomic memories from your entries.
        </p>

        <div style="display: flex; flex-direction: column; gap: var(--space-4);">
          <div>
            <label style="display: block; font-size: var(--text-sm); font-weight: var(--font-medium); color: var(--color-text); margin-bottom: var(--space-2);">
              Auto-process new entries
            </label>
            <select style="padding: var(--space-2) var(--space-3); border: 1px solid var(--color-border); border-radius: var(--radius-md); width: 200px;">
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
            </select>
          </div>

          <div>
            <label style="display: block; font-size: var(--text-sm); font-weight: var(--font-medium); color: var(--color-text); margin-bottom: var(--space-2);">
              LLM Provider
            </label>
            <select style="padding: var(--space-2) var(--space-3); border: 1px solid var(--color-border); border-radius: var(--radius-md); width: 200px;">
              <option value="openai">OpenAI (GPT-4o)</option>
              <option value="anthropic">Anthropic (Claude)</option>
            </select>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp searcher_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        🔍 Searcher Agent Settings
      </h1>

      <div class="card">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Embedding Configuration
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Configure semantic search embeddings.
        </p>

        <div>
          <label style="display: block; font-size: var(--text-sm); font-weight: var(--font-medium); color: var(--color-text); margin-bottom: var(--space-2);">
            Embedding Model
          </label>
          <select style="padding: var(--space-2) var(--space-3); border: 1px solid var(--color-border); border-radius: var(--radius-md); width: 250px;">
            <option value="text-embedding-3-small">OpenAI text-embedding-3-small</option>
            <option value="text-embedding-3-large">OpenAI text-embedding-3-large</option>
          </select>
        </div>
      </div>
    </div>
    """
  end

  defp enrichment_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        ✨ Asset Enrichment Settings
      </h1>

      <div class="card">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Auto-enrichment
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Configure automatic processing for uploaded assets.
        </p>

        <div style="display: flex; flex-direction: column; gap: var(--space-3);">
          <label style="display: flex; align-items: center; gap: var(--space-2); cursor: pointer;">
            <input type="checkbox" checked style="width: 1rem; height: 1rem;" />
            <span style="font-size: var(--text-sm); color: var(--color-text);">
              Auto-transcribe audio files
            </span>
          </label>
          <label style="display: flex; align-items: center; gap: var(--space-2); cursor: pointer;">
            <input type="checkbox" checked style="width: 1rem; height: 1rem;" />
            <span style="font-size: var(--text-sm); color: var(--color-text);">
              Auto-describe images
            </span>
          </label>
          <label style="display: flex; align-items: center; gap: var(--space-2); cursor: pointer;">
            <input type="checkbox" checked style="width: 1rem; height: 1rem;" />
            <span style="font-size: var(--text-sm); color: var(--color-text);">
              Extract text from images (OCR)
            </span>
          </label>
        </div>
      </div>
    </div>
    """
  end

  defp storage_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        💾 Storage Settings
      </h1>

      <div class="card" style="margin-bottom: var(--space-4);">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Usage
        </h3>
        <div style="background: var(--color-bg-subtle); border-radius: var(--radius-md); height: 0.5rem; margin-bottom: var(--space-2);">
          <div style="background: var(--color-primary); border-radius: var(--radius-md); height: 100%; width: 5%;">
          </div>
        </div>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
          50 MB of 1 GB used
        </p>
      </div>

      <div class="card">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          BYOB (Bring Your Own Bucket)
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Connect your own S3-compatible storage for assets.
        </p>
        <button class="btn btn-ghost">
          Configure BYOB
        </button>
      </div>
    </div>
    """
  end

  defp api_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        🔑 API Keys
      </h1>

      <div class="card">
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Manage your API keys for programmatic access.
        </p>
        <a href={~p"/app/api-keys"} class="btn btn-primary">
          Manage API Keys
        </a>
      </div>
    </div>
    """
  end

  defp billing_settings(assigns) do
    ~H"""
    <div>
      <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text); margin-bottom: var(--space-6);">
        💳 Billing
      </h1>

      <div class="card" style="margin-bottom: var(--space-4);">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
          Current Plan
        </h3>
        <p style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-primary); margin-bottom: var(--space-2);">
          Free
        </p>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm);">
          Self-hosted with local storage
        </p>
      </div>

      <div class="card">
        <h3 style="font-size: var(--text-lg); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-4);">
          Upgrade
        </h3>
        <p style="color: var(--color-text-muted); font-size: var(--text-sm); margin-bottom: var(--space-4);">
          Unlock cloud sync, public pages, and managed hosting.
        </p>
        <button class="btn btn-primary">
          View Plans
        </button>
      </div>
    </div>
    """
  end
end
