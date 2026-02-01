defmodule Onelist.Storage.Backends.Encrypted do
  @moduledoc """
  E2EE wrapper for any storage backend.

  Wraps another storage backend with client-side encryption.
  Content is encrypted before upload and decrypted after download,
  enabling zero-knowledge cloud storage.

  ## Usage

  Pass the inner backend and encryption key via options:

      opts = [
        inner_backend: Onelist.Storage.Backends.S3,
        encryption_key: key,
        config: s3_config
      ]

      {:ok, metadata} = Encrypted.put(path, content, opts)
      {:ok, decrypted} = Encrypted.get(path, opts)

  ## Configuration

  This backend doesn't have its own configuration - it uses the
  configuration of the inner backend passed via options.

  ## Security Notes

  - The encryption key should never be stored on the server
  - Keys should be derived from user passwords using PBKDF2
  - Each user should have their own unique salt
  - The cloud provider never sees plaintext content
  """

  @behaviour Onelist.Storage.Behaviour

  alias Onelist.Encryption

  require Logger

  @impl true
  def backend_id, do: :encrypted

  @impl true
  def put(path, content, opts) do
    inner_backend = Keyword.fetch!(opts, :inner_backend)
    encryption_key = Keyword.fetch!(opts, :encryption_key)

    case Encryption.encrypt(content, encryption_key) do
      {:ok, encrypted} ->
        # Add .enc suffix to indicate encrypted content
        encrypted_path = encrypted_path(path)

        case inner_backend.put(encrypted_path, encrypted, opts) do
          {:ok, metadata} ->
            {:ok,
             metadata
             |> Map.put(:encrypted, true)
             |> Map.put(:original_path, path)
             |> Map.put(:path, encrypted_path)}

          error ->
            error
        end

      {:error, reason} ->
        Logger.error("Encryption failed: #{inspect(reason)}")
        {:error, {:encryption_failed, reason}}
    end
  end

  @impl true
  def get(_path) do
    # Can't get without options (need encryption key)
    {:error, :encryption_key_required}
  end

  @impl true
  def get(path, opts) do
    inner_backend = Keyword.fetch!(opts, :inner_backend)
    encryption_key = Keyword.fetch!(opts, :encryption_key)

    # Try encrypted path first, then original path
    encrypted_path = encrypted_path(path)

    result =
      case inner_backend.get(encrypted_path, opts) do
        {:ok, _} = success -> success
        {:error, :not_found} -> inner_backend.get(path, opts)
        error -> error
      end

    case result do
      {:ok, encrypted} ->
        case Encryption.decrypt(encrypted, encryption_key) do
          {:ok, decrypted} ->
            {:ok, decrypted}

          {:error, reason} ->
            Logger.error("Decryption failed: #{inspect(reason)}")
            {:error, {:decryption_failed, reason}}
        end

      error ->
        error
    end
  end

  @impl true
  def delete(_path) do
    # Can't delete without options (need inner backend)
    {:error, :inner_backend_required}
  end

  def delete(path, opts) do
    inner_backend = Keyword.fetch!(opts, :inner_backend)

    # Delete both encrypted and original paths
    encrypted_path = encrypted_path(path)

    result1 = inner_backend.delete(encrypted_path)
    result2 = inner_backend.delete(path)

    case {result1, result2} do
      {:ok, _} -> :ok
      {_, :ok} -> :ok
      {error, _} -> error
    end
  end

  @impl true
  def exists?(_path) do
    # Can't check without options
    false
  end

  def exists?(path, opts) do
    inner_backend = Keyword.fetch!(opts, :inner_backend)
    encrypted_path = encrypted_path(path)

    inner_backend.exists?(encrypted_path) || inner_backend.exists?(path)
  end

  @impl true
  def presigned_url(path, opts) do
    # Presigned URLs don't work well with E2EE since the content
    # needs to be decrypted client-side
    inner_backend = Keyword.fetch!(opts, :inner_backend)
    encrypted_path = encrypted_path(path)

    # Return URL to encrypted content - client must decrypt
    inner_backend.presigned_url(encrypted_path, opts)
  end

  @impl true
  def head(_path) do
    {:error, :inner_backend_required}
  end

  def head(path, opts) do
    inner_backend = Keyword.fetch!(opts, :inner_backend)
    encrypted_path = encrypted_path(path)

    case inner_backend.head(encrypted_path) do
      {:ok, metadata} ->
        {:ok, Map.put(metadata, :encrypted, true)}

      {:error, :not_found} ->
        inner_backend.head(path)

      error ->
        error
    end
  end

  # Private functions

  defp encrypted_path(path) do
    if String.ends_with?(path, ".enc") do
      path
    else
      path <> ".enc"
    end
  end
end
