defmodule OnelistWeb.Api.V1.OpenClawImportController do
  @moduledoc """
  API endpoints for importing OpenClaw session transcripts.

  ## Endpoints

  - `POST /api/v1/openclaw/import` - Start a directory import
  - `GET /api/v1/openclaw/import/preview` - Preview what would be imported
  - `POST /api/v1/openclaw/import/file` - Import a single file

  ## Authentication

  All endpoints require a valid API key with appropriate permissions.
  """

  use OnelistWeb, :controller

  alias Onelist.OpenClaw.SessionImporter
  alias Onelist.OpenClaw.Workers.ImportSessionWorker

  action_fallback OnelistWeb.FallbackController

  @doc """
  Start importing sessions from a directory.

  POST /api/v1/openclaw/import

  Body:
  {
    "path": "~/.openclaw",
    "options": {
      "agent_id": "main",        // optional: filter to agent
      "after": "2026-01-01",     // optional: only after date
      "before": "2026-02-01",    // optional: only before date
      "async": true              // optional: use background jobs (default: true)
    }
  }

  Response:
  {
    "ok": true,
    "queued": 42,
    "message": "Import started"
  }
  """
  def create(conn, %{"path" => path} = params) do
    user = conn.assigns.current_user
    opts = build_import_opts(params["options"] || %{})
    async = get_in(params, ["options", "async"]) != false

    if async do
      case ImportSessionWorker.queue_directory_import(user, path, opts) do
        {:ok, result} ->
          conn
          |> put_status(:accepted)
          |> json(%{
            ok: true,
            queued: result.queued,
            total: result.total,
            message: "Import jobs queued. Sessions will be processed sequentially."
          })

        {:error, :directory_not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{ok: false, error: "Directory not found: #{path}"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{ok: false, error: inspect(reason)})
      end
    else
      # Synchronous import (for small imports or testing)
      case SessionImporter.import_directory(user, path, opts) do
        {:ok, result} ->
          conn
          |> put_status(:ok)
          |> json(%{
            ok: true,
            imported: result.imported_count,
            failed: result.failed_count,
            total: result.total
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{ok: false, error: inspect(reason)})
      end
    end
  end

  @doc """
  Preview what would be imported (dry run).

  GET /api/v1/openclaw/import/preview?path=~/.openclaw

  Query params:
  - path: Directory to scan (required)
  - agent_id: Filter to specific agent (optional)
  - after: Only sessions after this date (optional)
  - before: Only sessions before this date (optional)

  Response:
  {
    "ok": true,
    "sessions": [
      {
        "path": "/path/to/session.jsonl",
        "agent_id": "main",
        "session_id": "telegram-12345",
        "earliest_timestamp": "2026-01-30T08:00:00Z",
        "message_count": 42
      }
    ],
    "total": 1
  }
  """
  def preview(conn, %{"path" => path} = params) do
    opts = build_import_opts(params)

    case SessionImporter.list_sessions(path, opts) do
      {:ok, sessions} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          sessions: sessions,
          total: length(sessions)
        })

      {:error, :directory_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Directory not found: #{path}"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end

  @doc """
  Import a single session file.

  POST /api/v1/openclaw/import/file

  Body:
  {
    "path": "/path/to/session.jsonl"
  }

  Response:
  {
    "ok": true,
    "entry_id": "uuid",
    "message_count": 42,
    "session_id": "openclaw:main:telegram-12345"
  }
  """
  def import_file(conn, %{"path" => path}) do
    user = conn.assigns.current_user

    case SessionImporter.import_session_file(user, path) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          entry_id: result.entry_id,
          message_count: result.message_count,
          session_id: result[:session_id],
          already_existed: result[:already_existed] || false
        })

      {:error, :file_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "File not found: #{path}"})

      {:error, :invalid_path_format} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: "Invalid OpenClaw session path format"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end

  # Private functions

  defp build_import_opts(params) when is_map(params) do
    []
    |> maybe_add_agent_id(params["agent_id"])
    |> maybe_add_after(params["after"])
    |> maybe_add_before(params["before"])
  end

  defp maybe_add_agent_id(opts, nil), do: opts
  defp maybe_add_agent_id(opts, agent_id), do: Keyword.put(opts, :agent_id, agent_id)

  defp maybe_add_after(opts, nil), do: opts

  defp maybe_add_after(opts, date_str) do
    case parse_datetime(date_str) do
      {:ok, dt} -> Keyword.put(opts, :after, dt)
      _ -> opts
    end
  end

  defp maybe_add_before(opts, nil), do: opts

  defp maybe_add_before(opts, date_str) do
    case parse_datetime(date_str) do
      {:ok, dt} -> Keyword.put(opts, :before, dt)
      _ -> opts
    end
  end

  defp parse_datetime(str) when is_binary(str) do
    # Try ISO8601 first
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} ->
        {:ok, dt}

      _ ->
        # Try date-only format
        case Date.from_iso8601(str) do
          {:ok, date} ->
            {:ok, DateTime.new!(date, ~T[00:00:00], "Etc/UTC")}

          _ ->
            {:error, :invalid_format}
        end
    end
  end
end
