defmodule OnelistWeb.Plugs.Authenticate do
  @moduledoc """
  Plug for authenticating requests with session tokens.
  Ensures protected routes are only accessible to authenticated users.
  """

  import Plug.Conn
  import Phoenix.Controller
  use OnelistWeb, :verified_routes

  alias Onelist.Sessions

  @doc """
  Authenticate the user from session token.
  """
  def init(opts), do: opts

  def call(conn, _opts) do
    # Store connection info for login tracking
    # (IP address and user agent will be stored in process dictionary)
    store_connection_info(conn)

    # In test environment, check for bypass configuration
    if Application.get_env(:onelist, :env) == :test &&
         Application.get_env(:onelist, :bypass_auth) do
      # Get test user and session from configuration
      test_user = get_test_user()
      test_session = get_test_session()

      # If both are set, bypass authentication
      if test_user && test_session do
        conn
        |> assign(:current_user, test_user)
        |> assign(:current_session, test_session)
      else
        conn
        |> put_flash(:error, "Authentication required")
        |> redirect(to: ~p"/?login_required=true")
        |> halt()
      end
    else
      # Check for test environment
      test_env = Application.get_env(:onelist, :env) == :test
      test_user = get_session(conn, :current_user)

      # In test environment, use session user directly if available
      if test_env && test_user do
        conn
        |> assign(:current_user, test_user)
        |> assign(:current_session, %{user: test_user})
      else
        # Normal authentication flow
        # Get token from session
        with token when not is_nil(token) <- get_session(conn, :session_token),
             {:ok, session} <- Sessions.get_session_by_token(token),
             user when not is_nil(user) <- session.user,
             # Check if account is locked
             false <- is_account_locked?(user) do
          # Add user and session to conn
          conn
          |> assign(:current_user, user)
          |> assign(:current_session, session)
        else
          # Account is locked
          true ->
            log_authentication_failure({:error, :account_locked})

            conn
            |> clear_session()
            |> put_flash(:error, get_error_message({:error, :account_locked}))
            |> redirect(to: ~p"/?login_required=true")
            |> halt()

          error ->
            # Log failure reason without exposing sensitive info
            log_authentication_failure(error)

            # Redirect to login page with appropriate message
            conn
            |> clear_session()
            |> put_flash(:error, get_error_message(error))
            |> redirect(to: ~p"/?login_required=true")
            |> halt()
        end
      end
    end
  end

  # Helper functions to get test user and session
  defp get_test_user do
    Application.get_env(:onelist, :test_user)
  end

  defp get_test_session do
    Application.get_env(:onelist, :test_session)
  end

  # Store connection info for login tracking and rate limiting
  defp store_connection_info(conn) do
    # Extract IP address (handle both proxied and direct connections)
    ip_address = get_client_ip(conn)

    # Extract user agent
    user_agent = get_req_header(conn, "user-agent") |> List.first() || ""

    # Store in process dictionary for use in other modules
    Process.put(:current_ip_address, ip_address)
    Process.put(:current_user_agent, user_agent)
  end

  # Get client IP address, handling proxies correctly
  defp get_client_ip(conn) do
    forwarded = get_req_header(conn, "x-forwarded-for") |> List.first()

    cond do
      # If we have X-Forwarded-For, use the first IP (client IP)
      forwarded && String.contains?(forwarded, ",") ->
        forwarded |> String.split(",") |> List.first() |> String.trim()

      # Single IP in X-Forwarded-For
      forwarded ->
        String.trim(forwarded)

      # Fall back to the remote_ip from the socket
      true ->
        conn.remote_ip |> Tuple.to_list() |> Enum.join(".")
    end
  end

  # Log authentication failure without exposing sensitive information
  defp log_authentication_failure(error) do
    # Get IP and user agent from process dictionary
    ip = Process.get(:current_ip_address) || "unknown"

    # Log the failure but don't include sensitive details
    require Logger

    Logger.info(
      "Authentication failure: #{inspect(error)} from IP: #{Onelist.Security.anonymize_ip(ip)}"
    )
  end

  # Check if a user account is locked
  defp is_account_locked?(%{locked_at: nil}), do: false
  defp is_account_locked?(%{locked_at: _locked_at}), do: true
  defp is_account_locked?(_), do: false

  # Get user-friendly error message based on error type
  defp get_error_message(error) do
    case error do
      nil ->
        "You need to sign in to access this page."

      {:error, :expired_token} ->
        "Your session has expired. Please sign in again."

      {:error, :invalid_token} ->
        "You need to sign in to access this page."

      {:error, :account_locked} ->
        "Your account has been locked due to too many failed attempts. " <>
          "Please reset your password or contact support."

      _ ->
        "You must sign in to access this page."
    end
  end
end
