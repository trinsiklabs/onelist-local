defmodule OnelistWeb.Api.SessionController do
  use OnelistWeb, :controller

  @doc """
  Handles session ping requests to extend session lifetime.
  """
  def ping(conn, _params) do
    # The session token is already validated by the authentication plug
    # Just return a success response - the mere act of making this request
    # will refresh the session's last_active_at timestamp
    json(conn, %{success: true})
  end
end
