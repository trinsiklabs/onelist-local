defmodule OnelistWeb.App.ActivityLive do
  @moduledoc """
  Activity log - shows agent processing history and costs.
  """
  use OnelistWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Load activity from agent logs
    activities = []

    {:ok,
     socket
     |> assign(:page_title, "Activity")
     |> assign(:current_path, "/app/activity")
     |> assign(:activities, activities)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="activity-page">
      <div class="page-header" style="margin-bottom: var(--space-6);">
        <h1 style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
          📊 Activity
        </h1>
        <p style="color: var(--color-text-muted); margin-top: var(--space-2);">
          Agent processing history and API usage
        </p>
      </div>
      <!-- Stats Cards -->
      <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: var(--space-4); margin-bottom: var(--space-6);">
        <div class="card">
          <div style="font-size: var(--text-sm); color: var(--color-text-muted); margin-bottom: var(--space-1);">
            Total Entries Processed
          </div>
          <div style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
            0
          </div>
        </div>
        <div class="card">
          <div style="font-size: var(--text-sm); color: var(--color-text-muted); margin-bottom: var(--space-1);">
            Memories Extracted
          </div>
          <div style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-secondary);">
            0
          </div>
        </div>
        <div class="card">
          <div style="font-size: var(--text-sm); color: var(--color-text-muted); margin-bottom: var(--space-1);">
            API Costs (This Month)
          </div>
          <div style="font-size: var(--text-2xl); font-weight: var(--font-bold); color: var(--color-text);">
            $0.00
          </div>
        </div>
      </div>
      <!-- Activity List -->
      <%= if Enum.empty?(@activities) do %>
        <div class="card" style="text-align: center; padding: var(--space-12);">
          <div style="font-size: 3rem; margin-bottom: var(--space-4);">📊</div>
          <h2 style="font-size: var(--text-xl); font-weight: var(--font-semibold); color: var(--color-text); margin-bottom: var(--space-2);">
            No activity yet
          </h2>
          <p style="color: var(--color-text-muted); max-width: 400px; margin-left: auto; margin-right: auto;">
            Agent activity will appear here as entries are processed by Reader, Searcher, and other agents.
          </p>
        </div>
      <% else %>
        <div class="card" style="padding: 0;">
          <table style="width: 100%; border-collapse: collapse;">
            <thead>
              <tr style="border-bottom: 1px solid var(--color-border);">
                <th style="text-align: left; padding: var(--space-3) var(--space-4); font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text-muted);">
                  Time
                </th>
                <th style="text-align: left; padding: var(--space-3) var(--space-4); font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text-muted);">
                  Agent
                </th>
                <th style="text-align: left; padding: var(--space-3) var(--space-4); font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text-muted);">
                  Action
                </th>
                <th style="text-align: left; padding: var(--space-3) var(--space-4); font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text-muted);">
                  Status
                </th>
                <th style="text-align: right; padding: var(--space-3) var(--space-4); font-size: var(--text-sm); font-weight: var(--font-semibold); color: var(--color-text-muted);">
                  Cost
                </th>
              </tr>
            </thead>
            <tbody>
              <%= for activity <- @activities do %>
                <tr style="border-bottom: 1px solid var(--color-border-light);">
                  <td style="padding: var(--space-3) var(--space-4); font-size: var(--text-sm); color: var(--color-text-muted);">
                    <%= format_time(activity.inserted_at) %>
                  </td>
                  <td style="padding: var(--space-3) var(--space-4); font-size: var(--text-sm); color: var(--color-text);">
                    <%= activity.agent %>
                  </td>
                  <td style="padding: var(--space-3) var(--space-4); font-size: var(--text-sm); color: var(--color-text);">
                    <%= activity.action %>
                  </td>
                  <td style="padding: var(--space-3) var(--space-4);">
                    <span class={"status-badge status-#{activity.status}"}>
                      <%= activity.status %>
                    </span>
                  </td>
                  <td style="padding: var(--space-3) var(--space-4); font-size: var(--text-sm); color: var(--color-text); text-align: right;">
                    $<%= :erlang.float_to_binary(activity.cost, decimals: 4) %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%b %d, %I:%M %p")
  end
end
