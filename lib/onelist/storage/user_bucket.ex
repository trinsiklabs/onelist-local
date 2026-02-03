defmodule Onelist.Storage.UserBucket do
  @moduledoc """
  BYOB (Bring Your Own Bucket) credential management.

  Resolves storage backend configuration based on user settings.
  Falls back to Onelist-provided storage if no BYOB configured.

  ## Usage

      # Get backend for a user
      {:ok, backend_type, config} = UserBucket.get_backend_for_user(user_id)

      # Store with BYOB
      Storage.store(entry_id, filename, content, config: config)

  ## Credential Encryption

  User credentials are encrypted before storage using the application's
  secret key. This ensures credentials are protected at rest.
  """

  alias Onelist.Repo
  alias Onelist.Entries.UserStorageConfig

  import Ecto.Query

  require Logger

  @doc """
  Gets the storage backend configuration for a user.

  Returns the user's BYOB configuration if active, otherwise falls back
  to Onelist-provided storage.

  ## Returns

  - `{:ok, :onelist_cloud, config}` - Using Onelist-provided storage
  - `{:ok, :s3, config}` - Using user's S3-compatible bucket
  - `{:ok, :gcs, config}` - Using user's GCS bucket
  """
  @spec get_backend_for_user(String.t()) :: {:ok, atom(), map()}
  def get_backend_for_user(user_id) do
    case get_active_config(user_id) do
      nil ->
        # No BYOB: use Onelist-provided storage
        {:ok, :onelist_cloud, default_config()}

      %UserStorageConfig{provider: "r2"} = config ->
        {:ok, :s3, r2_config(config)}

      %UserStorageConfig{provider: "b2"} = config ->
        {:ok, :s3, b2_config(config)}

      %UserStorageConfig{provider: "s3"} = config ->
        {:ok, :s3, s3_config(config)}

      %UserStorageConfig{provider: "spaces"} = config ->
        {:ok, :s3, spaces_config(config)}

      %UserStorageConfig{provider: "wasabi"} = config ->
        {:ok, :s3, wasabi_config(config)}

      %UserStorageConfig{provider: "minio"} = config ->
        {:ok, :s3, minio_config(config)}

      %UserStorageConfig{provider: "gcs"} = config ->
        {:ok, :gcs, gcs_config(config)}
    end
  end

  @doc """
  Gets the active storage configuration for a user.
  """
  @spec get_active_config(String.t()) :: UserStorageConfig.t() | nil
  def get_active_config(user_id) do
    UserStorageConfig
    |> where([c], c.user_id == ^user_id and c.is_active == true)
    |> Repo.one()
  end

  @doc """
  Creates or updates a user's storage configuration.
  """
  @spec upsert_config(String.t(), map()) :: {:ok, UserStorageConfig.t()} | {:error, term()}
  def upsert_config(user_id, attrs) do
    # Encrypt credentials before storing
    attrs = Map.update(attrs, :credentials, nil, &encrypt_credentials/1)

    case get_active_config(user_id) do
      nil ->
        %UserStorageConfig{}
        |> UserStorageConfig.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      existing ->
        existing
        |> UserStorageConfig.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Removes a user's BYOB configuration, reverting to Onelist storage.
  """
  @spec remove_config(String.t()) :: :ok | {:error, term()}
  def remove_config(user_id) do
    case get_active_config(user_id) do
      nil ->
        :ok

      config ->
        case Repo.delete(config) do
          {:ok, _} -> :ok
          error -> error
        end
    end
  end

  @doc """
  Tests a storage configuration by attempting to list the bucket.
  """
  @spec test_config(map()) :: :ok | {:error, term()}
  def test_config(attrs) do
    # Build temporary config
    config = build_s3_config(attrs)

    # Try to list objects (limit 1) to verify access
    request =
      ExAws.S3.list_objects(config.bucket, max_keys: 1)
      |> Map.put(:config,
        access_key_id: config.access_key_id,
        secret_access_key: config.secret_access_key,
        region: config.region,
        host: get_host(config.endpoint),
        scheme: get_scheme(config.endpoint)
      )

    case ExAws.request(request) do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 403, _}} ->
        {:error, :access_denied}

      {:error, {:http_error, 404, _}} ->
        {:error, :bucket_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Marks a configuration as verified after successful connection test.
  """
  @spec mark_verified(UserStorageConfig.t()) :: {:ok, UserStorageConfig.t()} | {:error, term()}
  def mark_verified(config) do
    config
    |> UserStorageConfig.mark_verified()
    |> Repo.update()
  end

  @doc """
  Encrypts credentials for storage.
  """
  @spec encrypt_credentials(map()) :: binary()
  def encrypt_credentials(credentials) when is_map(credentials) do
    secret = get_encryption_key()
    payload = Jason.encode!(credentials)

    case Onelist.Encryption.encrypt(payload, secret) do
      {:ok, encrypted} -> encrypted
      {:error, _} -> raise "Failed to encrypt credentials"
    end
  end

  @doc """
  Decrypts stored credentials.
  """
  @spec decrypt_credentials(binary()) :: map()
  def decrypt_credentials(encrypted) when is_binary(encrypted) do
    secret = get_encryption_key()

    case Onelist.Encryption.decrypt(encrypted, secret) do
      {:ok, payload} -> Jason.decode!(payload)
      {:error, _} -> raise "Failed to decrypt credentials"
    end
  end

  # Private functions

  defp default_config do
    # Onelist-provided storage configuration
    app_config = Application.get_env(:onelist, Onelist.Storage.Backends.S3, [])

    %{
      bucket: Keyword.get(app_config, :bucket),
      region: Keyword.get(app_config, :region, "us-east-1"),
      endpoint: Keyword.get(app_config, :endpoint),
      access_key_id: Keyword.get(app_config, :access_key_id),
      secret_access_key: Keyword.get(app_config, :secret_access_key)
    }
  end

  defp r2_config(config) do
    credentials = decrypt_credentials(config.credentials)
    account_id = config.metadata["account_id"]

    %{
      bucket: config.bucket_name,
      region: "auto",
      endpoint: "https://#{account_id}.r2.cloudflarestorage.com",
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp b2_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      region: config.region,
      endpoint: "https://s3.#{config.region}.backblazeb2.com",
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp s3_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      region: config.region || "us-east-1",
      endpoint: config.endpoint,
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp spaces_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      region: config.region,
      endpoint: "https://#{config.region}.digitaloceanspaces.com",
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp wasabi_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      region: config.region || "us-east-1",
      endpoint: "https://s3.#{config.region || "us-east-1"}.wasabisys.com",
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp minio_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      region: config.region || "us-east-1",
      endpoint: config.endpoint,
      access_key_id: credentials["access_key_id"],
      secret_access_key: credentials["secret_access_key"]
    }
  end

  defp gcs_config(config) do
    credentials = decrypt_credentials(config.credentials)

    %{
      bucket: config.bucket_name,
      project_id: config.metadata["project_id"],
      credentials: credentials
    }
  end

  defp build_s3_config(attrs) do
    %{
      bucket: attrs["bucket_name"] || attrs[:bucket_name],
      region: attrs["region"] || attrs[:region] || "us-east-1",
      endpoint: attrs["endpoint"] || attrs[:endpoint],
      access_key_id: attrs["access_key_id"] || attrs[:access_key_id],
      secret_access_key: attrs["secret_access_key"] || attrs[:secret_access_key]
    }
  end

  defp get_host(nil), do: nil

  defp get_host(endpoint) do
    URI.parse(endpoint).host
  end

  defp get_scheme(nil), do: "https://"

  defp get_scheme(endpoint) do
    case URI.parse(endpoint).scheme do
      nil -> "https://"
      scheme -> scheme <> "://"
    end
  end

  defp get_encryption_key do
    # Use first 32 bytes of secret_key_base as encryption key
    secret_key_base =
      Application.get_env(:onelist, OnelistWeb.Endpoint)[:secret_key_base] ||
        raise "secret_key_base not configured"

    :crypto.hash(:sha256, secret_key_base)
  end
end
