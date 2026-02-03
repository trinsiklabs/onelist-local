defmodule OnelistWeb.UserSessionController do
  use OnelistWeb, :controller

  alias Onelist.SessionManagement

  @doc """
  Lists all active sessions for the current user.
  """
  def index(conn, _params) do
    user = conn.assigns.current_user
    current_session_id = conn.assigns.current_session.id

    # Use context function for business logic
    session_data = SessionManagement.get_session_management_data(user, current_session_id)

    render(conn, :index, session_data)
  end

  @doc """
  Revokes a specific session.
  """
  def delete(conn, %{"id" => session_id}) do
    user = conn.assigns.current_user
    current_session_id = conn.assigns.current_session.id

    cond do
      # Trying to revoke current session
      session_id == current_session_id ->
        # Redirect to logout which will handle revoking the current session
        redirect(conn, to: ~p"/logout")

      # Revoke the session if it belongs to the current user
      true ->
        # Use context function for business logic with ownership check
        case SessionManagement.revoke_user_session(user, session_id) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Session has been signed out")
            |> redirect(to: ~p"/app/sessions")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Session not found")
            |> redirect(to: ~p"/app/sessions")

          {:error, :unauthorized} ->
            conn
            |> put_flash(:error, "Session not found")
            |> redirect(to: ~p"/app/sessions")
        end
    end
  end

  @doc """
  Revokes all sessions except the current one.
  """
  def delete_all(conn, _params) do
    user = conn.assigns.current_user
    current_session_id = conn.assigns.current_session.id

    # Use context function for business logic
    {:ok, count} = SessionManagement.revoke_other_sessions(user, current_session_id)

    conn
    |> put_flash(:info, "#{count} sessions have been signed out")
    |> redirect(to: ~p"/app/sessions")
  end
end
