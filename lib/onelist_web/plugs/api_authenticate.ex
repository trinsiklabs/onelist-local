defmodule OnelistWeb.Plugs.ApiAuthenticate do
  @moduledoc """
  Plug for authenticating API requests via API keys.

  Extracts the API key from the `Authorization: Bearer <key>` header,
  validates it, and assigns the associated user and API key to the conn.

  Returns a 401 JSON error for invalid, revoked, or expired keys.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Onelist.ApiKeys
  alias Onelist.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_key} <- extract_api_key(conn),
         {:ok, api_key} <- ApiKeys.validate_api_key(raw_key) do
      # Load the associated user
      api_key = Repo.preload(api_key, :user)

      # Update last_used_at asynchronously (non-blocking)
      touch_api_key_async(api_key)

      conn
      |> assign(:current_user, api_key.user)
      |> assign(:current_api_key, api_key)
    else
      {:error, :missing_header} ->
        unauthorized(conn, "Missing Authorization header")

      {:error, :invalid_format} ->
        unauthorized(conn, "Invalid Authorization header format. Expected: Bearer <api_key>")

      {:error, :invalid_key} ->
        unauthorized(conn, "Invalid API key")

      {:error, :revoked} ->
        unauthorized(conn, "API key has been revoked")

      {:error, :expired} ->
        unauthorized(conn, "API key has expired")
    end
  end

  defp extract_api_key(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        {:error, :missing_header}

      [header | _] ->
        case String.split(header, " ", parts: 2) do
          ["Bearer", key] when byte_size(key) > 0 ->
            {:ok, String.trim(key)}

          _ ->
            {:error, :invalid_format}
        end
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_status(:unauthorized)
    |> put_resp_content_type("application/json")
    |> json(%{errors: %{detail: message}})
    |> halt()
  end

  # Update last_used_at in a separate process to avoid blocking the request.
  # In test environment, we allow the sandbox to manage the connection properly.
  defp touch_api_key_async(api_key) do
    if Application.get_env(:onelist, :sql_sandbox) do
      # In test mode, run synchronously to avoid sandbox issues
      ApiKeys.touch_api_key(api_key)
    else
      Task.Supervisor.start_child(
        Onelist.TaskSupervisor,
        fn -> ApiKeys.touch_api_key(api_key) end,
        restart: :transient
      )
    end

    :ok
  end
end
