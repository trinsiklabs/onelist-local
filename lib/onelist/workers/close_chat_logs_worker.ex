defmodule Onelist.Workers.CloseChatLogsWorker do
  @moduledoc """
  Periodically closes inactive chat log sessions.

  A session is considered inactive if no messages have been received
  for a configurable period (default: 1 hour).

  When a session is closed:
  1. Status is set to "closed"
  2. Final memory extraction is triggered
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Entries.Entry
  alias Onelist.ChatLogs
  alias Onelist.Reader.Workers.ProcessEntryWorker

  @inactive_threshold_minutes 60

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    threshold = DateTime.utc_now() |> DateTime.add(-@inactive_threshold_minutes, :minute)

    # Find active sessions with no recent messages
    inactive_sessions =
      Entry
      |> where([e], e.entry_type == "chat_log")
      |> where([e], fragment("metadata->>'status' = ?", "active"))
      |> where([e], fragment("(metadata->>'last_message_at')::timestamp < ?", ^threshold))
      |> Repo.all()

    # Close each inactive session
    Enum.each(inactive_sessions, fn entry ->
      # Update status to closed
      {:ok, _} =
        Onelist.Entries.update_entry(entry, %{
          metadata:
            Map.merge(entry.metadata || %{}, %{
              "status" => "closed",
              "closed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "close_reason" => "inactive"
            })
        })

      # Queue memory extraction
      %{entry_id: entry.id, mode: "final"}
      |> ProcessEntryWorker.new()
      |> Oban.insert()
    end)

    {:ok, %{closed_count: length(inactive_sessions)}}
  end
end
