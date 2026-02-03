defmodule OnelistWeb.Dashboard.TrioChatLive do
  @moduledoc """
  The Trio Chat Dashboard - unified communication between splntrb, Key, and Stream.

  Layout:
  ┌─────────────────────┬─────────────────────┬─────────────────────────────┐
  │  splntrb ↔ Key      │  splntrb ↔ Stream   │  Key ↔ Stream (read-only)   │
  │  [messages...]      │  [messages...]      │  [messages...]              │
  │  [input box]        │  [input box]        │  (no input - viewport only) │
  ├─────────────────────┴─────────────────────┴─────────────────────────────┤
  │                         GROUP CHAT                                       │
  │  [messages...]                                                          │
  │  [input box]                                                            │
  └─────────────────────────────────────────────────────────────────────────┘

  PLAN-048: Unified Chat Dashboard
  """
  use OnelistWeb, :live_view

  alias Onelist.Chat

  @channels [:group, :dm_splntrb_key, :dm_splntrb_stream, :dm_key_stream]
  @current_user "splntrb"  # The human using this dashboard

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to all channels
      Enum.each(@channels, &Chat.subscribe/1)
    end

    # Load initial messages for all channels
    messages = load_all_messages()

    {:ok,
     socket
     |> assign(:current_user, @current_user)
     |> assign(:messages, messages)
     |> assign(:unread_counts, load_unread_counts())}
  end

  def render(assigns) do
    ~H"""
    <div class="trio-chat">
      <style>
        .trio-chat {
          display: flex;
          flex-direction: column;
          height: 100vh;
          background: #0a0a0a;
          color: #e0e0e0;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        .dm-row {
          display: flex;
          height: 35%;
          border-bottom: 1px solid #2a2a2a;
        }
        .dm-pane {
          flex: 1;
          display: flex;
          flex-direction: column;
          border-right: 1px solid #2a2a2a;
        }
        .dm-pane:last-child {
          border-right: none;
        }
        .dm-pane.readonly {
          opacity: 0.8;
        }
        .pane-header {
          padding: 0.75rem 1rem;
          background: #141414;
          border-bottom: 1px solid #2a2a2a;
          font-weight: 600;
          font-size: 0.85rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        .pane-header .badge {
          background: #3b82f6;
          color: white;
          padding: 0.15rem 0.5rem;
          border-radius: 10px;
          font-size: 0.75rem;
        }
        .message-list {
          flex: 1;
          overflow-y: auto;
          padding: 0.5rem;
        }
        .message {
          padding: 0.5rem 0.75rem;
          margin-bottom: 0.25rem;
          border-radius: 6px;
        }
        .message:hover {
          background: #1a1a1a;
        }
        .message .sender {
          font-weight: 600;
          margin-right: 0.5rem;
        }
        .message .sender.splntrb { color: #f59e0b; }
        .message .sender.key { color: #3b82f6; }
        .message .sender.stream { color: #10b981; }
        .message .time {
          color: #666;
          font-size: 0.75rem;
          margin-left: 0.5rem;
        }
        .message .content {
          margin-top: 0.25rem;
          line-height: 1.4;
          white-space: pre-wrap;
        }
        .input-area {
          padding: 0.5rem;
          background: #141414;
          border-top: 1px solid #2a2a2a;
        }
        .input-area form {
          display: flex;
          gap: 0.5rem;
        }
        .input-area input {
          flex: 1;
          background: #0a0a0a;
          border: 1px solid #2a2a2a;
          border-radius: 6px;
          padding: 0.5rem 0.75rem;
          color: #e0e0e0;
          font-size: 0.9rem;
        }
        .input-area input:focus {
          outline: none;
          border-color: #3b82f6;
        }
        .input-area button {
          background: #3b82f6;
          color: white;
          border: none;
          border-radius: 6px;
          padding: 0.5rem 1rem;
          cursor: pointer;
          font-weight: 500;
        }
        .input-area button:hover {
          background: #2563eb;
        }
        .group-pane {
          flex: 1;
          display: flex;
          flex-direction: column;
        }
        .group-pane .pane-header {
          background: #1a1a1a;
        }
        .readonly-notice {
          text-align: center;
          padding: 0.5rem;
          color: #666;
          font-size: 0.8rem;
          font-style: italic;
        }
      </style>

      <!-- DM Row -->
      <div class="dm-row">
        <!-- splntrb ↔ Key -->
        <div class="dm-pane">
          <div class="pane-header">
            <span>splntrb ↔ Key</span>
            <%= if @unread_counts[:dm_splntrb_key] > 0 do %>
              <span class="badge"><%= @unread_counts[:dm_splntrb_key] %></span>
            <% end %>
          </div>
          <div class="message-list" id="dm-splntrb-key-messages">
            <%= for message <- @messages[:dm_splntrb_key] || [] do %>
              <.message_item message={message} />
            <% end %>
          </div>
          <div class="input-area">
            <form phx-submit="send_dm" phx-value-channel="dm_splntrb_key" id="dm-key-form" onsubmit="setTimeout(() => this.reset(), 10)">
              <input
                type="text"
                name="content"
                placeholder="Message Key..."
                autocomplete="off"
              />
              <button type="submit">Send</button>
            </form>
          </div>
        </div>

        <!-- splntrb ↔ Stream -->
        <div class="dm-pane">
          <div class="pane-header">
            <span>splntrb ↔ Stream</span>
            <%= if @unread_counts[:dm_splntrb_stream] > 0 do %>
              <span class="badge"><%= @unread_counts[:dm_splntrb_stream] %></span>
            <% end %>
          </div>
          <div class="message-list" id="dm-splntrb-stream-messages">
            <%= for message <- @messages[:dm_splntrb_stream] || [] do %>
              <.message_item message={message} />
            <% end %>
          </div>
          <div class="input-area">
            <form phx-submit="send_dm" phx-value-channel="dm_splntrb_stream" id="dm-stream-form" onsubmit="setTimeout(() => this.reset(), 10)">
              <input
                type="text"
                name="content"
                placeholder="Message Stream..."
                autocomplete="off"
              />
              <button type="submit">Send</button>
            </form>
          </div>
        </div>

        <!-- Key ↔ Stream (read-only for splntrb) -->
        <div class="dm-pane readonly">
          <div class="pane-header">
            <span>Key ↔ Stream</span>
            <span style="color: #666; font-size: 0.75rem;">read-only</span>
          </div>
          <div class="message-list" id="dm-key-stream-messages">
            <%= for message <- @messages[:dm_key_stream] || [] do %>
              <.message_item message={message} />
            <% end %>
          </div>
          <div class="readonly-notice">
            Viewport only — Key and Stream coordinate here
          </div>
        </div>
      </div>

      <!-- Group Chat -->
      <div class="group-pane">
        <div class="pane-header">
          <span>🔺 The Trio — Group Chat</span>
          <%= if @unread_counts[:group] > 0 do %>
            <span class="badge"><%= @unread_counts[:group] %></span>
          <% end %>
        </div>
        <div class="message-list" id="group-messages">
          <%= for message <- @messages[:group] || [] do %>
            <.message_item message={message} />
          <% end %>
        </div>
        <div class="input-area">
          <form phx-submit="send_group" id="group-form" onsubmit="setTimeout(() => this.reset(), 10)">
            <input
              type="text"
              name="content"
              placeholder="Message the Trio..."
              autocomplete="off"
            />
            <button type="submit">Send</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ============================================
  # COMPONENTS
  # ============================================

  defp message_item(assigns) do
    ~H"""
    <div class="message" id={"message-#{@message.id}"}>
      <span class={"sender #{@message.sender}"}><%= @message.sender %></span>
      <span class="time"><%= format_time(@message.inserted_at) %></span>
      <div class="content"><%= @message.content %></div>
    </div>
    """
  end

  # ============================================
  # EVENT HANDLERS
  # ============================================

  def handle_event("send_group", %{"content" => content}, socket) when content != "" do
    Chat.send_message(:group, socket.assigns.current_user, content)
    {:noreply, socket}
  end

  def handle_event("send_group", _, socket), do: {:noreply, socket}

  def handle_event("send_dm", %{"content" => content, "channel" => channel}, socket) when content != "" do
    channel_atom = String.to_existing_atom(channel)
    Chat.send_message(channel_atom, socket.assigns.current_user, content)
    {:noreply, socket}
  end

  def handle_event("send_dm", _, socket), do: {:noreply, socket}


  # ============================================
  # PUBSUB HANDLERS
  # ============================================

  def handle_info({:new_message, message}, socket) do
    channel = channel_for_message(message)

    # Append message to the appropriate channel
    messages = socket.assigns.messages
    channel_messages = Map.get(messages, channel, [])
    updated_messages = Map.put(messages, channel, channel_messages ++ [message])

    {:noreply, assign(socket, :messages, updated_messages)}
  end

  # ============================================
  # HELPERS
  # ============================================

  defp load_all_messages do
    %{
      group: load_channel_messages(:group),
      dm_splntrb_key: load_channel_messages(:dm_splntrb_key),
      dm_splntrb_stream: load_channel_messages(:dm_splntrb_stream),
      dm_key_stream: load_channel_messages(:dm_key_stream)
    }
  end

  defp load_channel_messages(channel) do
    case Chat.get_messages(channel, limit: 100) do
      {:ok, messages} -> messages
      _ -> []
    end
  end

  defp load_unread_counts do
    %{
      group: get_unread_count(:group),
      dm_splntrb_key: get_unread_count(:dm_splntrb_key),
      dm_splntrb_stream: get_unread_count(:dm_splntrb_stream),
      dm_key_stream: get_unread_count(:dm_key_stream)
    }
  end

  defp get_unread_count(channel) do
    case Chat.unread_count(channel, @current_user) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  defp channel_for_message(message) do
    # Get channel name from the message's channel association
    case Onelist.Repo.preload(message, :channel).channel.name do
      "group" -> :group
      "dm:splntrb-key" -> :dm_splntrb_key
      "dm:splntrb-stream" -> :dm_splntrb_stream
      "dm:key-stream" -> :dm_key_stream
      _ -> :group
    end
  end

  defp format_time(nil), do: ""
  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end
end
