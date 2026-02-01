defmodule Onelist.ChatLogs do
  @moduledoc """
  Real-time chat log management.
  
  Handles streaming messages from OpenClaw agents into Onelist entries.
  Each session becomes a single chat_log entry that grows over time.
  """

  import Ecto.Query
  alias Onelist.{Repo, Entries}
  alias Onelist.Entries.{Entry, Representation}
  alias Onelist.Reader.Workers.ProcessEntryWorker

  @doc """
  Append a message to a session's chat log.
  
  Creates the entry if it doesn't exist, otherwise appends to existing.
  Queues memory extraction after debounce period.
  """
  def append_message(user, session_id, message) do
    Repo.transaction(fn ->
      # Find or create the chat log entry for this session
      entry = get_or_create_session_entry(user, session_id)
      
      # Parse existing messages
      existing_content = get_entry_content(entry)
      
      # Append new message
      message_id = generate_message_id()
      timestamped_message = Map.put(message, "id", message_id)
      new_content = existing_content <> Jason.encode!(timestamped_message) <> "\n"
      
      message_count = (entry.metadata["message_count"] || 0) + 1
      
      # Update the representation directly (bypassing trusted memory check)
      representation = get_or_create_representation(entry)
      {:ok, _} = representation
        |> Representation.changeset(%{content: new_content})
        |> Repo.update()
      
      # Update entry metadata
      {:ok, updated} = entry
        |> Entry.update_changeset(%{
          metadata: Map.merge(entry.metadata || %{}, %{
            "message_count" => message_count,
            "last_message_at" => message["timestamp"] || DateTime.utc_now() |> DateTime.to_iso8601(),
            "last_role" => message["role"]
          })
        })
        |> Repo.update()
      
      # Queue memory extraction (debounced - only if no recent job)
      maybe_queue_extraction(updated, message_count)
      
      %{
        message_id: message_id,
        entry_id: updated.id,
        message_count: message_count
      }
    end)
  end
  
  defp get_or_create_representation(entry) do
    # Handle both preloaded and not-preloaded cases
    case entry.representations do
      %Ecto.Association.NotLoaded{} ->
        # Not preloaded - query for it or create
        case Repo.one(from r in Representation, where: r.entry_id == ^entry.id, limit: 1) do
          nil -> create_representation(entry)
          rep -> rep
        end
      [rep | _] -> rep
      [] -> create_representation(entry)
    end
  end
  
  defp create_representation(entry) do
    {:ok, rep} = %Representation{entry_id: entry.id}
      |> Representation.changeset(%{
        mime_type: "application/jsonl",
        content: "",
        type: "chat_log"
      })
      |> Repo.insert()
    rep
  end

  @doc """
  Get recent messages across all sessions within a time window.
  
  Returns messages from the last N hours, up to the specified limit.
  Messages are ordered by timestamp, most recent first.
  """
  def get_recent_messages_by_time(user, hours, limit \\ 100) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)
    cutoff_iso = DateTime.to_iso8601(cutoff)
    
    # Get all chat_log entries for this user
    entries = 
      Entry
      |> where([e], e.user_id == ^user.id)
      |> where([e], e.entry_type == "chat_log")
      |> preload(:representations)
      |> Repo.all()
    
    # Extract and filter messages across all sessions
    messages = 
      entries
      |> Enum.flat_map(fn entry ->
        session_id = entry.metadata["session_id"]
        
        entry
        |> get_entry_content()
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          case Jason.decode(line) do
            {:ok, msg} -> Map.put(msg, "session_id", session_id)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      end)
      |> Enum.filter(fn msg ->
        case msg["timestamp"] do
          nil -> false
          ts when is_binary(ts) -> ts >= cutoff_iso
          _ -> false
        end
      end)
      |> Enum.sort_by(fn msg -> msg["timestamp"] end, :desc)
      |> Enum.take(limit)
    
    {:ok, messages}
  end

  @doc """
  Get recent messages from a session.
  """
  def get_recent_messages(user, session_id, limit \\ 50) do
    case get_session_entry(user, session_id) do
      nil -> {:error, :not_found}
      entry ->
        content = get_entry_content(entry)
        messages = 
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
          |> Enum.take(-limit)
        {:ok, messages}
    end
  end

  @doc """
  List all chat log sessions for a user.
  """
  def list_sessions(user, limit \\ 20) do
    sessions = 
      Entry
      |> where([e], e.user_id == ^user.id)
      |> where([e], e.entry_type == "chat_log")
      |> order_by([e], desc: e.inserted_at)
      |> limit(^limit)
      |> Repo.all()
      |> Enum.map(fn entry ->
        %{
          session_id: entry.metadata["session_id"],
          entry_id: entry.id,
          title: entry.title,
          message_count: entry.metadata["message_count"] || 0,
          status: entry.metadata["status"] || "active",
          started_at: entry.metadata["started_at"],
          last_message_at: entry.metadata["last_message_at"],
          inserted_at: entry.inserted_at
        }
      end)
    
    {:ok, sessions}
  end

  @doc """
  Close a session and trigger final memory extraction.
  """
  def close_session(user, session_id) do
    case get_session_entry(user, session_id) do
      nil -> {:error, :not_found}
      entry ->
        # Update metadata to mark as closed
        {:ok, updated} = Entries.update_entry(entry, %{
          metadata: Map.merge(entry.metadata || %{}, %{
            "status" => "closed",
            "closed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })
        })
        
        # Queue final memory extraction
        %{entry_id: updated.id}
        |> ProcessEntryWorker.new()
        |> Oban.insert()
        
        {:ok, updated}
    end
  end

  # Private functions

  defp get_or_create_session_entry(user, session_id) do
    case get_session_entry(user, session_id) do
      nil -> create_session_entry(user, session_id)
      entry -> entry
    end
  end

  defp get_session_entry(user, session_id) do
    Entry
    |> where([e], e.user_id == ^user.id)
    |> where([e], e.entry_type == "chat_log")
    |> where([e], fragment("metadata->>'session_id' = ?", ^session_id))
    |> preload(:representations)
    |> Repo.one()
  end

  defp create_session_entry(user, session_id) do
    today = Date.utc_today() |> Date.to_iso8601()
    
    {:ok, entry} = Entries.create_entry(user, %{
      title: "Chat Session: #{today}",
      entry_type: "chat_log",
      source_type: "openclaw",
      metadata: %{
        "session_id" => session_id,
        "started_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "message_count" => 0,
        "status" => "active"
      },
      representations: [%{
        mime_type: "application/jsonl",
        content: ""
      }]
    })
    
    entry
  end

  defp get_entry_content(entry) do
    case entry.representations do
      [%{content: content} | _] when is_binary(content) -> content
      _ -> ""
    end
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp maybe_queue_extraction(entry, message_count) do
    # Queue extraction every 10 messages, or if explicitly requested
    if rem(message_count, 10) == 0 do
      %{entry_id: entry.id, mode: "incremental"}
      |> ProcessEntryWorker.new(schedule_in: 30)  # 30 second debounce
      |> Oban.insert()
    end
    :ok
  end
end
