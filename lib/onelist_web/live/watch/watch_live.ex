defmodule OnelistWeb.Watch.WatchLive do
  @moduledoc """
  Watch index page - hub for monitoring endpoints.

  PLAN-051: Phoenix Auth Migration
  """
  use OnelistWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="watch-index">
      <style>
        .watch-index {
          font-family: system-ui, -apple-system, sans-serif;
          max-width: 600px;
          margin: 50px auto;
          padding: 20px;
          background: #0a0a0a;
          color: #e0e0e0;
          min-height: 100vh;
        }
        .watch-index h1 {
          border-bottom: 2px solid #333;
          padding-bottom: 10px;
          margin-bottom: 20px;
        }
        .endpoint {
          margin: 20px 0;
          padding: 20px;
          background: #141414;
          border-radius: 8px;
          border: 1px solid #2a2a2a;
        }
        .endpoint h2 {
          margin: 0 0 10px 0;
          font-size: 1.2em;
        }
        .endpoint p {
          margin: 0;
          color: #888;
        }
        .endpoint a {
          color: #3b82f6;
          text-decoration: none;
        }
        .endpoint a:hover {
          text-decoration: underline;
        }
        .status {
          font-size: 0.85em;
          color: #28a745;
          margin-top: 8px;
        }
        .user-info {
          margin-bottom: 20px;
          padding: 10px 15px;
          background: #1a1a1a;
          border-radius: 6px;
          font-size: 0.9em;
          color: #888;
        }
        .user-info strong {
          color: #e0e0e0;
        }
      </style>

      <h1>Stream Watch</h1>

      <div class="user-info">
        Logged in as <strong><%= @current_user.username || @current_user.email %></strong>
        · <a href="/logout" data-method="delete">Logout</a>
      </div>

      <p>Monitoring endpoints for stream.onelist.my</p>

      <div class="endpoint">
        <h2><a href="/watch/livelog">Live Log</a></h2>
        <p>Real-time activity stream from Stream and connected services.</p>
        <div class="status">LiveView - Auto-updates</div>
      </div>

      <div class="endpoint">
        <h2><a href="/watch/workspace">Workspace</a></h2>
        <p>Browse OpenClaw workspace files, memory, and configuration.</p>
        <div class="status">File browser - Markdown rendering</div>
      </div>

      <div class="endpoint">
        <h2><a href="/watch/swarm">Swarm</a></h2>
        <p>Claude Code Swarm content - plans, docs, roster, and more.</p>
        <div class="status">File browser - Markdown rendering</div>
      </div>

      <div class="endpoint">
        <h2><a href="/dashboard">Trio Chat</a></h2>
        <p>Real-time chat between splntrb, Keystone, and Stream.</p>
        <div class="status">LiveView - Real-time messaging</div>
      </div>
    </div>
    """
  end
end
