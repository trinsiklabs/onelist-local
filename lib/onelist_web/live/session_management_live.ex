defmodule OnelistWeb.SessionManagementLive do
  use OnelistWeb, :live_view

  alias Onelist.Sessions
  alias Onelist.Security

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_user do
      # Get current user and session
      user = socket.assigns.current_user

      # Get current session ID, handling both regular and test sessions
      current_session_id =
        case socket.assigns.current_session do
          # Regular session structure
          %{id: id} ->
            id

          _ when is_map(socket.assigns.current_session) ->
            # For test sessions that might not have an id field
            # Use the Application env if available, or a default value
            test_session = Application.get_env(:onelist, :test_session)

            if test_session && Map.has_key?(test_session, :id),
              do: test_session.id,
              else: "test-session-id"

          # Fallback
          _ ->
            nil
        end

      # Load all active sessions for the user
      active_sessions = Sessions.list_active_sessions(user)

      # Subscribe to session events for this user
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Onelist.PubSub, "sessions:#{user.id}")
      end

      # Sort sessions into current and others
      {current, others} = Enum.split_with(active_sessions, fn s -> s.id == current_session_id end)

      # Get inactivity timeout for display (convert seconds to hours)
      inactivity_hours = div(Sessions.get_inactivity_timeout(), 3600)

      {:ok,
       assign(socket,
         page_title: "Manage Your Sessions",
         current_session_id: current_session_id,
         current_session: List.first(current) || socket.assigns.current_session,
         other_sessions: others,
         sessions: active_sessions,
         inactivity_hours: inactivity_hours,
         loading: false,
         error: nil
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("revoke_session", %{"id" => session_id}, socket) do
    # Find the session to revoke
    session_to_revoke = Enum.find(socket.assigns.other_sessions, fn s -> s.id == session_id end)

    # Only revoke if it's not the current session
    if session_to_revoke && session_to_revoke.id != socket.assigns.current_session_id do
      case Sessions.revoke_session(session_to_revoke) do
        {:ok, _} ->
          # Remove the revoked session from the list
          updated_others =
            Enum.reject(socket.assigns.other_sessions, fn s -> s.id == session_id end)

          {:noreply,
           assign(socket,
             other_sessions: updated_others,
             sessions: [socket.assigns.current_session | updated_others]
           )}

        {:error, _reason} ->
          {:noreply, assign(socket, error: "Failed to revoke the session. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("revoke_all_other_sessions", _, socket) do
    user = socket.assigns.current_user

    # Ensure there are other sessions to revoke
    if Enum.count(socket.assigns.other_sessions) > 0 do
      case Sessions.revoke_all_sessions(user) do
        {_, _} ->
          # Current session will be reloaded via PubSub event
          # But update the UI immediately for better UX
          {:noreply,
           assign(socket,
             other_sessions: [],
             sessions: [socket.assigns.current_session]
           )}

        _ ->
          {:noreply, assign(socket, error: "Failed to revoke all sessions. Please try again.")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:session_revoked, session_id}, socket) do
    # If this is our current session, we'll be redirected by LiveAuth
    # Otherwise, just update the list
    if session_id != socket.assigns.current_session_id do
      updated_others = Enum.reject(socket.assigns.other_sessions, fn s -> s.id == session_id end)

      {:noreply,
       assign(socket,
         other_sessions: updated_others,
         sessions: [socket.assigns.current_session | updated_others]
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:all_sessions_revoked, user_id}, socket) do
    # If current_user's sessions were all revoked, LiveAuth will redirect us
    # This is just a fallback to update the UI immediately
    if user_id == socket.assigns.current_user.id do
      {:noreply,
       assign(socket,
         other_sessions: [],
         sessions: [socket.assigns.current_session]
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sessions-container">
      <h1>Manage Your Sessions</h1>

      <p class="sessions-info">
        You are currently signed in on <%= length(@sessions) %> <%= if length(@sessions) == 1,
          do: "device",
          else: "devices" %>.
        Sessions will automatically expire after <%= @inactivity_hours %> hours of inactivity.
      </p>

      <%= if length(@other_sessions) > 0 do %>
        <div class="actions">
          <button
            phx-click="revoke_all_other_sessions"
            data-confirm="Are you sure you want to sign out from all other devices?"
            class="btn btn-secondary"
            data-test-id="revoke-all-button"
          >
            Sign out from all other devices
          </button>
        </div>
      <% end %>

      <section class="sessions-list">
        <h2>Your Sessions</h2>
        <!-- Current Session -->
        <div
          class="session-card current"
          data-session-id={@current_session_id}
          data-test-id="session-card"
        >
          <div class="session-info">
            <div class="device">
              <span>
                <%= device_icon(@current_session.device_name) %> <%= @current_session.device_name %>
              </span>
              <span class="current-badge" data-test-id="current-session-badge">Current Session</span>
            </div>

            <div class="details">
              <div class="location">
                <span class="label">Location:</span>
                <span><%= @current_session.ip_address || "Unknown" %></span>
              </div>

              <div class="last-active">
                <span class="label">Last active:</span>
                <span><%= format_datetime(@current_session.last_active_at) %></span>
              </div>

              <div class="browser">
                <span class="label">Browser:</span>
                <span><%= extract_browser(@current_session.user_agent) %></span>
              </div>
            </div>
          </div>
        </div>
        <!-- Other Sessions -->
        <%= for session <- @other_sessions do %>
          <div class="session-card" data-session-id={session.id} data-test-id="session-card">
            <div class="session-info">
              <div class="device">
                <span><%= device_icon(session.device_name) %> <%= session.device_name %></span>
              </div>

              <div class="details">
                <div class="location">
                  <span class="label">Location:</span>
                  <span><%= session.ip_address || "Unknown" %></span>
                </div>

                <div class="last-active">
                  <span class="label">Last active:</span>
                  <span><%= format_datetime(session.last_active_at) %></span>
                </div>

                <div class="browser">
                  <span class="label">Browser:</span>
                  <span><%= extract_browser(session.user_agent) %></span>
                </div>
              </div>
            </div>

            <div class="actions">
              <button
                phx-click="revoke_session"
                phx-value-id={session.id}
                data-confirm="Are you sure you want to sign out this session?"
                class="btn btn-danger"
                data-test-id="revoke-session-button"
              >
                Sign Out
              </button>
            </div>
          </div>
        <% end %>
      </section>
    </div>
    """
  end

  # Helper function to get an icon for a device type
  defp device_icon(device_name) do
    cond do
      String.contains?(device_name, "iPhone") -> "📱"
      String.contains?(device_name, "iPad") -> "📱"
      String.contains?(device_name, "Android") -> "📱"
      String.contains?(device_name, "Windows") -> "💻"
      String.contains?(device_name, "Mac") -> "💻"
      String.contains?(device_name, "Linux") -> "💻"
      true -> "🖥️"
    end
  end

  # Helper function to format datetime
  defp format_datetime(datetime) do
    # Format as "Jan 1, 2023 at 12:34 PM"
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  # Helper to extract browser info
  defp extract_browser(user_agent) do
    Security.extract_browser(user_agent)
  end
end
