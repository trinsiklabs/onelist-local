defmodule OnelistWeb.Api.V1.ChatStreamController do
  @moduledoc """
  Real-time chat log streaming endpoint.

  Receives individual messages from OpenClaw agents and:
  1. Appends to the session's chat log entry
  2. Queues background memory extraction
  3. Publishes to Livelog (after redaction)
  """
  use OnelistWeb, :controller

  alias Onelist.ChatLogs
  alias Onelist.Livelog.Publisher
  alias Onelist.Repo

  action_fallback OnelistWeb.FallbackController

  @doc """
  Append a message to a chat session.

  POST /api/v1/chat-stream/append

  Body:
  {
    "session_id": "abc-123",
    "message": {
      "role": "user",
      "content": "...",
      "timestamp": "2026-01-30T23:15:00Z"
    }
  }

  Response:
  { "ok": true, "message_id": "xyz-789" }
  """
  def append(conn, %{"session_id" => session_id, "message" => message}) do
    user = conn.assigns.current_user

    case ChatLogs.append_message(user, session_id, message) do
      {:ok, result} ->
        # Async publish to Livelog (don't block the API response)
        # Only publish if this is Stream's user account
        if user.id == "deba7211-889d-4381-afcc-2dca0c56b17b" do
          Task.start(fn ->
            Publisher.process_and_publish(
              message,
              result.entry_id,
              result.message_id
            )
          end)
        end

        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          message_id: result.message_id,
          entry_id: result.entry_id,
          message_count: result.message_count
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end

  @doc """
  Get recent messages from a chat session.

  GET /api/v1/chat-stream?session_id=abc&last=50
  """
  def index(conn, %{"session_id" => session_id} = params) do
    user = conn.assigns.current_user
    limit = Map.get(params, "last", "50") |> String.to_integer() |> min(500)

    case ChatLogs.get_recent_messages(user, session_id, limit) do
      {:ok, messages} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          session_id: session_id,
          messages: messages,
          count: length(messages)
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "Session not found"})
    end
  end

  @doc """
  List all chat log sessions for the current user.

  GET /api/v1/chat-logs
  """
  def list_logs(conn, params) do
    user = conn.assigns.current_user
    limit = Map.get(params, "limit", "20") |> String.to_integer() |> min(100)

    case ChatLogs.list_sessions(user, limit) do
      {:ok, sessions} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          sessions: sessions,
          count: length(sessions)
        })
    end
  end

  @doc """
  Get recent messages across all sessions within a time window.

  GET /api/v1/chat-stream/recent?hours=N&limit=M

  Query params:
  - hours: Number of hours to look back (default: 24, max: 168)
  - limit: Maximum messages to return (default: 100, max: 1000)

  Response:
  { 
    "ok": true, 
    "messages": [...], 
    "count": N,
    "hours": N 
  }
  """
  def recent(conn, params) do
    user = conn.assigns.current_user
    hours = Map.get(params, "hours", "24") |> String.to_integer() |> min(168) |> max(1)
    limit = Map.get(params, "limit", "100") |> String.to_integer() |> min(1000) |> max(1)

    case ChatLogs.get_recent_messages_by_time(user, hours, limit) do
      {:ok, messages} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          messages: messages,
          count: length(messages),
          hours: hours
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end

  @doc """
  Close a chat session (marks it as complete, triggers final processing).

  POST /api/v1/chat-stream/close
  """
  def close(conn, %{"session_id" => session_id}) do
    user = conn.assigns.current_user

    case ChatLogs.close_session(user, session_id) do
      {:ok, entry} ->
        conn
        |> put_status(:ok)
        |> json(%{
          ok: true,
          entry_id: entry.id,
          message_count: entry.metadata["message_count"]
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: inspect(reason)})
    end
  end
end
