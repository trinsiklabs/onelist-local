defmodule Onelist.Searcher.Workers.BatchEmbedWorker do
  @moduledoc """
  Oban worker for batch embedding multiple entries.

  This worker is useful for re-embedding entries after a model upgrade
  or for initial embedding of existing content.
  """

  use Oban.Worker,
    queue: :embeddings_batch,
    max_attempts: 3,
    priority: 2

  alias Onelist.Searcher

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_ids" => entry_ids}}) when is_list(entry_ids) do
    Logger.info("Starting batch embedding for #{length(entry_ids)} entries")

    results =
      entry_ids
      |> Enum.map(fn entry_id ->
        case Searcher.enqueue_embedding(entry_id, priority: -1) do
          {:ok, _job} -> {:ok, entry_id}
          {:error, reason} -> {:error, entry_id, reason}
        end
      end)

    successes = Enum.count(results, fn r -> match?({:ok, _}, r) end)
    failures = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

    Logger.info("Batch embedding queued: #{successes} succeeded, #{failures} failed")

    :ok
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Invalid batch embed worker args: #{inspect(args)}")
    {:error, "Invalid args - expected entry_ids list"}
  end
end
