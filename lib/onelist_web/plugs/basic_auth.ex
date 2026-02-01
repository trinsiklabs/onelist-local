defmodule OnelistWeb.Plugs.BasicAuth do
  @moduledoc """
  HTTP Basic Authentication plug for protected routes.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)

    case get_req_header(conn, "authorization") do
      ["Basic " <> encoded] ->
        case Base.decode64(encoded) do
          {:ok, credentials} ->
            if credentials == "#{username}:#{password}" do
              conn
            else
              unauthorized(conn)
            end

          :error ->
            unauthorized(conn)
        end

      _ ->
        unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", ~s(Basic realm="Restricted"))
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
