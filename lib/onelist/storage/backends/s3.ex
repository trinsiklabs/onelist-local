defmodule Onelist.Storage.Backends.S3 do
  @moduledoc """
  S3-compatible storage backend.

  Supports AWS S3 and S3-compatible services:
  - AWS S3
  - Cloudflare R2 (no egress fees)
  - Backblaze B2 (low cost)
  - DigitalOcean Spaces
  - MinIO (self-hosted)
  - Wasabi (no egress fees)

  ## Configuration

  ### AWS S3
      config :onelist, Onelist.Storage.Backends.S3,
        bucket: "my-bucket",
        region: "us-east-1",
        access_key_id: "AKIA...",
        secret_access_key: "..."

  ### Cloudflare R2
      config :onelist, Onelist.Storage.Backends.S3,
        bucket: "my-bucket",
        region: "auto",
        endpoint: "https://ACCOUNT_ID.r2.cloudflarestorage.com",
        access_key_id: "...",
        secret_access_key: "..."

  ### Backblaze B2
      config :onelist, Onelist.Storage.Backends.S3,
        bucket: "my-bucket",
        region: "us-west-004",
        endpoint: "https://s3.us-west-004.backblazeb2.com",
        access_key_id: "...",
        secret_access_key: "..."

  ## S3-Compatible Service Endpoints

  | Service | Endpoint Format |
  |---------|-----------------|
  | AWS S3 | (default, no endpoint needed) |
  | Cloudflare R2 | `https://{account_id}.r2.cloudflarestorage.com` |
  | Backblaze B2 | `https://s3.{region}.backblazeb2.com` |
  | DigitalOcean Spaces | `https://{region}.digitaloceanspaces.com` |
  | MinIO | User-configured |
  | Wasabi | `https://s3.{region}.wasabisys.com` |
  """

  @behaviour Onelist.Storage.Behaviour

  require Logger

  @impl true
  def backend_id, do: :s3

  @impl true
  def put(path, content, opts \\ []) do
    config = get_config(opts)
    content_type = Keyword.get(opts, :content_type, MIME.from_path(path))

    s3_opts = [
      content_type: content_type,
      acl: :private
    ]

    # Add custom metadata if provided
    s3_opts =
      case Keyword.get(opts, :metadata) do
        nil -> s3_opts
        meta -> Keyword.put(s3_opts, :meta, meta)
      end

    request =
      ExAws.S3.put_object(config.bucket, path, content, s3_opts)
      |> add_config(config)

    case ExAws.request(request) do
      {:ok, %{status_code: status}} when status in [200, 201] ->
        checksum = compute_checksum(content)

        {:ok,
         %{
           path: path,
           size: byte_size(content),
           content_type: content_type,
           checksum: checksum,
           backend: :s3,
           bucket: config.bucket
         }}

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("S3 put failed for #{path}: status=#{status}, body=#{inspect(body)}")
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        Logger.error("S3 put failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get(path) do
    get(path, [])
  end

  @impl true
  def get(path, opts) do
    config = get_config(opts)

    request =
      case Keyword.get(opts, :range) do
        nil ->
          ExAws.S3.get_object(config.bucket, path)

        {start_byte, end_byte} ->
          ExAws.S3.get_object(config.bucket, path, range: "bytes=#{start_byte}-#{end_byte}")
      end
      |> add_config(config)

    case ExAws.request(request) do
      {:ok, %{body: body, status_code: status}} when status in [200, 206] ->
        {:ok, body}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: 403}} ->
        {:error, :access_denied}

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("S3 get failed for #{path}: status=#{status}")
        {:error, {:s3_error, status, body}}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("S3 get failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def delete(path) do
    delete(path, [])
  end

  def delete(path, opts) do
    config = get_config(opts)

    request =
      ExAws.S3.delete_object(config.bucket, path)
      |> add_config(config)

    case ExAws.request(request) do
      {:ok, %{status_code: status}} when status in [200, 204] ->
        :ok

      {:ok, %{status_code: 404}} ->
        # Already deleted
        :ok

      {:ok, %{status_code: status, body: body}} ->
        Logger.error("S3 delete failed for #{path}: status=#{status}")
        {:error, {:s3_error, status, body}}

      {:error, reason} ->
        Logger.error("S3 delete failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def exists?(path) do
    exists?(path, [])
  end

  def exists?(path, opts) do
    case head(path, opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @impl true
  def presigned_url(path, opts \\ []) do
    config = get_config(opts)
    expires_in = Keyword.get(opts, :expires_in, 3600)
    method = Keyword.get(opts, :method, :get)

    query_params = []

    # Add content-type for PUT requests
    query_params =
      case {method, Keyword.get(opts, :content_type)} do
        {:put, ct} when is_binary(ct) ->
          Keyword.put(query_params, :"content-type", ct)

        _ ->
          query_params
      end

    s3_opts = [
      expires_in: expires_in,
      query_params: query_params
    ]

    # Build the config for presigning
    presign_config = build_presign_config(config)

    url =
      case method do
        :get ->
          ExAws.S3.presigned_url(presign_config, :get, config.bucket, path, s3_opts)

        :put ->
          ExAws.S3.presigned_url(presign_config, :put, config.bucket, path, s3_opts)
      end

    case url do
      {:ok, url} -> {:ok, url}
      error -> error
    end
  end

  @impl true
  def head(path) do
    head(path, [])
  end

  def head(path, opts) do
    config = get_config(opts)

    request =
      ExAws.S3.head_object(config.bucket, path)
      |> add_config(config)

    case ExAws.request(request) do
      {:ok, %{headers: headers, status_code: 200}} ->
        metadata = parse_headers(headers)
        {:ok, Map.put(metadata, :backend, :s3)}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: 403}} ->
        {:error, :access_denied}

      {:ok, %{status_code: status}} ->
        {:error, {:s3_error, status, nil}}

      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("S3 head failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Creates a backend configuration from options or user storage config.

  This is used by the UserBucket module to create per-user S3 configurations.
  """
  @spec build_config(map()) :: map()
  def build_config(params) do
    %{
      bucket: params[:bucket] || params["bucket"],
      region: params[:region] || params["region"] || "us-east-1",
      endpoint: params[:endpoint] || params["endpoint"],
      access_key_id: params[:access_key_id] || params["access_key_id"],
      secret_access_key: params[:secret_access_key] || params["secret_access_key"]
    }
  end

  # Private functions

  defp get_config(opts) do
    # Allow passing custom config via opts (for BYOB)
    case Keyword.get(opts, :config) do
      nil ->
        app_config = Application.get_env(:onelist, __MODULE__, [])

        %{
          bucket: Keyword.fetch!(app_config, :bucket),
          region: Keyword.get(app_config, :region, "us-east-1"),
          endpoint: Keyword.get(app_config, :endpoint),
          access_key_id: Keyword.fetch!(app_config, :access_key_id),
          secret_access_key: Keyword.fetch!(app_config, :secret_access_key)
        }

      config when is_map(config) ->
        config
    end
  end

  defp add_config(request, config) do
    ex_aws_config = [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    ]

    # Add custom endpoint for S3-compatible services
    ex_aws_config =
      case config.endpoint do
        nil ->
          ex_aws_config

        endpoint ->
          uri = URI.parse(endpoint)

          ex_aws_config
          |> Keyword.put(:host, uri.host)
          |> Keyword.put(:scheme, uri.scheme || "https")
          |> Keyword.put(:port, uri.port || 443)
      end

    Map.put(request, :config, ex_aws_config)
  end

  defp build_presign_config(config) do
    base = [
      access_key_id: config.access_key_id,
      secret_access_key: config.secret_access_key,
      region: config.region
    ]

    case config.endpoint do
      nil ->
        ExAws.Config.new(:s3, base)

      endpoint ->
        uri = URI.parse(endpoint)

        base
        |> Keyword.put(:host, uri.host)
        |> Keyword.put(:scheme, uri.scheme || "https")
        |> Keyword.put(:port, uri.port || 443)
        |> then(&ExAws.Config.new(:s3, &1))
    end
  end

  defp parse_headers(headers) do
    headers_map =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
      |> Map.new()

    %{
      size: parse_content_length(headers_map["content-length"]),
      content_type: headers_map["content-type"],
      last_modified: parse_last_modified(headers_map["last-modified"]),
      etag: headers_map["etag"]
    }
  end

  defp parse_content_length(nil), do: nil

  defp parse_content_length(value) do
    case Integer.parse(value) do
      {size, _} -> size
      :error -> nil
    end
  end

  defp parse_last_modified(nil), do: nil

  defp parse_last_modified(value) do
    # Parse RFC1123 date format: "Sun, 06 Nov 1994 08:49:37 GMT"
    # Using Calendar.strftime format
    case parse_rfc1123(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end

  defp parse_rfc1123(value) do
    # Simple RFC1123 parser
    # Format: "Day, DD Mon YYYY HH:MM:SS GMT"
    months = %{
      "Jan" => 1, "Feb" => 2, "Mar" => 3, "Apr" => 4,
      "May" => 5, "Jun" => 6, "Jul" => 7, "Aug" => 8,
      "Sep" => 9, "Oct" => 10, "Nov" => 11, "Dec" => 12
    }

    case Regex.run(~r/\w+, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT/, value) do
      [_, day, month, year, hour, min, sec] ->
        with {d, _} <- Integer.parse(day),
             {y, _} <- Integer.parse(year),
             {h, _} <- Integer.parse(hour),
             {m, _} <- Integer.parse(min),
             {s, _} <- Integer.parse(sec),
             month_num when month_num != nil <- months[month],
             {:ok, naive} <- NaiveDateTime.new(y, month_num, d, h, m, s) do
          {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  rescue
    _ -> {:error, :parse_error}
  end

  defp compute_checksum(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
