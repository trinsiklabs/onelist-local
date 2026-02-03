defmodule OnelistWeb.App.RiverLive do
  @moduledoc """
  River chat interface.

  Talk to River, the AI soul of Onelist.
  """

  use OnelistWeb, :live_view

  alias Onelist.River.{Agent, Sessions}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get or create session
    {:ok, session} = Sessions.get_or_create_session(user)

    # Load conversation history
    messages = Sessions.get_history(session, limit: 50)

    {:ok,
     socket
     |> assign(:session, session)
     |> assign(:messages, messages)
     |> assign(:input, "")
     |> assign(:loading, false)
     |> assign(:gtd_state, get_gtd_state(user))}
  end

  @impl true
  def handle_event("send", %{"message" => message}, socket) when message != "" do
    user = socket.assigns.current_user

    # Add user message to UI immediately
    user_msg = %{role: "user", content: message, inserted_at: DateTime.utc_now()}
    messages = socket.assigns.messages ++ [user_msg]

    # Start async River response
    socket =
      socket
      |> assign(:messages, messages)
      |> assign(:input, "")
      |> assign(:loading, true)

    # Call River in background
    send(self(), {:call_river, message})

    {:noreply, socket}
  end

  def handle_event("send", _, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input, value)}
  end

  @impl true
  def handle_info({:call_river, message}, socket) do
    user = socket.assigns.current_user

    case Agent.chat(user, message) do
      {:ok, response} ->
        # Add River's response
        river_msg = %{role: "river", content: response.message, inserted_at: DateTime.utc_now()}
        messages = socket.assigns.messages ++ [river_msg]

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)
         |> assign(:gtd_state, response.gtd_state)}

      {:error, reason} ->
        # Show error
        error_msg = %{
          role: "error",
          content: "Sorry, something went wrong: #{inspect(reason)}",
          inserted_at: DateTime.utc_now()
        }

        messages = socket.assigns.messages ++ [error_msg]

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)}
    end
  end

  defp get_gtd_state(user) do
    Agent.build_context(user, "", []).gtd_state
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="river-chat h-full flex flex-col bg-gray-900">
      <!-- Header -->
      <div class="river-header px-6 py-4 border-b border-gray-800 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-cyan-400 flex items-center justify-center">
            <span class="text-xl">🌊</span>
          </div>
          <div>
            <h1 class="text-xl font-semibold text-white">River</h1>
            <p class="text-sm text-gray-400">Your memory, together</p>
          </div>
        </div>
        <!-- GTD State -->
        <div class="flex items-center gap-4 text-sm">
          <div class="text-gray-400">
            <span class="text-orange-400 font-medium"><%= @gtd_state.inbox_count %></span> inbox
          </div>
          <div class="text-gray-400">
            <span class="text-blue-400 font-medium"><%= @gtd_state.active_projects %></span> projects
          </div>
        </div>
      </div>
      <!-- Messages -->
      <div class="flex-1 overflow-y-auto px-6 py-4 space-y-4" id="messages" phx-hook="ScrollToBottom">
        <%= if Enum.empty?(@messages) do %>
          <div class="text-center py-12">
            <div class="text-6xl mb-4">🌊</div>
            <h2 class="text-xl text-gray-300 mb-2">Welcome to River</h2>
            <p class="text-gray-500 max-w-md mx-auto">
              I'm the part of your mind that never forgets.
              Ask me about your memories, tasks, or just capture a new thought.
            </p>
          </div>
        <% else %>
          <%= for msg <- @messages do %>
            <div class={"message flex #{if msg.role == "user", do: "justify-end", else: "justify-start"}"}>
              <div class={"max-w-[80%] rounded-2xl px-4 py-3 #{message_style(msg.role)}"}>
                <p class="text-sm whitespace-pre-wrap"><%= msg.content %></p>
              </div>
            </div>
          <% end %>

          <%= if @loading do %>
            <div class="message flex justify-start">
              <div class="bg-gray-800 rounded-2xl px-4 py-3">
                <div class="flex items-center gap-2 text-gray-400">
                  <div class="animate-pulse">●</div>
                  <div class="animate-pulse animation-delay-200">●</div>
                  <div class="animate-pulse animation-delay-400">●</div>
                </div>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
      <!-- Input -->
      <div class="river-input px-6 py-4 border-t border-gray-800">
        <form phx-submit="send" class="flex gap-3">
          <input
            type="text"
            name="message"
            value={@input}
            phx-change="update_input"
            placeholder="Ask River anything..."
            class="flex-1 bg-gray-800 text-white rounded-full px-5 py-3 focus:outline-none focus:ring-2 focus:ring-blue-500"
            autocomplete="off"
            disabled={@loading}
          />
          <button
            type="submit"
            class="bg-blue-500 hover:bg-blue-600 text-white rounded-full px-6 py-3 font-medium transition disabled:opacity-50"
            disabled={@loading || @input == ""}
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  defp message_style("user"), do: "bg-blue-600 text-white"
  defp message_style("river"), do: "bg-gray-800 text-gray-100"
  defp message_style("error"), do: "bg-red-900 text-red-200"
  defp message_style(_), do: "bg-gray-800 text-gray-100"
end
