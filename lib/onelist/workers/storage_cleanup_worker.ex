defmodule Onelist.Workers.StorageCleanupWorker do
  @moduledoc """
  Oban worker for retrying failed mirror syncs and cleaning up orphaned mirrors.

  This worker runs on a schedule (configured in config.exs) to:
  1. Retry failed mirrors that haven't exceeded max attempts
  2. Clean up orphaned mirror records (where asset was deleted)
  3. Remove stale pending mirrors that were never processed

  ## Configuration

  Add to config.exs:

      config :onelist, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"*/15 * * * *", Onelist.Workers.StorageCleanupWorker}  # Every 15 minutes
           ]}
        ]
  """

  use Oban.Worker,
    queue: :storage,
    max_attempts: 1

  alias Onelist.Repo
  alias Onelist.Entries.AssetMirror
  alias Onelist.Storage.Mirror

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    action = Map.get(args, "action", "all")

    case action do
      "all" ->
        retry_failed_mirrors()
        cleanup_orphaned_mirrors()
        cleanup_stale_pending()
        :ok

      "retry_failed" ->
        retry_failed_mirrors()
        :ok

      "cleanup_orphaned" ->
        cleanup_orphaned_mirrors()
        :ok

      "cleanup_stale" ->
        cleanup_stale_pending()
        :ok

      _ ->
        Logger.warning("Unknown cleanup action: #{action}")
        :ok
    end
  end

  @doc """
  Retries all failed mirrors that haven't exceeded max attempts.
  """
  def retry_failed_mirrors do
    mirrors = Mirror.get_retriable_mirrors()
    count = length(mirrors)

    if count > 0 do
      Logger.info("Retrying #{count} failed mirrors")

      Enum.each(mirrors, fn mirror ->
        # Re-queue the sync job
        %{
          asset_id: mirror.asset_id,
          mirror_id: mirror.id,
          action: "sync"
        }
        |> Onelist.Workers.StorageMirrorWorker.new()
        |> Oban.insert()
      end)
    end

    count
  end

  @doc """
  Removes mirror records where the parent asset no longer exists.
  """
  def cleanup_orphaned_mirrors do
    # Find mirrors where asset doesn't exist
    orphaned_query =
      from m in AssetMirror,
        left_join: a in assoc(m, :asset),
        where: is_nil(a.id),
        select: m.id

    orphaned_ids = Repo.all(orphaned_query)
    count = length(orphaned_ids)

    if count > 0 do
      Logger.info("Cleaning up #{count} orphaned mirrors")

      from(m in AssetMirror, where: m.id in ^orphaned_ids)
      |> Repo.delete_all()
    end

    count
  end

  @doc """
  Removes mirrors that have been pending for too long (likely stuck).
  """
  def cleanup_stale_pending do
    # Mirrors pending for more than 24 hours are considered stale
    stale_cutoff = DateTime.utc_now() |> DateTime.add(-24, :hour)

    stale_query =
      from m in AssetMirror,
        where: m.status == "pending" and m.inserted_at < ^stale_cutoff,
        select: m

    stale_mirrors = Repo.all(stale_query)
    count = length(stale_mirrors)

    if count > 0 do
      Logger.info("Re-queuing #{count} stale pending mirrors")

      Enum.each(stale_mirrors, fn mirror ->
        # Mark as failed and retry
        mirror
        |> AssetMirror.mark_failed("stale_pending")
        |> Repo.update()

        # Re-queue
        %{
          asset_id: mirror.asset_id,
          mirror_id: mirror.id,
          action: "sync"
        }
        |> Onelist.Workers.StorageMirrorWorker.new()
        |> Oban.insert()
      end)
    end

    count
  end
end
