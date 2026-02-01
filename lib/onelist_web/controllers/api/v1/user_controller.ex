defmodule OnelistWeb.Api.V1.UserController do
  use OnelistWeb, :controller

  @doc """
  GET /api/v1/me
  
  Returns the current authenticated user's info.
  Used by claude-onelist plugin to verify connection.
  """
  def me(conn, _params) do
    user = conn.assigns.current_user
    
    conn
    |> put_status(:ok)
    |> json(%{
      id: user.id,
      email: user.email,
      name: user.name,
      username: user.username,
      account_type: user.account_type,
      trusted_memory_mode: user.trusted_memory_mode
    })
  end
end
