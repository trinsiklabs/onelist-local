defmodule OnelistWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.
  """
  use OnelistWeb, :controller

  alias Onelist.Repo

  def index(conn, params) do
    case Map.get(params, "deep") do
      "true" -> deep_check(conn)
      _ -> basic_check(conn)
    end
  end

  defp basic_check(conn) do
    json(conn, %{status: "ok"})
  end

  defp deep_check(conn) do
    db_status = check_database()
    storage_status = check_storage()

    status =
      if db_status == "ok" and storage_status == "ok" do
        "ok"
      else
        "degraded"
      end

    response = %{
      status: status,
      database: db_status,
      storage: storage_status
    }

    if status == "ok" do
      json(conn, response)
    else
      conn
      |> put_status(503)
      |> json(response)
    end
  end

  defp check_database do
    case Repo.query("SELECT 1") do
      {:ok, _} -> "ok"
      {:error, _} -> "error"
    end
  rescue
    _ -> "error"
  end

  defp check_storage do
    # Basic storage check - just verify configuration exists
    case Application.get_env(:onelist, Onelist.Storage)[:primary_backend] do
      nil -> "not_configured"
      _ -> "ok"
    end
  rescue
    _ -> "error"
  end
end
