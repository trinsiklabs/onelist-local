defmodule OnelistWeb.Components.SessionTimeoutComponent do
  use OnelistWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       # Default timeout: 30 minutes (1800 seconds)
       timeout_seconds:
         Application.get_env(:onelist, Onelist.Sessions)[:user_session_timeout] || 1800,
       # Show warning 2 minutes before expiry
       warning_seconds: Application.get_env(:onelist, Onelist.Sessions)[:warning_seconds] || 120
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="session-timeout-container"
      phx-hook="SessionTimeout"
      data-timeout-seconds={@timeout_seconds}
      data-warning-seconds={@warning_seconds}
    >
      <div class="session-timeout-modal" data-test-id="session-timeout-modal" style="display: none;">
        <div class="modal-content">
          <h3>Your session is about to expire</h3>
          <p>
            Due to inactivity, your session will expire in <span id="timeout-countdown">0</span>
            seconds.
          </p>

          <div class="modal-actions">
            <button
              phx-click="extend_session"
              phx-target={@myself}
              class="btn btn-primary"
              data-test-id="extend-session-button"
            >
              Keep me signed in
            </button>
            <button
              phx-click="logout"
              phx-target={@myself}
              class="btn btn-secondary"
              data-test-id="logout-button"
            >
              Log out now
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("extend_session", _params, socket) do
    # Extend the session by making a request that will reset the session timer
    {:noreply, push_event(socket, "session-extended", %{})}
  end

  @impl true
  def handle_event("logout", _params, socket) do
    # Redirect to logout
    {:noreply, redirect(socket, to: ~p"/logout")}
  end
end
