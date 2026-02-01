defmodule Onelist.Storage.Backends.GCS do
  @moduledoc """
  Google Cloud Storage backend.

  Uses the Google Cloud Storage JSON API for object operations.

  ## Configuration

      config :onelist, Onelist.Storage.Backends.GCS,
        bucket: "my-bucket",
        project_id: "my-project"

  ## Authentication

  Authentication is handled via service account credentials.
  Set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable to
  point to your service account JSON key file.

  Alternatively, configure credentials directly:

      config :onelist, Onelist.Storage.Backends.GCS,
        bucket: "my-bucket",
        project_id: "my-project",
        credentials: %{
          "type" => "service_account",
          "client_email" => "...",
          "private_key" => "..."
        }
  """

  @behaviour Onelist.Storage.Behaviour

  require Logger

  @base_url "https://storage.googleapis.com"
  @upload_url "https://storage.googleapis.com/upload/storage/v1"

  @impl true
  def backend_id, do: :gcs

  @impl true
  def put(path, content, opts \\ []) do
    config = get_config()
    content_type = Keyword.get(opts, :content_type, MIME.from_path(path))

    url = "#{@upload_url}/b/#{config.bucket}/o?uploadType=media&name=#{URI.encode(path)}"

    headers = [
      {"Authorization", "Bearer #{get_access_token(config)}"},
      {"Content-Type", content_type}
    ]

    case HTTPoison.post(url, content, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        metadata = Jason.decode!(body)

        {:ok,
         %{
           path: path,
           size: String.to_integer(metadata["size"]),
           content_type: metadata["contentType"],
           checksum: metadata["md5Hash"],
           etag: metadata["etag"],
           backend: :gcs
         }}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("GCS put failed for #{path}: status=#{status}, body=#{body}")
        {:error, {:gcs_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("GCS put failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get(path) do
    get(path, [])
  end

  @impl true
  def get(path, opts) do
    config = get_config()
    url = "#{@base_url}/#{config.bucket}/#{URI.encode(path)}"

    headers = [
      {"Authorization", "Bearer #{get_access_token(config)}"}
    ]

    # Add range header if specified
    headers =
      case Keyword.get(opts, :range) do
        nil -> headers
        {start_byte, end_byte} -> [{"Range", "bytes=#{start_byte}-#{end_byte}"} | headers]
      end

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: status, body: body}} when status in [200, 206] ->
        {:ok, body}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: 403}} ->
        {:error, :access_denied}

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("GCS get failed for #{path}: status=#{status}")
        {:error, {:gcs_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("GCS get failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(path) do
    config = get_config()
    url = "#{@base_url}/storage/v1/b/#{config.bucket}/o/#{URI.encode(path, &URI.char_unreserved?/1)}"

    headers = [
      {"Authorization", "Bearer #{get_access_token(config)}"}
    ]

    case HTTPoison.delete(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        # Already deleted
        :ok

      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        Logger.error("GCS delete failed for #{path}: status=#{status}")
        {:error, {:gcs_error, status, body}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("GCS delete failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def exists?(path) do
    case head(path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @impl true
  def presigned_url(path, opts \\ []) do
    config = get_config()
    expires_in = Keyword.get(opts, :expires_in, 3600)
    method = Keyword.get(opts, :method, :get)

    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second)
    expires_unix = DateTime.to_unix(expires_at)

    http_method = method |> to_string() |> String.upcase()

    # Build the string to sign
    resource = "/#{config.bucket}/#{path}"

    string_to_sign = """
    #{http_method}


    #{expires_unix}
    #{resource}
    """

    # Sign with service account private key
    case sign_url(string_to_sign, config) do
      {:ok, signature} ->
        encoded_sig = Base.encode64(signature) |> URI.encode_www_form()

        url =
          "#{@base_url}#{resource}?GoogleAccessId=#{config.client_email}&Expires=#{expires_unix}&Signature=#{encoded_sig}"

        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def head(path) do
    config = get_config()
    url = "#{@base_url}/storage/v1/b/#{config.bucket}/o/#{URI.encode(path, &URI.char_unreserved?/1)}"

    headers = [
      {"Authorization", "Bearer #{get_access_token(config)}"}
    ]

    case HTTPoison.get(url, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        metadata = Jason.decode!(body)

        {:ok,
         %{
           size: String.to_integer(metadata["size"]),
           content_type: metadata["contentType"],
           last_modified: parse_timestamp(metadata["updated"]),
           etag: metadata["etag"],
           backend: :gcs
         }}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:gcs_error, status, nil}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  # Private functions

  defp get_config do
    app_config = Application.get_env(:onelist, __MODULE__, [])

    %{
      bucket: Keyword.fetch!(app_config, :bucket),
      project_id: Keyword.get(app_config, :project_id),
      credentials: Keyword.get(app_config, :credentials),
      client_email: get_client_email(app_config)
    }
  end

  defp get_client_email(config) do
    case Keyword.get(config, :credentials) do
      %{"client_email" => email} -> email
      _ -> nil
    end
  end

  defp get_access_token(config) do
    # If Goth is available, use it for token management
    if Code.ensure_loaded?(Goth) do
      case Goth.fetch(Onelist.Goth) do
        {:ok, %{token: token}} -> token
        _ -> fetch_token_manually(config)
      end
    else
      fetch_token_manually(config)
    end
  end

  defp fetch_token_manually(_config) do
    # Fallback: read from environment or return empty
    # In production, Goth should handle this
    System.get_env("GCS_ACCESS_TOKEN", "")
  end

  defp sign_url(string_to_sign, config) do
    case config.credentials do
      %{"private_key" => private_key} ->
        try do
          [pem_entry] = :public_key.pem_decode(private_key)
          key = :public_key.pem_entry_decode(pem_entry)
          signature = :public_key.sign(string_to_sign, :sha256, key)
          {:ok, signature}
        rescue
          e -> {:error, e}
        end

      _ ->
        {:error, :no_credentials}
    end
  end

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end
end
