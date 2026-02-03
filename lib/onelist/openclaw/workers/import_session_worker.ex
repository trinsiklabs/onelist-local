defmodule Onelist.OpenClaw.Workers.ImportSessionWorker do
  @moduledoc """
  Oban worker for importing OpenClaw session files.

  This worker processes one session file at a time. The queue should be
  configured with `max_concurrency: 1` to ensure sessions are imported
  in chronological order for memory chain integrity.

  ## Configuration

      config :onelist, Oban,
        queues: [
          openclaw_import: 1  # Sequential processing
        ]

  ## Usage

      # Queue a single file import
      %{user_id: user.id, file_path: "/path/to/session.jsonl"}
      |> ImportSessionWorker.new()
      |> Oban.insert()

      # Queue multiple files (will process sequentially)
      for path <- paths do
        %{user_id: user.id, file_path: path}
        |> ImportSessionWorker.new()
        |> Oban.insert()
      end

  """

  use Oban.Worker,
    queue: :openclaw_import,
    max_attempts: 3,
    unique: [period: 300, keys: [:file_path]]

  require Logger

  alias Onelist.OpenClaw.SessionImporter
  alias Onelist.Accounts.User
  alias Onelist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "file_path" => file_path} = args}) do
    Logger.info("ImportSessionWorker: Processing #{file_path}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("ImportSessionWorker: User not found: #{user_id}")
        {:error, :user_not_found}

      user ->
        opts = build_opts(args)

        case SessionImporter.import_session_file(user, file_path, opts) do
          {:ok, result} ->
            Logger.info("ImportSessionWorker: Imported #{file_path} -> entry #{result.entry_id}")
            :ok

          {:error, reason} ->
            Logger.error("ImportSessionWorker: Failed to import #{file_path}: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp build_opts(args) do
    []
    |> maybe_add_opt(:trigger_extraction, args["trigger_extraction"])
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  @doc """
  Queue import jobs for all sessions in a directory.

  Sessions are queued in chronological order to maintain memory chain integrity.

  ## Options

  - `:agent_id` - Filter to specific agent
  - `:after` - Only sessions after this DateTime
  - `:before` - Only sessions before this DateTime
  - `:trigger_extraction` - Queue memory extraction after import (default: true)

  ## Returns

  - `{:ok, %{queued: n, sessions: [...]}}` on success
  - `{:error, reason}` on failure
  """
  def queue_directory_import(user, path, opts \\ []) do
    case SessionImporter.list_sessions(path, opts) do
      {:ok, sessions} ->
        trigger_extraction = Keyword.get(opts, :trigger_extraction, true)

        jobs =
          sessions
          |> Enum.map(fn session ->
            %{
              user_id: user.id,
              file_path: session.path,
              trigger_extraction: trigger_extraction
            }
            |> __MODULE__.new()
          end)

        # Insert jobs in order - Oban will process them sequentially
        # due to queue concurrency of 1
        results = Enum.map(jobs, &Oban.insert/1)
        successful = Enum.count(results, &match?({:ok, _}, &1))

        {:ok,
         %{
           queued: successful,
           total: length(sessions),
           sessions: Enum.map(sessions, & &1.path)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
