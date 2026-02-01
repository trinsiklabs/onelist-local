defmodule OnelistWeb.LiveAuth do
  @moduledoc """
  LiveView authentication hooks for handling authentication in LiveView contexts.
  """
  
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  
  # Import verified routes with proper endpoint configuration
  use OnelistWeb, :verified_routes
  
  alias Onelist.Sessions

  @doc """
  LiveView on_mount callback for authentication.

  ## Modes

  - `:ensure_authenticated` - Requires user to be logged in, redirects to login if not
  - `:ensure_admin` - Requires user to be admin, redirects to home if not
  - `:maybe_authenticated` - Loads user if logged in, but doesn't require it
  - `:redirect_if_authenticated` - Redirects to home if already logged in (for login/register pages)

  ## Examples

      # In router.ex
      live_session :authenticated, on_mount: {OnelistWeb.LiveAuth, :ensure_authenticated} do
        # Protected LiveView routes
      end
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    # Check if we're in test environment with bypass auth
    test_env = Application.get_env(:onelist, :env) == :test
    bypass_auth = Application.get_env(:onelist, :bypass_auth)

    # For tests with bypass_auth enabled, use Application config
    if test_env && bypass_auth do
      test_user = Application.get_env(:onelist, :test_user)
      test_session = Application.get_env(:onelist, :test_session)

      if test_user && test_session do
        socket =
          socket
          |> assign(:current_user, test_user)
          |> assign(:current_session, test_session)
          |> assign(:logged_in, true)

        {:cont, socket}
      else
        # No test user/session configured, redirect to login
        {:halt, redirect(socket, to: "/?login_required=true")}
      end
    else
      # Normal auth flow
      socket = assign_current_user(socket, session)
    
      if socket.assigns.current_user do
        # If authenticated, proceed with the LiveView
        {:cont, socket}
      else
        # If not authenticated, redirect to login page
        {:halt, redirect(socket, to: "/?login_required=true")}
      end
    end
  end

  def on_mount(:ensure_admin, _params, _session, socket) do
    user = socket.assigns.current_user
    
    if user && "admin" in (user.roles || []) do
      # If user is admin, proceed with the LiveView
      {:cont, socket}
    else
      # If not admin, redirect to home page
      socket = 
        socket
        |> put_flash(:error, "You must be an admin to access this page.")
        |> redirect(to: "/")
      
      {:halt, socket}
    end
  end

  def on_mount(:maybe_authenticated, _params, session, socket) do
    {:cont, assign_current_user(socket, session)}
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = assign_current_user(socket, session)
    
    if socket.assigns.current_user do
      # If already authenticated, redirect to home page
      {:halt, redirect(socket, to: "/")}
    else
      # If not authenticated, proceed with the login/register LiveView
      {:cont, socket}
    end
  end

  # Assigns current user and session to the socket based on session token.
  # Also sets up process dictionary for authentication tracking.
  defp assign_current_user(socket, %{"session_token" => token}) when is_binary(token) do
    # Set process dictionary for authentication tracking
    store_connection_info(socket)
    
    # Get session and user
    case Sessions.get_session_by_token(token) do
      {:ok, session} ->
        socket
        |> assign(:current_user, session.user)
        |> assign(:current_session, session)
        |> assign(:logged_in, true)
      
      _error ->
        assign_default_values(socket)
    end
  end
  
  defp assign_current_user(socket, _session) do
    # Set process dictionary for authentication tracking even if no session
    store_connection_info(socket)
    
    assign_default_values(socket)
  end
  
  defp assign_default_values(socket) do
    socket
    |> assign(:current_user, nil)
    |> assign(:current_session, nil)
    |> assign(:logged_in, false)
  end

  # Stores connection info in process dictionary for authentication tracking.
  defp store_connection_info(socket) do
    if connected?(socket) do
      # Extract IP - this depends on your setup, adjust as needed
      # This assumes you're using :peer_data in your socket assigns
      ip_address = get_client_ip(socket)
      
      # Extract user agent - this depends on your setup, adjust as needed
      user_agent = get_user_agent(socket)
      
      # Store in process dictionary for use in other modules
      Process.put(:current_ip_address, ip_address)
      Process.put(:current_user_agent, user_agent)
    end
  end
  
  # Extract client IP - adjust based on your Socket setup
  defp get_client_ip(socket) do
    socket.assigns[:ip_address] || 
    (socket.assigns[:peer_data] && socket.assigns[:peer_data].address |> Tuple.to_list() |> Enum.join(".")) || 
    "unknown"
  end
  
  # Extract user agent - adjust based on your Socket setup
  defp get_user_agent(socket) do
    socket.assigns[:user_agent] || "unknown"
  end
  
  @doc """
  Handles PubSub events related to session state.
  
  ## Examples
  
      # In your LiveView
      def mount(_params, session, socket) do
        # ... other mount logic ...
        # Assuming socket has current_user assigned
        current_user_id = socket.assigns[:current_user] && socket.assigns[:current_user].id
        if connected?(socket) && current_user_id do
          Phoenix.PubSub.subscribe(Onelist.PubSub, "sessions:\#{current_user_id}")
        end
        {:ok, socket}
      end
  
      # Forward all session-related messages to LiveAuth
      def handle_info({:session_revoked, _} = msg, socket) do
        OnelistWeb.LiveAuth.handle_session_event(msg, socket)
      end
  """
  def handle_session_event(msg, socket) do
    case msg do
      {:session_revoked, session_id} ->
        # If current session was revoked, redirect to login
        if socket.assigns.current_session && socket.assigns.current_session.id == session_id do
          {:noreply, redirect(socket, to: "/?session_expired=true")}
        else
          {:noreply, socket}
        end
      
      {:all_sessions_revoked, user_id} ->
        # If all sessions for current user were revoked, redirect to login
        if socket.assigns.current_user && socket.assigns.current_user.id == user_id do
          {:noreply, redirect(socket, to: "/?session_expired=true")}
        else
          {:noreply, socket}
        end
      
      {:session_refreshed, _} ->
        # Session was refreshed, no action needed
        {:noreply, socket}
        
      {:session_created, _} ->
        # New session was created, no action needed
        {:noreply, socket}
        
      _ ->
        # Unknown message type, just pass through
        {:noreply, socket}
    end
  end
end 