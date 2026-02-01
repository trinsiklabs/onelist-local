defmodule Onelist.Storage.Mirror do
  @moduledoc """
  Coordinates asset mirroring across storage backends.

  Handles queuing mirror jobs, performing sync operations, and tracking
  mirror status across all configured backends.

  ## Mirroring Flow

  1. Asset uploaded to primary backend
  2. `queue_mirrors/2` called to queue Oban jobs for each mirror backend
  3. `StorageMirrorWorker` executes `sync_to_backend/3` for each mirror
  4. Mirror status tracked in `asset_mirrors` table

  ## Configuration

  Mirror backends are configured in `config.exs`:

      config :onelist, Onelist.Storage,
        primary_backend: :local,
        mirror_backends: [:s3, :encrypted_s3]
  """

  alias Onelist.Repo
  alias Onelist.Entries.{Asset, AssetMirror}
  
  import Ecto.Query

  require Logger

  @doc """
  Queues mirror sync jobs for all configured mirror backends.

  Creates `AssetMirror` records and enqueues Oban jobs for each backend.

  ## Options

  - `:backends` - Override configured mirror backends
  - `:sync_mode` - Sync mode for all mirrors (default: "full")
  - `:encrypted` - Whether to encrypt content in mirrors

  ## Returns

  - `{:ok, [mirror]}` - List of created mirror records
  - `{:error, reason}` - If queuing failed
  """
  @spec queue_mirrors(Asset.t(), keyword()) :: {:ok, [AssetMirror.t()]} | {:error, term()}
  def queue_mirrors(%Asset{} = asset, opts \\ []) do
    backends = Keyword.get(opts, :backends, configured_mirror_backends())
    sync_mode = Keyword.get(opts, :sync_mode, "full")
    encrypted = Keyword.get(opts, :encrypted, false)

    mirrors =
      Enum.map(backends, fn backend ->
        create_mirror_and_queue_job(asset, backend, sync_mode, encrypted)
      end)

    errors = Enum.filter(mirrors, &match?({:error, _}, &1))

    if Enum.empty?(errors) do
      {:ok, Enum.map(mirrors, fn {:ok, mirror} -> mirror end)}
    else
      {:error, {:partial_failure, errors}}
    end
  end

  @doc """
  Syncs an asset to a specific backend.

  Called by the `StorageMirrorWorker` to perform the actual sync.

  ## Options

  - `:encryption_key` - Key for E2EE (required if mirror.encrypted is true)

  ## Returns

  - `{:ok, mirror}` - Updated mirror record with synced status
  - `{:error, reason}` - If sync failed
  """
  @spec sync_to_backend(Asset.t(), AssetMirror.t(), keyword()) ::
          {:ok, AssetMirror.t()} | {:error, term()}
  def sync_to_backend(%Asset{} = asset, %AssetMirror{} = mirror, opts \\ []) do
    # Mark as syncing
    {:ok, mirror} = update_mirror(mirror, AssetMirror.mark_syncing(mirror))

    source_backend = get_backend_module(asset.primary_backend)
    target_backend = get_backend_module(mirror.backend)

    with {:ok, content} <- source_backend.get(asset.storage_path),
         content <- maybe_encrypt(content, mirror.encrypted, opts),
         {:ok, _metadata} <- target_backend.put(mirror.storage_path, content, opts) do
      # Verify checksum if available
      if asset.checksum do
        verify_checksum(target_backend, mirror.storage_path, asset.checksum, mirror)
      else
        {:ok, mirror} = update_mirror(mirror, AssetMirror.mark_synced(mirror))
        {:ok, mirror}
      end
    else
      {:error, reason} ->
        Logger.error("Mirror sync failed for asset #{asset.id} to #{mirror.backend}: #{inspect(reason)}")
        {:ok, _updated_mirror} = update_mirror(mirror, AssetMirror.mark_failed(mirror, inspect(reason)))
        {:error, reason}
    end
  end

  @doc """
  Deletes an asset from a specific mirror backend.

  ## Returns

  - `:ok` - Successfully deleted
  - `{:error, reason}` - If deletion failed
  """
  @spec delete_from_backend(AssetMirror.t(), keyword()) :: :ok | {:error, term()}
  def delete_from_backend(%AssetMirror{} = mirror, _opts \\ []) do
    backend = get_backend_module(mirror.backend)

    case backend.delete(mirror.storage_path) do
      :ok ->
        Repo.delete(mirror)
        :ok

      {:error, reason} ->
        Logger.error("Mirror delete failed for #{mirror.backend}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the sync status for all mirrors of an asset.

  ## Returns

  A map with backend names as keys and status info as values:

      %{
        "s3" => %{status: "synced", synced_at: ~U[...], sync_mode: "full"},
        "local" => %{status: "pending", synced_at: nil, sync_mode: "full"}
      }
  """
  @spec mirror_status(Asset.t()) :: %{String.t() => map()}
  def mirror_status(%Asset{id: asset_id}) do
    AssetMirror
    |> where([m], m.asset_id == ^asset_id)
    |> Repo.all()
    |> Enum.map(fn mirror ->
      {mirror.backend,
       %{
         status: mirror.status,
         synced_at: mirror.synced_at,
         sync_mode: mirror.sync_mode,
         encrypted: mirror.encrypted,
         error_message: mirror.error_message,
         retry_count: mirror.retry_count
       }}
    end)
    |> Map.new()
  end

  @doc """
  Returns all mirrors for an asset.
  """
  @spec get_mirrors(Asset.t()) :: [AssetMirror.t()]
  def get_mirrors(%Asset{id: asset_id}) do
    AssetMirror
    |> where([m], m.asset_id == ^asset_id)
    |> Repo.all()
  end

  @doc """
  Returns a synced mirror for fallback retrieval.

  Prioritizes local mirrors for faster access.
  """
  @spec get_synced_mirror(Asset.t()) :: AssetMirror.t() | nil
  def get_synced_mirror(%Asset{id: asset_id}) do
    AssetMirror
    |> where([m], m.asset_id == ^asset_id and m.status == "synced")
    |> order_by([m], fragment("CASE WHEN ? = 'local' THEN 0 ELSE 1 END", m.backend))
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Returns all failed mirrors that can be retried.
  """
  @spec get_retriable_mirrors() :: [AssetMirror.t()]
  def get_retriable_mirrors do
    AssetMirror
    |> where([m], m.status == "failed" and m.retry_count < 5)
    |> preload(:asset)
    |> Repo.all()
  end

  # Private functions

  defp create_mirror_and_queue_job(asset, backend, sync_mode, encrypted) do
    # Generate storage path for this backend
    storage_path = generate_mirror_path(asset, backend)

    attrs = %{
      asset_id: asset.id,
      backend: to_string(backend),
      storage_path: storage_path,
      status: "pending",
      sync_mode: sync_mode,
      encrypted: encrypted || is_encrypted_backend?(backend)
    }

    Repo.transaction(fn ->
      case %AssetMirror{} |> AssetMirror.changeset(attrs) |> Repo.insert() do
        {:ok, mirror} ->
          # Queue Oban job
          %{
            asset_id: asset.id,
            mirror_id: mirror.id,
            action: "sync"
          }
          |> Onelist.Workers.StorageMirrorWorker.new()
          |> Oban.insert()

          mirror

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp generate_mirror_path(asset, _backend) do
    # Use the same path structure for all backends
    # The backend-specific path is just the storage_path
    asset.storage_path
  end

  defp update_mirror(_mirror, changeset) do
    Repo.update(changeset)
  end

  defp maybe_encrypt(content, false, _opts), do: content

  defp maybe_encrypt(content, true, opts) do
    case Keyword.get(opts, :encryption_key) do
      nil ->
        Logger.warning("Encryption key not provided for encrypted mirror, storing unencrypted")
        content

      key ->
        case Onelist.Encryption.encrypt(content, key) do
          {:ok, encrypted} -> encrypted
          {:error, _} -> content
        end
    end
  end

  defp verify_checksum(backend, path, expected_checksum, mirror) do
    case backend.get(path) do
      {:ok, content} ->
        actual_checksum =
          :crypto.hash(:sha256, content)
          |> Base.encode16(case: :lower)

        if actual_checksum == expected_checksum do
          {:ok, updated_mirror} = update_mirror(mirror, AssetMirror.mark_synced(mirror))
          {:ok, updated_mirror}
        else
          {:ok, _failed_mirror} =
            update_mirror(mirror, AssetMirror.mark_failed(mirror, "checksum_mismatch"))

          {:error, :checksum_mismatch}
        end

      {:error, reason} ->
        {:ok, _failed_mirror} = update_mirror(mirror, AssetMirror.mark_failed(mirror, inspect(reason)))
        {:error, reason}
    end
  end

  defp get_backend_module(backend) when is_atom(backend) do
    get_backend_module(to_string(backend))
  end

  defp get_backend_module("local"), do: Onelist.Storage.Backends.Local
  defp get_backend_module("s3"), do: Onelist.Storage.Backends.S3
  defp get_backend_module("gcs"), do: Onelist.Storage.Backends.GCS
  defp get_backend_module("encrypted_s3"), do: Onelist.Storage.Backends.Encrypted

  defp get_backend_module(backend) do
    Logger.warning("Unknown backend: #{backend}, falling back to local")
    Onelist.Storage.Backends.Local
  end

  defp is_encrypted_backend?(backend) when is_atom(backend) do
    is_encrypted_backend?(to_string(backend))
  end

  defp is_encrypted_backend?("encrypted_s3"), do: true
  defp is_encrypted_backend?("encrypted_" <> _), do: true
  defp is_encrypted_backend?(_), do: false

  defp configured_mirror_backends do
    Application.get_env(:onelist, Onelist.Storage, [])
    |> Keyword.get(:mirror_backends, [])
  end
end
