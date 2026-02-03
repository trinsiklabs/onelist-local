defmodule Onelist.Livelog.Publisher do
  @moduledoc """
  Publishes redacted messages to Livelog subscribers via Phoenix PubSub.

  Flow:
  1. Receives raw message from ChatStreamController
  2. Runs through Redaction engine
  3. If blocked → logs to audit only
  4. If OK → saves to DB + broadcasts to LiveView subscribers
  """

  alias Onelist.Livelog.{Redaction, Message, AuditLog}
  alias Onelist.Repo
  alias Phoenix.PubSub

  require Logger

  @pubsub Onelist.PubSub
  @topic "livelog:stream"

  @doc """
  Process a new message from ChatLogs and publish if appropriate.
  Called after ChatStreamController.append succeeds.

  Returns:
  - `{:ok, message}` - Message published successfully
  - `{:ok, :blocked}` - Message blocked (audit logged)
  - `{:error, reason}` - Processing failed
  """
  def process_and_publish(raw_message, entry_id, message_id) do
    start_time = System.monotonic_time(:microsecond)
    content = raw_message["content"]

    case Redaction.redact(content) do
      {:blocked, reason} ->
        log_blocked(raw_message, reason, entry_id, message_id, start_time)
        {:ok, :blocked}

      {:ok, redacted_content} ->
        case save_and_broadcast(raw_message, redacted_content, entry_id, message_id, start_time) do
          {:ok, message} -> {:ok, message}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Subscribe to the Livelog stream topic.
  Called by LiveView on mount.
  """
  def subscribe do
    PubSub.subscribe(@pubsub, @topic)
  end

  @doc """
  Broadcast a message to all subscribers.
  Used internally and can be used for testing.
  """
  def broadcast(message) do
    PubSub.broadcast(@pubsub, @topic, {:new_message, message})
  end

  # ============================================================================
  # PRIVATE
  # ============================================================================

  defp save_and_broadcast(raw_message, redacted_content, entry_id, message_id, start_time) do
    processing_time = System.monotonic_time(:microsecond) - start_time
    original_content = raw_message["content"]

    # Determine what patterns matched
    patterns = Redaction.get_matched_patterns(original_content)
    redaction_applied = redacted_content != original_content

    attrs = %{
      source_entry_id: entry_id,
      source_message_id: message_id,
      role: raw_message["role"],
      content: redacted_content,
      original_timestamp: parse_timestamp(raw_message["timestamp"]),
      redaction_applied: redaction_applied,
      patterns_matched: patterns,
      blocked: false,
      session_label: generate_session_label(entry_id)
    }

    Repo.transaction(fn ->
      # Insert message
      case %Message{}
           |> Message.changeset(attrs)
           |> Repo.insert() do
        {:ok, message} ->
          # Insert audit log
          {:ok, _audit} =
            %AuditLog{}
            |> AuditLog.changeset(%{
              livelog_message_id: message.id,
              original_content_hash: hash(original_content),
              redacted_content_hash: hash(redacted_content),
              action: if(redaction_applied, do: "redacted", else: "allowed"),
              layer: Redaction.get_decision_layer(original_content),
              patterns_fired: patterns,
              processing_time_us: processing_time
            })
            |> Repo.insert()

          # Broadcast to all subscribers
          PubSub.broadcast(@pubsub, @topic, {:new_message, message})

          message

        {:error, changeset} ->
          Logger.error("[Livelog.Publisher] Failed to save message: #{inspect(changeset.errors)}")
          Repo.rollback(changeset.errors)
      end
    end)
  end

  defp log_blocked(raw_message, reason, entry_id, message_id, start_time) do
    processing_time = System.monotonic_time(:microsecond) - start_time
    original_content = raw_message["content"]

    # Only log metadata, NEVER the content for blocked messages
    Logger.info(
      "[Livelog.Publisher] Message blocked",
      message_id: message_id,
      entry_id: entry_id,
      reason: reason,
      processing_time_us: processing_time
    )

    # Still create audit record (without storing content)
    %AuditLog{}
    |> AuditLog.changeset(%{
      original_content_hash: hash(original_content),
      redacted_content_hash: "BLOCKED",
      action: "blocked",
      layer: 1,
      patterns_fired: [to_string(reason)],
      processing_time_us: processing_time
    })
    |> Repo.insert()
  end

  defp hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp hash(_), do: "nil"

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp generate_session_label(nil), do: "Unknown Session"

  defp generate_session_label(entry_id) do
    "Session #{String.slice(entry_id, 0, 8)}"
  end
end
