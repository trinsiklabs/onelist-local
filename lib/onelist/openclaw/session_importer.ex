defmodule Onelist.OpenClaw.SessionImporter do
  @moduledoc """
  Imports historical OpenClaw session transcripts into Onelist.

  Sessions are imported chronologically to maintain memory chain integrity.
  This module reads files directly - no OpenClaw runtime required.

  ## Usage

      # List sessions that would be imported
      {:ok, sessions} = SessionImporter.list_sessions("~/.openclaw")

      # Import all sessions
      {:ok, result} = SessionImporter.import_directory(user, "~/.openclaw")

      # Dry run (don't actually import)
      {:ok, result} = SessionImporter.import_directory(user, "~/.openclaw", dry_run: true)

      # Import single file
      {:ok, result} = SessionImporter.import_session_file(user, path)

      # Import with CLI progress bar
      alias Onelist.OpenClaw.Progress
      SessionImporter.import_directory(user, "~/.openclaw",
        progress: &Progress.cli_reporter/3
      )

  ## Memory Chain Integrity

  Sessions are imported in chronological order (by earliest message timestamp)
  to ensure proper memory chain sequencing when TrustedMemory is enabled.
  """

  import Ecto.Query
  require Logger

  alias Onelist.OpenClaw.JsonlParser
  alias Onelist.ChatLogs
  alias Onelist.Entries.Entry
  alias Onelist.Repo

  @doc """
  Import all sessions from an OpenClaw directory.

  Scans for `.jsonl` files, sorts them chronologically, and imports each one.

  ## Options

  - `:agent_id` - Filter to specific agent (default: all)
  - `:after` - Only import sessions after this DateTime
  - `:before` - Only import sessions before this DateTime
  - `:dry_run` - Don't actually import, just return what would be imported
  - `:progress` - Callback function `(current, total, context) -> any()` for progress reporting

  ## Progress Callback

  The progress callback receives:
  - `current` - Current session number (1-indexed)
  - `total` - Total number of sessions
  - `context` - Map with `:file_path`, `:session_id`, `:status` keys

  Use `Onelist.OpenClaw.Progress.cli_reporter/3` for a CLI progress bar.

  ## Returns

  - `{:ok, %{imported_count: n, failed_count: n, ...}}` on success
  - `{:error, reason}` on failure
  """
  def import_directory(user, path, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    progress_fn = Keyword.get(opts, :progress)

    case list_sessions(path, opts) do
      {:ok, sessions} when dry_run ->
        {:ok,
         %{
           dry_run: true,
           would_import: length(sessions),
           sessions: sessions
         }}

      {:ok, sessions} ->
        total = length(sessions)

        results =
          sessions
          |> Enum.with_index(1)
          |> Enum.map(fn {session, index} ->
            # Report progress before import
            if progress_fn do
              progress_fn.(index, total, %{
                file_path: session.path,
                session_id: session.session_id,
                status: :importing
              })
            end

            result =
              case import_session_file(user, session.path) do
                {:ok, result} -> {:ok, result}
                {:error, reason} -> {:error, session.path, reason}
              end

            # Report completion status
            if progress_fn do
              status = if match?({:ok, _}, result), do: :complete, else: :failed

              progress_fn.(index, total, %{
                file_path: session.path,
                session_id: session.session_id,
                status: status
              })
            end

            result
          end)

        imported = Enum.count(results, &match?({:ok, _}, &1))
        failed = Enum.count(results, &match?({:error, _, _}, &1))

        # Finish progress display
        if progress_fn do
          Onelist.OpenClaw.Progress.finish(total, failed: failed)
        end

        {:ok,
         %{
           imported_count: imported,
           failed_count: failed,
           total: total,
           results: results
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Import a single session file.

  Creates a `chat_log` entry with `source_type: "openclaw_import"`.
  Preserves original timestamps from the messages.

  ## Returns

  - `{:ok, %{entry_id: id, message_count: n}}` on success
  - `{:error, reason}` on failure
  """
  def import_session_file(user, file_path, _opts \\ []) do
    with {:ok, messages} <- JsonlParser.parse_file(file_path),
         {:ok, session_info} <- JsonlParser.extract_session_info(file_path),
         {:ok, earliest} <- JsonlParser.get_earliest_timestamp(messages),
         {:ok, latest} <- JsonlParser.get_latest_timestamp(messages) do
      session_id = build_session_id(session_info)

      # Check if already imported (idempotency)
      case get_existing_entry(user, session_id) do
        nil ->
          create_import_entry(
            user,
            file_path,
            session_id,
            session_info,
            messages,
            earliest,
            latest
          )

        existing ->
          # Already imported, return existing
          {:ok,
           %{
             entry_id: existing.id,
             message_count: existing.metadata["message_count"] || length(messages),
             already_existed: true
           }}
      end
    end
  end

  @doc """
  List importable sessions without importing.

  Returns sessions sorted by earliest timestamp (chronological order).

  ## Options

  - `:agent_id` - Filter to specific agent
  - `:after` - Only sessions after this DateTime
  - `:before` - Only sessions before this DateTime

  ## Returns

  - `{:ok, [%{path: ..., agent_id: ..., session_id: ..., earliest_timestamp: ...}]}`
  - `{:error, reason}`
  """
  def list_sessions(path, opts \\ []) do
    expanded_path = Path.expand(path)

    if File.dir?(expanded_path) do
      agent_filter = Keyword.get(opts, :agent_id)
      after_filter = Keyword.get(opts, :after)
      before_filter = Keyword.get(opts, :before)

      sessions =
        expanded_path
        |> find_session_files(agent_filter)
        |> Enum.map(&build_session_info/1)
        |> Enum.reject(&is_nil/1)
        |> apply_time_filters(after_filter, before_filter)
        |> Enum.sort_by(& &1.earliest_timestamp)

      {:ok, sessions}
    else
      {:error, :directory_not_found}
    end
  end

  # Private functions

  defp find_session_files(base_path, agent_filter) do
    pattern =
      if agent_filter do
        Path.join([base_path, "agents", agent_filter, "sessions", "*.jsonl"])
      else
        Path.join([base_path, "agents", "*", "sessions", "*.jsonl"])
      end

    Path.wildcard(pattern)
  end

  defp build_session_info(file_path) do
    with {:ok, messages} <- JsonlParser.parse_file(file_path),
         {:ok, session_info} <- JsonlParser.extract_session_info(file_path),
         {:ok, earliest} <- JsonlParser.get_earliest_timestamp(messages) do
      %{
        path: file_path,
        agent_id: session_info.agent_id,
        session_id: session_info.session_id,
        earliest_timestamp: earliest,
        message_count: length(messages)
      }
    else
      _ -> nil
    end
  end

  defp apply_time_filters(sessions, after_filter, before_filter) do
    sessions
    |> maybe_filter_after(after_filter)
    |> maybe_filter_before(before_filter)
  end

  defp maybe_filter_after(sessions, nil), do: sessions

  defp maybe_filter_after(sessions, after_dt) do
    after_iso = DateTime.to_iso8601(after_dt)

    Enum.filter(sessions, fn s ->
      s.earliest_timestamp && s.earliest_timestamp > after_iso
    end)
  end

  defp maybe_filter_before(sessions, nil), do: sessions

  defp maybe_filter_before(sessions, before_dt) do
    before_iso = DateTime.to_iso8601(before_dt)

    Enum.filter(sessions, fn s ->
      s.earliest_timestamp && s.earliest_timestamp < before_iso
    end)
  end

  defp build_session_id(session_info) do
    "openclaw:#{session_info.agent_id}:#{session_info.session_id}"
  end

  defp get_existing_entry(user, session_id) do
    Entry
    |> where([e], e.user_id == ^user.id)
    |> where([e], e.entry_type == "chat_log")
    |> where([e], fragment("metadata->>'session_id' = ?", ^session_id))
    |> Repo.one()
  end

  defp create_import_entry(user, file_path, session_id, session_info, messages, earliest, latest) do
    # Build JSONL content from messages
    content =
      messages
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")

    # Determine title from date
    title =
      case earliest do
        nil -> "Imported Chat Session"
        ts -> "Chat Session: #{String.slice(ts, 0, 10)}"
      end

    # Create the entry using ChatLogs-compatible structure
    {:ok, entry} =
      Onelist.Entries.create_entry(user, %{
        title: title,
        entry_type: "chat_log",
        source_type: "openclaw_import",
        metadata: %{
          "session_id" => session_id,
          "agent_id" => session_info.agent_id,
          "original_session_id" => session_info.session_id,
          "started_at" => earliest,
          "last_message_at" => latest,
          "message_count" => length(messages),
          "status" => "imported",
          "imported_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "source_file" => file_path
        },
        representations: [
          %{
            mime_type: "application/jsonl",
            content: content,
            type: "chat_log"
          }
        ]
      })

    Logger.info("Imported OpenClaw session: #{session_id} (#{length(messages)} messages)")

    {:ok,
     %{
       entry_id: entry.id,
       message_count: length(messages),
       session_id: session_id
     }}
  end
end
