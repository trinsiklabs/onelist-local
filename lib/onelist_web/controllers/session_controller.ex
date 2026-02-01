defmodule OnelistWeb.SessionController do
  use OnelistWeb, :controller
  
  alias Onelist.Accounts
  alias Onelist.Sessions
  
  @doc """
  Handles user login.
  
  This action processes the login form submission, authenticates the user,
  and creates a session if successful.
  """
  def create(conn, %{"user" => %{"email" => email, "password" => password, "remember_me" => remember_me}}) do
    # Extract and store connection info (needed by Accounts context for tracking)
    {ip_address, user_agent} = extract_connection_info(conn)
    store_connection_info(ip_address, user_agent)

    # Attempt to authenticate the user
    case Accounts.get_user_by_email_and_password(email, password) do
      {:ok, user} ->
        # Create a new session
        create_session_for_user(conn, user, %{
          "ip_address" => ip_address,
          "user_agent" => user_agent,
          "context" => "web",
          "remember_me" => remember_me == "true"
        })
        
      {:error, {:rate_limited, timeout}} ->
        # Rate limited - inform the user
        conn
        |> put_flash(:error, "Too many login attempts. Please try again in #{div(timeout, 60)} minutes.")
        |> redirect(to: ~p"/login?rate_limited=true")
        
      {:error, :account_locked} ->
        # Account is locked - direct user to reset password
        conn
        |> put_flash(:error, "Your account has been locked due to too many failed attempts. Please reset your password to unlock your account.")
        |> redirect(to: ~p"/forgot-password?account_locked=true")
        
      {:error, :invalid_credentials} ->
        # Invalid credentials - generic error message
        conn
        |> put_flash(:error, "Invalid email or password")
        |> redirect(to: ~p"/login")
    end
  end
  
  # Handle case where remember_me isn't present
  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    create(conn, %{"user" => %{"email" => email, "password" => password, "remember_me" => "false"}})
  end
  
  # Handle case where params don't match expected format
  def create(conn, _params) do
    conn
    |> put_flash(:error, "Invalid login attempt")
    |> redirect(to: ~p"/login")
  end
  
  @doc """
  Logs out the user by invalidating the current session.
  """
  def delete(conn, _params) do
    # Try to revoke the session - first check assigns, then try token from session
    cond do
      session = conn.assigns[:current_session] ->
        # Revoke session from assigns
        Sessions.revoke_session(session)

      token = get_session(conn, :session_token) ->
        # Get and revoke session by token
        case Sessions.get_session_by_token(token) do
          {:ok, session} -> Sessions.revoke_session(session)
          _ -> :ok
        end

      true ->
        :ok
    end

    # Clear the session and redirect to the homepage
    conn
    |> clear_session()
    |> put_flash(:info, "You have been logged out")
    |> redirect(to: ~p"/")
  end
  
  # Store connection info in Process dictionary for Accounts context tracking
  # TODO: Refactor Accounts context to accept ip/user_agent as explicit params
  defp store_connection_info(ip_address, user_agent) do
    Process.put(:current_ip_address, ip_address)
    Process.put(:current_user_agent, user_agent)
  end

  # Extract connection info (IP address and user agent)
  defp extract_connection_info(conn) do
    ip_address = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
    user_agent = get_req_header(conn, "user-agent") |> List.first() || ""

    # Check for X-Forwarded-For header (for proxied requests)
    ip_address = case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] when is_binary(forwarded) ->
        # Take the first IP if there are multiple
        if String.contains?(forwarded, ",") do
          forwarded |> String.split(",") |> List.first() |> String.trim()
        else
          String.trim(forwarded)
        end
      _ -> ip_address
    end

    {ip_address, user_agent}
  end

  # Create a session for the authenticated user
  defp create_session_for_user(conn, user, %{"ip_address" => ip_address, "user_agent" => user_agent, "context" => context, "remember_me" => remember_me}) do
    # Determine session expiry based on remember_me
    expiry = if remember_me do
      # Longer expiry for remember_me (e.g., 30 days)
      60 * 60 * 24 * 30
    else
      # Shorter expiry for regular session (e.g., 24 hours)
      60 * 60 * 24
    end

    # Create session
    {:ok, %{session: _session, token: token}} = Sessions.create_session(user, %{
      "ip_address" => ip_address,
      "user_agent" => user_agent,
      "context" => context
    })
    
    # Store token in session
    conn
    |> put_session(:session_token, token)
    |> configure_session(renew: true, max_age: expiry)
    |> put_flash(:info, "Welcome back!")
    |> redirect(to: ~p"/app/entries")
  end
end 