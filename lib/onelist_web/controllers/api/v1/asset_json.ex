defmodule OnelistWeb.Api.V1.AssetJSON do
  @moduledoc """
  JSON rendering for Asset resources.
  """

  alias Onelist.Entries.Asset

  @doc """
  Renders a list of assets.
  """
  def index(%{assets: assets}) do
    %{data: for(asset <- assets, do: data(asset))}
  end

  @doc """
  Renders a single asset.
  """
  def show(%{asset: asset}) do
    %{data: data(asset)}
  end

  @doc """
  Renders a download URL response.
  """
  def download(%{url: url, asset: asset}) do
    %{
      data: %{
        id: asset.id,
        filename: asset.filename,
        download_url: url,
        mime_type: asset.mime_type,
        file_size: asset.file_size,
        encrypted: asset.encrypted
      }
    }
  end

  @doc """
  Renders mirror status.
  """
  def mirror_status(%{asset: asset, mirrors: mirrors}) do
    %{
      data: %{
        id: asset.id,
        filename: asset.filename,
        primary_backend: asset.primary_backend,
        mirrors:
          Enum.map(mirrors, fn {backend, status} ->
            %{
              backend: backend,
              status: status.status,
              sync_mode: status.sync_mode,
              encrypted: status.encrypted,
              synced_at: status.synced_at,
              error_message: status.error_message,
              retry_count: status.retry_count
            }
          end)
      }
    }
  end

  defp data(%Asset{} = asset) do
    %{
      id: asset.id,
      filename: asset.filename,
      mime_type: asset.mime_type,
      file_size: asset.file_size,
      storage_path: asset.storage_path,
      primary_backend: asset.primary_backend,
      checksum: asset.checksum,
      encrypted: asset.encrypted,
      has_thumbnail: asset.thumbnail_path != nil,
      entry_id: asset.entry_id,
      representation_id: asset.representation_id,
      metadata: asset.metadata,
      inserted_at: asset.inserted_at,
      updated_at: asset.updated_at
    }
  end
end
