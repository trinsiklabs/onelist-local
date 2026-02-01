defmodule Onelist.Workers.ThumbnailWorker do
  @moduledoc """
  Oban worker for generating thumbnails and stubs asynchronously.

  Processes assets that need thumbnail/stub generation for tiered sync.
  Uses ImageMagick for images and FFmpeg for video poster frames.

  ## Job Args

  - `asset_id` - The asset to process
  - `action` - "generate_thumbnail", "generate_waveform", "generate_poster"

  ## Dependencies

  - ImageMagick (convert) for image thumbnails
  - FFmpeg for video poster frames and audio waveforms
  """

  use Oban.Worker,
    queue: :storage,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue]]

  alias Onelist.Repo
  alias Onelist.Entries.Asset
  alias Onelist.Storage
  alias Onelist.Storage.TieredSync

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id, "action" => action}}) do
    case Repo.get(Asset, asset_id) do
      nil ->
        Logger.info("Asset #{asset_id} not found, skipping thumbnail generation")
        :ok

      asset ->
        process_asset(asset, action)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id}}) do
    # Auto-detect action based on asset type
    case Repo.get(Asset, asset_id) do
      nil ->
        :ok

      asset ->
        action = determine_action(asset)
        process_asset(asset, action)
    end
  end

  defp process_asset(asset, action) do
    result =
      case action do
        "generate_thumbnail" ->
          generate_and_store_thumbnail(asset)

        "generate_waveform" ->
          generate_and_store_waveform(asset)

        "generate_poster" ->
          generate_and_store_poster(asset)

        _ ->
          Logger.warning("Unknown thumbnail action: #{action}")
          :ok
      end

    case result do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp determine_action(asset) do
    cond do
      Asset.image?(asset) -> "generate_thumbnail"
      Asset.audio?(asset) -> "generate_waveform"
      Asset.video?(asset) -> "generate_poster"
      true -> nil
    end
  end

  defp generate_and_store_thumbnail(asset) do
    case TieredSync.generate_thumbnail(asset, max_size: 800, quality: 80) do
      {:ok, thumbnail} ->
        # Generate thumbnail path
        thumbnail_path = thumbnail_path(asset)

        # Store locally
        local = Onelist.Storage.Backends.Local

        case local.put(thumbnail_path, thumbnail, content_type: "image/jpeg") do
          {:ok, _} ->
            # Update asset with thumbnail path
            update_asset_thumbnail(asset, thumbnail_path)

          error ->
            error
        end

      {:error, :imagemagick_not_available} ->
        Logger.warning("ImageMagick not available, skipping thumbnail for asset #{asset.id}")
        :ok

      error ->
        error
    end
  end

  defp generate_and_store_waveform(asset) do
    case TieredSync.generate_waveform(asset) do
      {:ok, waveform} ->
        waveform_path = waveform_path(asset)
        local = Onelist.Storage.Backends.Local

        case local.put(waveform_path, waveform, content_type: "application/json") do
          {:ok, _} ->
            update_asset_thumbnail(asset, waveform_path)

          error ->
            error
        end

      error ->
        error
    end
  end

  defp generate_and_store_poster(asset) do
    case TieredSync.extract_poster_frame(asset) do
      {:ok, poster} ->
        poster_path = poster_path(asset)
        local = Onelist.Storage.Backends.Local

        case local.put(poster_path, poster, content_type: "image/jpeg") do
          {:ok, _} ->
            update_asset_thumbnail(asset, poster_path)

          error ->
            error
        end

      {:error, :ffmpeg_not_available} ->
        Logger.warning("FFmpeg not available, skipping poster for asset #{asset.id}")
        :ok

      error ->
        error
    end
  end

  defp thumbnail_path(asset) do
    asset.storage_path
    |> String.replace_prefix("assets/", "thumbnails/")
    |> Path.rootname()
    |> Kernel.<>(".jpg")
  end

  defp waveform_path(asset) do
    asset.storage_path
    |> String.replace_prefix("assets/", "waveforms/")
    |> Path.rootname()
    |> Kernel.<>(".json")
  end

  defp poster_path(asset) do
    asset.storage_path
    |> String.replace_prefix("assets/", "posters/")
    |> Path.rootname()
    |> Kernel.<>(".jpg")
  end

  defp update_asset_thumbnail(asset, thumbnail_path) do
    asset
    |> Asset.update_changeset(%{thumbnail_path: thumbnail_path})
    |> Repo.update()
  end

  @doc """
  Queues thumbnail generation for an asset.
  """
  @spec queue_thumbnail(Asset.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def queue_thumbnail(%Asset{} = asset) do
    action = determine_action(asset)

    if action do
      %{asset_id: asset.id, action: action}
      |> new()
      |> Oban.insert()
    else
      {:ok, nil}
    end
  end

  @doc """
  Queues thumbnail generation for all assets of an entry.
  """
  @spec queue_entry_thumbnails(String.t()) :: :ok
  def queue_entry_thumbnails(entry_id) do
    assets = Storage.list_assets(entry_id)

    Enum.each(assets, fn asset ->
      if asset.file_size > get_max_local_size() do
        queue_thumbnail(asset)
      end
    end)

    :ok
  end

  defp get_max_local_size do
    Application.get_env(:onelist, Storage, [])
    |> Keyword.get(:max_local_asset_size, 1_000_000)
  end
end
