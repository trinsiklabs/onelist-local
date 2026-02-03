defmodule Onelist.Workers.StorageMirrorWorker do
  @moduledoc """
  Oban worker for async asset mirror operations.

  Handles syncing assets to mirror backends and deleting from mirrors.

  ## Job Args

  - `asset_id` - The asset to sync
  - `mirror_id` - The specific mirror record
  - `action` - "sync" or "delete"

  ## Retry Behavior

  - Max 5 attempts with exponential backoff
  - Failed mirrors are tracked in the `asset_mirrors` table
  - Cleanup worker can retry failed mirrors later
  """

  use Oban.Worker,
    queue: :storage,
    max_attempts: 5,
    unique: [period: 300, fields: [:args, :queue]]

  alias Onelist.Repo
  alias Onelist.Entries.{Asset, AssetMirror}
  alias Onelist.Storage.Mirror

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"action" => "sync", "asset_id" => asset_id, "mirror_id" => mirror_id}
      }) do
    with {:ok, asset} <- get_asset(asset_id),
         {:ok, mirror} <- get_mirror(mirror_id) do
      case Mirror.sync_to_backend(asset, mirror) do
        {:ok, _mirror} ->
          :ok

        {:error, reason} ->
          # Check if we should retry
          mirror = Repo.reload(mirror)

          if AssetMirror.can_retry?(mirror) do
            # Return error to trigger Oban retry with backoff
            {:error, reason}
          else
            # Max retries reached, mark as permanently failed
            Logger.error(
              "Mirror sync permanently failed for asset #{asset_id} to #{mirror.backend}"
            )

            :ok
          end
      end
    else
      {:error, :not_found} ->
        # Asset or mirror was deleted, skip
        Logger.info("Asset or mirror not found, skipping sync")
        :ok

      error ->
        error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "delete", "mirror_id" => mirror_id}}) do
    case get_mirror(mirror_id) do
      {:ok, mirror} ->
        case Mirror.delete_from_backend(mirror) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        # Already deleted
        :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Logger.error("Unknown storage mirror worker args: #{inspect(args)}")
    :ok
  end

  # Calculate backoff based on attempt number
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential backoff: 1min, 2min, 4min, 8min, 16min
    trunc(:math.pow(2, attempt - 1) * 60)
  end

  # Private functions

  defp get_asset(asset_id) do
    case Repo.get(Asset, asset_id) do
      nil -> {:error, :not_found}
      asset -> {:ok, asset}
    end
  end

  defp get_mirror(mirror_id) do
    case Repo.get(AssetMirror, mirror_id) do
      nil -> {:error, :not_found}
      mirror -> {:ok, mirror}
    end
  end
end
