defmodule Onelist.Livelog.HistoricalProcessor do
  @moduledoc """
  One-time processor for historical chat logs.

  Run this ONCE to populate livelog_messages from existing ChatLogs data.
  Processes in batches to avoid memory issues with 73MB of data.

  ## Usage

      # In IEx:
      iex> Onelist.Livelog.HistoricalProcessor.process_all()
      
      # Or with options:
      iex> Onelist.Livelog.HistoricalProcessor.process_all(batch_size: 50)
  """

  alias Onelist.{Repo, ChatLogs}
  alias Onelist.Accounts.User
  alias Onelist.Livelog.{Redaction, Message, AuditLog}

  require Logger

  @batch_size 100
  @stream_user_id "deba7211-889d-4381-afcc-2dca0c56b17b"

  @doc """
  Process all historical chat logs for Stream.

  Options:
  - `:batch_size` - Number of messages per transaction (default: 100)
  - `:dry_run` - If true, don't actually save (default: false)
  """
  def process_all(opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @batch_size)
    dry_run = Keyword.get(opts, :dry_run, false)

    Logger.info("[HistoricalProcessor] Starting historical data migration...")
    Logger.info("[HistoricalProcessor] Batch size: #{batch_size}, Dry run: #{dry_run}")

    start_time = System.monotonic_time(:second)

    user = Repo.get!(User, @stream_user_id)

    {:ok, sessions} = ChatLogs.list_sessions(user, 1000)
    total_sessions = length(sessions)

    Logger.info("[HistoricalProcessor] Found #{total_sessions} sessions to process")

    stats =
      sessions
      |> Enum.with_index(1)
      |> Enum.reduce(%{processed: 0, blocked: 0, errors: 0, skipped: 0}, fn {session, idx}, acc ->
        Logger.info(
          "[HistoricalProcessor] Processing session #{idx}/#{total_sessions}: #{session.session_id}"
        )

        session_stats = process_session(user, session, batch_size, dry_run)

        %{
          processed: acc.processed + session_stats.processed,
          blocked: acc.blocked + session_stats.blocked,
          errors: acc.errors + session_stats.errors,
          skipped: acc.skipped + session_stats.skipped
        }
      end)

    elapsed = System.monotonic_time(:second) - start_time

    Logger.info("""
    [HistoricalProcessor] Migration complete!

    Stats:
    - Processed: #{stats.processed}
    - Blocked: #{stats.blocked}
    - Skipped (duplicates): #{stats.skipped}
    - Errors: #{stats.errors}
    - Duration: #{elapsed}s
    """)

    {:ok, stats}
  end

  @doc """
  Process a single session.
  """
  def process_session(user, session, batch_size \\ @batch_size, dry_run \\ false) do
    case ChatLogs.get_recent_messages(user, session.session_id, 10_000) do
      {:ok, messages} ->
        messages
        |> Enum.chunk_every(batch_size)
        |> Enum.reduce(%{processed: 0, blocked: 0, errors: 0, skipped: 0}, fn batch, acc ->
          batch_stats = process_batch(batch, session.entry_id, dry_run)

          %{
            processed: acc.processed + batch_stats.processed,
            blocked: acc.blocked + batch_stats.blocked,
            errors: acc.errors + batch_stats.errors,
            skipped: acc.skipped + batch_stats.skipped
          }
        end)

      {:error, _} ->
        %{processed: 0, blocked: 0, errors: 1, skipped: 0}
    end
  end

  defp process_batch(messages, entry_id, dry_run) do
    if dry_run do
      # Dry run - just count what would happen
      Enum.reduce(messages, %{processed: 0, blocked: 0, errors: 0, skipped: 0}, fn msg, acc ->
        case Redaction.redact(msg["content"]) do
          {:blocked, _} -> %{acc | blocked: acc.blocked + 1}
          {:ok, _} -> %{acc | processed: acc.processed + 1}
        end
      end)
    else
      Repo.transaction(fn ->
        Enum.reduce(messages, %{processed: 0, blocked: 0, errors: 0, skipped: 0}, fn msg, acc ->
          case process_single_message(msg, entry_id) do
            :processed -> %{acc | processed: acc.processed + 1}
            :blocked -> %{acc | blocked: acc.blocked + 1}
            :skipped -> %{acc | skipped: acc.skipped + 1}
            :error -> %{acc | errors: acc.errors + 1}
          end
        end)
      end)
      |> case do
        {:ok, stats} -> stats
        {:error, _} -> %{processed: 0, blocked: 0, errors: 1, skipped: 0}
      end
    end
  end

  defp process_single_message(raw_message, entry_id) do
    message_id = raw_message["id"]

    # Skip if already processed
    if message_id && Repo.get_by(Message, source_message_id: message_id) do
      :skipped
    else
      content = raw_message["content"]

      case Redaction.redact(content) do
        {:blocked, reason} ->
          # Log but don't save message
          Logger.debug("[HistoricalProcessor] Blocked: #{reason}")

          %AuditLog{}
          |> AuditLog.changeset(%{
            original_content_hash: hash(content),
            redacted_content_hash: "BLOCKED",
            action: "blocked",
            layer: 1,
            patterns_fired: [to_string(reason)],
            processing_time_us: 0
          })
          |> Repo.insert()

          :blocked

        {:ok, redacted_content} ->
          patterns = Redaction.get_matched_patterns(content)
          redaction_applied = redacted_content != content

          attrs = %{
            source_entry_id: entry_id,
            source_message_id: message_id,
            role: raw_message["role"],
            content: redacted_content,
            original_timestamp: parse_timestamp(raw_message["timestamp"]),
            redaction_applied: redaction_applied,
            patterns_matched: patterns,
            blocked: false
          }

          case %Message{} |> Message.changeset(attrs) |> Repo.insert() do
            {:ok, message} ->
              # Also create audit entry
              %AuditLog{}
              |> AuditLog.changeset(%{
                livelog_message_id: message.id,
                original_content_hash: hash(content),
                redacted_content_hash: hash(redacted_content),
                action: if(redaction_applied, do: "redacted", else: "allowed"),
                layer: Redaction.get_decision_layer(content),
                patterns_fired: patterns,
                processing_time_us: 0
              })
              |> Repo.insert()

              :processed

            {:error, _changeset} ->
              :error
          end
      end
    end
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
end
