defmodule OnelistWeb.Api.V1.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.

  See `Phoenix.Controller.action_fallback/1` for more details.
  """
  use OnelistWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :version_not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :no_snapshot_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("401.json")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("403.json")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("422.json", changeset: changeset)
  end

  def call(conn, {:error, :bad_request, message}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("400.json", message: message)
  end

  def call(conn, {:error, :unprocessable_entity, message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("422.json", message: message)
  end

  def call(conn, {:error, :missing_file}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("400.json", message: "No file uploaded")
  end

  def call(conn, {:error, {:file_read_error, _reason}}) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: OnelistWeb.ErrorJSON)
    |> render("400.json", message: "Failed to read uploaded file")
  end
end
