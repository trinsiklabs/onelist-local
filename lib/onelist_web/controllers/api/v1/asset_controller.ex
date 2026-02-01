defmodule OnelistWeb.Api.V1.AssetController do
  @moduledoc """
  API controller for asset management.

  Handles file uploads, downloads, and asset operations.
  """

  use OnelistWeb, :controller

  alias Onelist.{Entries, Storage}

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists assets for an entry.

  GET /api/v1/entries/:entry_id/assets
  """
  def index(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id) do
      assets = Storage.list_assets(entry.id)
      render(conn, :index, assets: assets)
    end
  end

  @doc """
  Uploads a new asset for an entry.

  POST /api/v1/entries/:entry_id/assets

  Accepts multipart form data with:
  - `file` - The file to upload (required)
  - `metadata` - JSON metadata (optional)
  - `representation_id` - Associate with representation (optional)
  """
  def create(conn, %{"entry_id" => entry_id} = params) do
    user = conn.assigns.current_user

    with {:ok, entry} <- get_user_entry(user, entry_id),
         {:ok, upload} <- get_upload(params),
         {:ok, content} <- read_upload(upload),
         {:ok, asset} <- store_asset(entry, upload, content, params) do
      conn
      |> put_status(:created)
      |> render(:show, asset: asset)
    end
  end

  @doc """
  Shows a single asset.

  GET /api/v1/assets/:id
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, asset} <- get_user_asset(user, id) do
      render(conn, :show, asset: asset)
    end
  end

  @doc """
  Deletes an asset.

  DELETE /api/v1/entries/:entry_id/assets/:id
  """
  def delete(conn, %{"entry_id" => entry_id, "id" => id}) do
    user = conn.assigns.current_user

    with {:ok, _entry} <- get_user_entry(user, entry_id),
         {:ok, asset} <- get_user_asset(user, id),
         :ok <- Storage.delete(asset) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Gets a presigned download URL for an asset.

  GET /api/v1/assets/:id/download
  """
  def download(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    expires_in = parse_expires_in(params["expires_in"])

    with {:ok, asset} <- get_user_asset(user, id),
         {:ok, url} <- Storage.presigned_url(asset, expires_in: expires_in) do
      render(conn, :download, url: url, asset: asset)
    end
  end

  @doc """
  Gets the thumbnail/stub for an asset (for tiered sync).

  GET /api/v1/assets/:id/thumbnail
  """
  def thumbnail(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, asset} <- get_user_asset(user, id) do
      case asset.thumbnail_path do
        nil ->
          {:error, :not_found}

        path ->
          backend = Storage.primary_backend() |> get_backend_module()

          case backend.presigned_url(path, expires_in: 3600) do
            {:ok, url} -> render(conn, :download, url: url, asset: asset)
            error -> error
          end
      end
    end
  end

  @doc """
  Gets mirror status for an asset.

  GET /api/v1/assets/:id/mirror-status
  """
  def mirror_status(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, asset} <- get_user_asset(user, id) do
      status = Storage.mirror_status(asset)
      render(conn, :mirror_status, asset: asset, mirrors: status)
    end
  end

  # Private functions

  defp get_user_entry(user, entry_id) do
    case Entries.get_user_entry(user, entry_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp get_user_asset(user, asset_id) do
    case Storage.get_asset(asset_id) do
      nil ->
        {:error, :not_found}

      asset ->
        # Verify user owns the entry
        case Entries.get_user_entry(user, asset.entry_id) do
          nil -> {:error, :not_found}
          _entry -> {:ok, asset}
        end
    end
  end

  defp get_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp get_upload(_), do: {:error, :missing_file}

  defp read_upload(%Plug.Upload{path: path}) do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:file_read_error, reason}}
    end
  end

  defp store_asset(entry, upload, content, params) do
    opts = [
      content_type: upload.content_type,
      metadata: parse_metadata(params["metadata"]),
      representation_id: params["representation_id"]
    ]

    Storage.store(entry.id, upload.filename, content, opts)
  end

  defp parse_metadata(nil), do: %{}

  defp parse_metadata(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_metadata(map) when is_map(map), do: map

  defp parse_expires_in(nil), do: 3600

  defp parse_expires_in(value) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, _} when seconds > 0 and seconds <= 86400 -> seconds
      _ -> 3600
    end
  end

  defp parse_expires_in(value) when is_integer(value) and value > 0 and value <= 86400, do: value
  defp parse_expires_in(_), do: 3600

  defp get_backend_module(:local), do: Onelist.Storage.Backends.Local
  defp get_backend_module(:s3), do: Onelist.Storage.Backends.S3
  defp get_backend_module(:gcs), do: Onelist.Storage.Backends.GCS
  defp get_backend_module(_), do: Onelist.Storage.Backends.Local
end
