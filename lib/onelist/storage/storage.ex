defmodule Onelist.Storage do
  @moduledoc """
  Main facade for asset storage operations.

  Provides a unified interface for storing, retrieving, and managing assets
  across multiple storage backends with automatic mirroring support.

  ## Configuration

      config :onelist, Onelist.Storage,
        primary_backend: :local,
        mirror_backends: [:s3],
        enable_e2ee: false,
        enable_tiered_sync: false,
        max_local_asset_size: 1_000_000

  ## Usage

      # Store a file
      {:ok, asset} = Storage.store(entry_id, "photo.jpg", binary_content)

      # Retrieve content
      {:ok, content} = Storage.retrieve(asset)

      # Get a presigned download URL
      {:ok, url} = Storage.presigned_url(asset)

      # Delete an asset
      :ok = Storage.delete(asset)

  ## Backends

  - `:local` - Local filesystem (default)
  - `:s3` - AWS S3 or S3-compatible services
  - `:gcs` - Google Cloud Storage
  - `:encrypted_s3` - S3 with E2EE wrapper
  """

  alias Onelist.Repo
  alias Onelist.Entries.Asset
  alias Onelist.Storage.{Mirror, PathGenerator}

  import Ecto.Query

  require Logger

  @doc """
  Stores content and creates an asset record.

  Uploads content to the primary backend, creates an asset record,
  and queues mirror jobs for configured mirror backends.

  ## Options

  - `:content_type` - MIME type (auto-detected from filename if not provided)
  - `:metadata` - Additional metadata map
  - `:representation_id` - Associate with a specific representation
  - `:encrypt` - Whether to encrypt content (overrides config)
  - `:skip_mirrors` - Skip queuing mirror jobs

  ## Returns

  - `{:ok, asset}` - Successfully stored with asset record
  - `{:error, reason}` - Storage or database error
  """
  @spec store(String.t(), String.t(), binary(), keyword()) ::
          {:ok, Asset.t()} | {:error, term()}
  def store(entry_id, filename, content, opts \\ []) do
    backend = primary_backend()
    backend_module = get_backend_module(backend)
    content_type = Keyword.get(opts, :content_type, MIME.from_path(filename))

    # Generate storage path
    storage_path = PathGenerator.generate(entry_id, filename)

    # Compute checksum
    checksum = compute_checksum(content)

    # Store in primary backend
    storage_opts = [content_type: content_type]

    case backend_module.put(storage_path, content, storage_opts) do
      {:ok, _metadata} ->
        # Create asset record
        asset_attrs = %{
          entry_id: entry_id,
          filename: filename,
          mime_type: content_type,
          storage_path: storage_path,
          file_size: byte_size(content),
          primary_backend: to_string(backend),
          checksum: checksum,
          encrypted: Keyword.get(opts, :encrypt, false),
          metadata: Keyword.get(opts, :metadata, %{}),
          representation_id: Keyword.get(opts, :representation_id)
        }

        case create_asset(asset_attrs) do
          {:ok, asset} ->
            # Queue mirrors unless skipped
            unless Keyword.get(opts, :skip_mirrors, false) do
              Mirror.queue_mirrors(asset, opts)
            end

            {:ok, asset}

          {:error, changeset} ->
            # Cleanup stored file on DB error
            backend_module.delete(storage_path)
            {:error, changeset}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves content for an asset.

  Attempts to retrieve from the primary backend first. If that fails,
  falls back to any synced mirror.

  ## Options

  - `:encryption_key` - Key for decrypting E2EE content

  ## Returns

  - `{:ok, binary}` - Content retrieved successfully
  - `{:error, :not_found}` - Asset not found in any backend
  - `{:error, reason}` - Other retrieval error
  """
  @spec retrieve(Asset.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def retrieve(%Asset{} = asset, opts \\ []) do
    backend_module = get_backend_module(asset.primary_backend)

    case backend_module.get(asset.storage_path) do
      {:ok, content} ->
        maybe_decrypt(content, asset.encrypted, opts)

      {:error, _reason} ->
        # Try fallback to mirrors
        retrieve_from_mirror(asset, opts)
    end
  end

  @doc """
  Generates a presigned URL for direct asset download.

  ## Options

  - `:expires_in` - URL expiration in seconds (default: 3600)

  ## Returns

  - `{:ok, url}` - Presigned URL
  - `{:error, reason}` - If URL generation failed
  """
  @spec presigned_url(Asset.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presigned_url(%Asset{} = asset, opts \\ []) do
    backend_module = get_backend_module(asset.primary_backend)
    backend_module.presigned_url(asset.storage_path, opts)
  end

  @doc """
  Deletes an asset and all its mirrors.

  Removes content from all backends and deletes the asset record.

  ## Returns

  - `:ok` - Successfully deleted
  - `{:error, reason}` - If deletion failed
  """
  @spec delete(Asset.t()) :: :ok | {:error, term()}
  def delete(%Asset{} = asset) do
    # Load mirrors if not loaded
    asset = Repo.preload(asset, :mirrors)

    # Delete from primary backend
    backend_module = get_backend_module(asset.primary_backend)
    _primary_result = backend_module.delete(asset.storage_path)

    # Delete from all mirrors
    Enum.each(asset.mirrors, fn mirror ->
      Mirror.delete_from_backend(mirror)
    end)

    # Delete thumbnail if exists
    if asset.thumbnail_path do
      backend_module.delete(asset.thumbnail_path)
    end

    # Delete asset record
    case Repo.delete(asset) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Checks if an asset exists in its primary backend.
  """
  @spec exists?(Asset.t()) :: boolean()
  def exists?(%Asset{} = asset) do
    backend_module = get_backend_module(asset.primary_backend)
    backend_module.exists?(asset.storage_path)
  end

  @doc """
  Gets metadata for an asset from its primary backend.
  """
  @spec head(Asset.t()) :: {:ok, map()} | {:error, term()}
  def head(%Asset{} = asset) do
    backend_module = get_backend_module(asset.primary_backend)
    backend_module.head(asset.storage_path)
  end

  @doc """
  Returns the mirror status for an asset.

  See `Onelist.Storage.Mirror.mirror_status/1`.
  """
  @spec mirror_status(Asset.t()) :: map()
  def mirror_status(%Asset{} = asset) do
    Mirror.mirror_status(asset)
  end

  @doc """
  Gets the primary backend module.
  """
  @spec primary_backend() :: atom()
  def primary_backend do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(:primary_backend, :local)
  end

  @doc """
  Gets the configured mirror backends.
  """
  @spec mirror_backends() :: [atom()]
  def mirror_backends do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(:mirror_backends, [])
  end

  @doc """
  Returns true if E2EE is enabled.
  """
  @spec e2ee_enabled?() :: boolean()
  def e2ee_enabled? do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(:enable_e2ee, false)
  end

  @doc """
  Returns true if tiered sync is enabled.
  """
  @spec tiered_sync_enabled?() :: boolean()
  def tiered_sync_enabled? do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(:enable_tiered_sync, false)
  end

  @doc """
  Gets an asset by ID with mirrors preloaded.
  """
  @spec get_asset(String.t()) :: Asset.t() | nil
  def get_asset(id) do
    Asset
    |> where([a], a.id == ^id)
    |> preload(:mirrors)
    |> Repo.one()
  end

  @doc """
  Lists assets for an entry.
  """
  @spec list_assets(String.t()) :: [Asset.t()]
  def list_assets(entry_id) do
    Asset
    |> where([a], a.entry_id == ^entry_id)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  # Private functions

  defp create_asset(attrs) do
    %Asset{}
    |> Asset.changeset(attrs)
    |> Repo.insert()
  end

  defp retrieve_from_mirror(asset, opts) do
    case Mirror.get_synced_mirror(asset) do
      nil ->
        {:error, :not_found}

      mirror ->
        backend_module = get_backend_module(mirror.backend)

        case backend_module.get(mirror.storage_path) do
          {:ok, content} ->
            # Decrypt if mirror is encrypted
            if mirror.encrypted do
              maybe_decrypt(content, true, opts)
            else
              {:ok, content}
            end

          error ->
            error
        end
    end
  end

  defp maybe_decrypt(content, false, _opts), do: {:ok, content}

  defp maybe_decrypt(content, true, opts) do
    case Keyword.get(opts, :encryption_key) do
      nil ->
        Logger.warning("Encryption key not provided for encrypted asset")
        {:error, :encryption_key_required}

      key ->
        Onelist.Encryption.decrypt(content, key)
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

  defp compute_checksum(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
