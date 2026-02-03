defmodule OnelistWeb.LivelogLive do
  @moduledoc """
  LiveView page for public Livelog display.

  Shows real-time Stream conversations with automatic redaction.
  Accessible at /livelog without authentication.
  """
  use OnelistWeb, :live_view

  alias Onelist.Livelog
  alias Onelist.Livelog.Publisher

  @messages_per_page 50
  @max_messages 200

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Publisher.subscribe()
      # Refresh relative timestamps every 30 seconds
      :timer.send_interval(30_000, self(), :refresh_timestamps)
    end

    messages = Livelog.list_recent_messages(@messages_per_page)
    stats = Livelog.get_stats()

    {:ok,
     socket
     |> assign(:messages, messages)
     |> assign(:stats, stats)
     |> assign(:loading_more, false)
     |> assign(:tick, 0)
     |> assign(:messages_per_page, @messages_per_page)
     |> assign(:page_title, "Livelog — Stream's Conversations")}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Prepend new message, cap at max
    messages =
      [message | socket.assigns.messages]
      |> Enum.take(@max_messages)

    # Update stats
    stats = %{
      socket.assigns.stats
      | total_messages: socket.assigns.stats.total_messages + 1
    }

    {:noreply,
     socket
     |> assign(:messages, messages)
     |> assign(:stats, stats)
     |> push_event("new-message", %{id: message.id})}
  end

  @impl true
  def handle_info(:refresh_timestamps, socket) do
    # Bump tick to force re-render of timestamps
    {:noreply, assign(socket, :tick, socket.assigns.tick + 1)}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    case List.last(socket.assigns.messages) do
      nil ->
        {:noreply, socket}

      oldest ->
        more = Livelog.list_messages_before(oldest.original_timestamp, @messages_per_page)

        {:noreply,
         socket
         |> assign(:messages, socket.assigns.messages ++ more)
         |> assign(:loading_more, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-950">
      <!-- Header -->
      <header class="sticky top-0 z-10 bg-gray-950/95 backdrop-blur border-b border-gray-800">
        <div class="max-w-4xl mx-auto px-4 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <div class="relative">
                <span class="text-2xl">🔴</span>
                <span class="absolute -top-0.5 -right-0.5 w-2 h-2 bg-red-500 rounded-full animate-pulse">
                </span>
              </div>
              <div>
                <h1 class="text-xl font-bold text-white">Livelog</h1>
                <p class="text-sm text-gray-400">Stream's conversations in real-time</p>
              </div>
            </div>
            <div class="flex items-center gap-4 text-sm text-gray-400">
              <span>📝 <%= @stats.total_messages %> messages</span>
              <%= if @stats.redaction_rate > 0 do %>
                <span class="text-yellow-500">🔒 <%= @stats.redaction_rate %>% redacted</span>
              <% end %>
            </div>
          </div>
        </div>
      </header>
      <!-- Disclaimer -->
      <div class="bg-gray-900 border-b border-gray-800">
        <div class="max-w-4xl mx-auto px-4 py-3">
          <p class="text-sm text-gray-400">
            Real-time log of conversations between
            <a href="https://x.com/splntrb" target="_blank" class="text-blue-400 hover:underline">
              @splntrb
            </a>
            and their AI assistant Stream.
            Sensitive information is automatically redacted.
            <span class="text-gray-500">Privacy-first transparency.</span>
          </p>
        </div>
      </div>
      <!-- Messages -->
      <main class="max-w-4xl mx-auto px-4 py-6">
        <div class="space-y-4" id="messages-list" phx-update="stream">
          <%= for {message, idx} <- Enum.with_index(@messages) do %>
            <%= if idx == 0 or not same_day?(message.original_timestamp, Enum.at(@messages, idx - 1).original_timestamp) do %>
              <.day_separator date={message.original_timestamp} />
            <% end %>
            <.message_card message={message} />
          <% end %>
        </div>

        <%= if length(@messages) >= @messages_per_page do %>
          <div class="mt-6 text-center">
            <button
              phx-click="load-more"
              class="px-4 py-2 bg-gray-800 text-gray-300 rounded-lg hover:bg-gray-700 transition"
              disabled={@loading_more}
            >
              <%= if @loading_more do %>
                Loading...
              <% else %>
                Load older messages
              <% end %>
            </button>
          </div>
        <% end %>

        <%= if @messages == [] do %>
          <div class="text-center py-12">
            <p class="text-gray-500 text-lg">No messages yet.</p>
            <p class="text-gray-600 text-sm mt-2">Conversations will appear here in real-time.</p>
          </div>
        <% end %>
      </main>
      <!-- Footer -->
      <footer class="border-t border-gray-800 mt-12">
        <div class="max-w-4xl mx-auto px-4 py-6 text-center text-sm text-gray-500">
          <p>
            Powered by <a href="https://onelist.my" class="text-blue-400 hover:underline">Onelist</a>
            — AI memory infrastructure
          </p>
        </div>
      </footer>
    </div>
    """
  end

  defp day_separator(assigns) do
    ~H"""
    <div class="flex items-center gap-4 py-2">
      <div class="flex-1 h-px bg-gray-700"></div>
      <span class="text-sm font-medium text-gray-400"><%= format_date(@date) %></span>
      <div class="flex-1 h-px bg-gray-700"></div>
    </div>
    """
  end

  defp message_card(assigns) do
    ~H"""
    <div class={"p-4 rounded-lg border #{role_styles(@message.role)}"} id={"message-#{@message.id}"}>
      <div class="flex items-start justify-between gap-4">
        <div class="flex items-center gap-2">
          <span class="text-lg"><%= role_emoji(@message.role) %></span>
          <span class={"font-medium #{role_name_color(@message.role)}"}>
            <%= role_display(@message.role) %>
          </span>
          <%= if @message.redaction_applied do %>
            <span
              class="text-xs px-1.5 py-0.5 bg-yellow-900/50 text-yellow-400 rounded"
              title="Some content was redacted for privacy"
            >
              🔒 Redacted
            </span>
          <% end %>
        </div>
        <time class="text-xs text-gray-500" datetime={@message.original_timestamp}>
          <%= format_timestamp(@message.original_timestamp) %>
        </time>
      </div>
      <div class="mt-2 text-gray-300 whitespace-pre-wrap break-words">
        <%= format_content(@message.content) %>
      </div>
    </div>
    """
  end

  # Helpers

  defp role_emoji("user"), do: "👤"
  defp role_emoji("assistant"), do: "🤖"
  defp role_emoji("system"), do: "⚙️"
  defp role_emoji(_), do: "💬"

  defp role_display("user"), do: "splntrb"
  defp role_display("assistant"), do: "Stream"
  defp role_display("system"), do: "System"
  defp role_display(other), do: other

  defp role_styles("user"), do: "bg-blue-950/30 border-blue-800/50"
  defp role_styles("assistant"), do: "bg-purple-950/30 border-purple-800/50"
  defp role_styles("system"), do: "bg-gray-900 border-gray-700"
  defp role_styles(_), do: "bg-gray-900 border-gray-700"

  defp role_name_color("user"), do: "text-blue-400"
  defp role_name_color("assistant"), do: "text-purple-400"
  defp role_name_color("system"), do: "text-gray-400"
  defp role_name_color(_), do: "text-gray-400"

  defp format_timestamp(dt) do
    # Simple time format: 2:45 PM
    Calendar.strftime(dt, "%-I:%M %p")
  end

  defp format_date(dt) do
    # Full date for day separators: Saturday, February 1, 2026
    Calendar.strftime(dt, "%A, %B %-d, %Y")
  end

  defp same_day?(dt1, dt2) do
    Date.compare(DateTime.to_date(dt1), DateTime.to_date(dt2)) == :eq
  end

  defp format_content(content) when is_binary(content) do
    content
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> highlight_redactions()
    |> Phoenix.HTML.raw()
  end

  defp format_content(_), do: ""

  defp highlight_redactions(content) do
    Regex.replace(
      ~r/\[REDACTED[^\]]*\]/,
      content,
      "<span class=\"px-1 py-0.5 bg-red-900/50 text-red-400 rounded text-sm\">\\0</span>"
    )
  end
end
