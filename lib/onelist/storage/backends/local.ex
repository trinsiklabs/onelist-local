defmodule Onelist.Storage.Backends.Local do
  @moduledoc """
  Local filesystem storage backend.

  Production-ready filesystem storage for self-hosted and on-premises deployments.
  Stores files in a configurable root directory with full CRUD operations.

  ## Configuration

      config :onelist, Onelist.Storage.Backends.Local,
        root_path: "priv/static/uploads"

  ## Use Cases

  - Privacy compliance (data stays on-premises)
  - Air-gapped environments
  - Edge deployments
  - Development and testing
  - Primary storage with cloud mirror backup
  """

  @behaviour Onelist.Storage.Behaviour

  require Logger

  @impl true
  def backend_id, do: :local

  @impl true
  def put(path, content, opts \\ []) do
    full_path = full_path(path)
    content_type = Keyword.get(opts, :content_type, MIME.from_path(path))

    with :ok <- ensure_directory(full_path),
         :ok <- File.write(full_path, content) do
      checksum = compute_checksum(content)

      {:ok,
       %{
         path: path,
         size: byte_size(content),
         content_type: content_type,
         checksum: checksum,
         backend: :local
       }}
    else
      {:error, reason} ->
        Logger.error("Local storage put failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get(path) do
    full_path = full_path(path)

    case File.read(full_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Local storage get failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get(path, opts) do
    case Keyword.get(opts, :range) do
      nil ->
        get(path)

      {start_byte, end_byte} ->
        get_range(path, start_byte, end_byte)
    end
  end

  @impl true
  def delete(path) do
    full_path = full_path(path)

    case File.rm(full_path) do
      :ok ->
        cleanup_empty_directories(full_path)
        :ok

      {:error, :enoent} ->
        # Already deleted, consider success
        :ok

      {:error, reason} ->
        Logger.error("Local storage delete failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def exists?(path) do
    full_path = full_path(path)
    File.exists?(full_path)
  end

  @impl true
  def presigned_url(path, opts \\ []) do
    # For local storage, we generate a token-based URL
    # that can be validated by the application
    expires_in = Keyword.get(opts, :expires_in, 3600)
    method = Keyword.get(opts, :method, :get)

    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)

    token = generate_access_token(path, method, expires_at)

    # Return a URL that the application can handle
    # The actual URL format depends on your endpoint configuration
    base_url = Application.get_env(:onelist, OnelistWeb.Endpoint)[:url][:host] || "localhost"
    scheme = if base_url == "localhost", do: "http", else: "https"
    port = Application.get_env(:onelist, OnelistWeb.Endpoint)[:http][:port] || 4000

    url =
      if base_url == "localhost" do
        "#{scheme}://#{base_url}:#{port}/storage/download?path=#{URI.encode(path)}&token=#{token}"
      else
        "#{scheme}://#{base_url}/storage/download?path=#{URI.encode(path)}&token=#{token}"
      end

    {:ok, url}
  end

  @impl true
  def head(path) do
    full_path = full_path(path)

    case File.stat(full_path) do
      {:ok, %File.Stat{size: size, mtime: mtime}} ->
        {:ok,
         %{
           size: size,
           content_type: MIME.from_path(path),
           last_modified: erl_to_datetime(mtime),
           backend: :local
         }}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Public helpers

  @doc """
  Returns the full filesystem path for a storage path.
  """
  @spec full_path(String.t()) :: String.t()
  def full_path(path) do
    root = root_path()
    Path.join(root, path)
  end

  @doc """
  Returns the configured root path for local storage.
  """
  @spec root_path() :: String.t()
  def root_path do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(:root_path, "priv/static/uploads")
  end

  @doc """
  Validates an access token for presigned URL access.
  """
  @spec validate_access_token(String.t(), String.t(), atom()) ::
          :ok | {:error, :invalid_token | :expired}
  def validate_access_token(path, token, method \\ :get) do
    case decode_access_token(token) do
      {:ok, %{path: ^path, method: ^method, expires_at: expires_at}} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          :ok
        else
          {:error, :expired}
        end

      {:ok, _} ->
        {:error, :invalid_token}

      {:error, _} ->
        {:error, :invalid_token}
    end
  end

  # Private functions

  defp ensure_directory(full_path) do
    dir = Path.dirname(full_path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, :eexist} -> :ok
      error -> error
    end
  end

  defp cleanup_empty_directories(full_path) do
    dir = Path.dirname(full_path)
    root = root_path()

    # Only clean up directories within our root
    if String.starts_with?(dir, root) and dir != root do
      case File.rmdir(dir) do
        :ok ->
          # Recursively clean parent if empty
          cleanup_empty_directories(dir)

        {:error, _} ->
          # Directory not empty or other error, stop
          :ok
      end
    end
  end

  defp get_range(path, start_byte, end_byte) do
    full_path = full_path(path)

    case File.open(full_path, [:read, :binary]) do
      {:ok, file} ->
        try do
          :file.position(file, start_byte)
          length = end_byte - start_byte + 1
          data = IO.binread(file, length)

          if is_binary(data) do
            {:ok, data}
          else
            {:error, :read_error}
          end
        after
          File.close(file)
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp compute_checksum(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  defp generate_access_token(path, method, expires_at) do
    secret = Application.get_env(:onelist, OnelistWeb.Endpoint)[:secret_key_base]

    data = %{
      path: path,
      method: method,
      expires_at: DateTime.to_iso8601(expires_at)
    }

    payload = Jason.encode!(data)
    signature = :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64()

    Base.url_encode64(payload) <> "." <> signature
  end

  defp decode_access_token(token) do
    secret = Application.get_env(:onelist, OnelistWeb.Endpoint)[:secret_key_base]

    case String.split(token, ".") do
      [payload_b64, signature] ->
        with {:ok, payload} <- Base.url_decode64(payload_b64),
             expected_sig <- :crypto.mac(:hmac, :sha256, secret, payload) |> Base.url_encode64(),
             true <- Plug.Crypto.secure_compare(signature, expected_sig),
             {:ok, data} <- Jason.decode(payload),
             {:ok, expires_at, _} <- DateTime.from_iso8601(data["expires_at"]) do
          {:ok,
           %{
             path: data["path"],
             method: String.to_existing_atom(data["method"]),
             expires_at: expires_at
           }}
        else
          _ -> {:error, :invalid_token}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp erl_to_datetime({{year, month, day}, {hour, minute, second}}) do
    {:ok, datetime} = NaiveDateTime.new(year, month, day, hour, minute, second)
    DateTime.from_naive!(datetime, "Etc/UTC")
  end
end
