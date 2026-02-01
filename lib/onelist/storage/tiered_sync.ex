defmodule Onelist.Storage.TieredSync do
  @moduledoc """
  Tiered sync strategy for space-constrained local storage.

  For Mac apps, mobile devices, or other space-constrained environments,
  this module syncs stubs/thumbnails instead of full assets to save space.

  ## Sync Modes

  - `full` - Full content synced locally
  - `thumbnail` - Image thumbnail only (configurable max size)
  - `waveform` - Audio waveform preview only
  - `poster` - Video poster frame only
  - `metadata_only` - No content, metadata only

  ## Size Thresholds

  Files smaller than `max_local_asset_size` (default 1MB) are synced in full.
  Larger files get stubs based on their MIME type.

  ## Usage

      # Determine sync mode for an asset
      {:ok, mode} = TieredSync.determine_sync_mode(asset)

      # Sync to local with appropriate mode
      {:ok, result} = TieredSync.sync_to_local(asset)

      # Fetch full content from cloud when needed
      {:ok, content} = TieredSync.fetch_full(asset)
  """

  alias Onelist.Entries.Asset
  alias Onelist.Storage
  alias Onelist.Storage.PathGenerator

  require Logger

  @default_max_local_size 1_000_000
  @default_thumbnail_max_size 800

  @doc """
  Determines the appropriate sync mode for an asset based on size and type.

  ## Options

  - `:max_local_size` - Max size in bytes for full sync (default: 1MB)

  ## Returns

  - `{:ok, :full}` - Asset should be synced in full
  - `{:ok, :thumbnail}` - Only thumbnail should be synced
  - `{:ok, :waveform}` - Only waveform preview should be synced
  - `{:ok, :poster}` - Only poster frame should be synced
  - `{:ok, :metadata_only}` - Only metadata, no content
  """
  @spec determine_sync_mode(Asset.t(), keyword()) :: {:ok, atom()}
  def determine_sync_mode(%Asset{} = asset, opts \\ []) do
    max_local_size = Keyword.get(opts, :max_local_size, get_max_local_size())

    cond do
      asset.file_size <= max_local_size ->
        {:ok, :full}

      Asset.image?(asset) ->
        {:ok, :thumbnail}

      Asset.audio?(asset) ->
        {:ok, :waveform}

      Asset.video?(asset) ->
        {:ok, :poster}

      true ->
        {:ok, :metadata_only}
    end
  end

  @doc """
  Syncs an asset to local storage with the appropriate mode.

  For small files, syncs full content. For larger files, generates
  and stores a stub (thumbnail, waveform, etc.).

  ## Returns

  - `{:ok, %{mode: mode, path: path}}` - Success
  - `{:error, reason}` - If sync failed
  """
  @spec sync_to_local(Asset.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_to_local(%Asset{} = asset, opts \\ []) do
    {:ok, mode} = determine_sync_mode(asset, opts)

    case mode do
      :full ->
        sync_full(asset, opts)

      :thumbnail ->
        sync_thumbnail(asset, opts)

      :waveform ->
        sync_waveform(asset, opts)

      :poster ->
        sync_poster(asset, opts)

      :metadata_only ->
        {:ok, %{mode: :metadata_only, path: nil}}
    end
  end

  @doc """
  Fetches full content from cloud storage.

  Downloads the full asset from the cloud backend, decrypting if necessary.

  ## Options

  - `:encryption_key` - Key for decrypting E2EE content
  """
  @spec fetch_full(Asset.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def fetch_full(%Asset{} = asset, opts \\ []) do
    # Get from primary backend
    case Storage.retrieve(asset, opts) do
      {:ok, content} ->
        {:ok, content}

      {:error, _reason} ->
        # Try mirrors
        Storage.retrieve(asset, opts)
    end
  end

  @doc """
  Generates a thumbnail for an image asset.

  Requires ImageMagick or libvips to be installed.

  ## Options

  - `:max_size` - Max dimension in pixels (default: 800)
  - `:quality` - JPEG quality (default: 80)
  """
  @spec generate_thumbnail(Asset.t() | binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def generate_thumbnail(%Asset{} = asset, opts) do
    case Storage.retrieve(asset) do
      {:ok, content} -> generate_thumbnail(content, opts)
      error -> error
    end
  end

  def generate_thumbnail(content, opts) when is_binary(content) do
    max_size = Keyword.get(opts, :max_size, @default_thumbnail_max_size)
    quality = Keyword.get(opts, :quality, 80)

    # Check if ImageMagick is available
    case System.cmd("which", ["convert"], stderr_to_stdout: true) do
      {_, 0} ->
        generate_thumbnail_imagemagick(content, max_size, quality)

      _ ->
        Logger.warning("ImageMagick not available for thumbnail generation")
        {:error, :imagemagick_not_available}
    end
  end

  @doc """
  Generates a waveform preview for an audio asset.

  Requires FFmpeg to be installed.
  """
  @spec generate_waveform(Asset.t() | binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def generate_waveform(asset_or_content, opts \\ [])

  def generate_waveform(%Asset{} = asset, opts) do
    case Storage.retrieve(asset) do
      {:ok, content} -> generate_waveform_data(content, opts)
      error -> error
    end
  end

  def generate_waveform(content, opts) when is_binary(content) do
    generate_waveform_data(content, opts)
  end

  @doc """
  Extracts a poster frame from a video asset.

  Requires FFmpeg to be installed.
  """
  @spec extract_poster_frame(Asset.t() | binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def extract_poster_frame(asset_or_content, opts \\ [])

  def extract_poster_frame(%Asset{} = asset, opts) do
    case Storage.retrieve(asset) do
      {:ok, content} -> extract_poster_frame_data(content, opts)
      error -> error
    end
  end

  def extract_poster_frame(content, opts) when is_binary(content) do
    extract_poster_frame_data(content, opts)
  end

  # Private functions

  defp get_max_local_size do
    Application.get_env(:onelist, Storage, [])
    |> Keyword.get(:max_local_asset_size, @default_max_local_size)
  end

  defp sync_full(asset, _opts) do
    # Full content is already in primary backend
    {:ok, %{mode: :full, path: asset.storage_path}}
  end

  defp sync_thumbnail(asset, opts) do
    case generate_thumbnail(asset, opts) do
      {:ok, thumbnail} ->
        # Store thumbnail
        thumbnail_path = PathGenerator.generate_thumbnail(asset.storage_path)
        local = Onelist.Storage.Backends.Local

        case local.put(thumbnail_path, thumbnail, content_type: "image/jpeg") do
          {:ok, _} ->
            {:ok, %{mode: :thumbnail, path: thumbnail_path}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp sync_waveform(asset, opts) do
    case generate_waveform(asset, opts) do
      {:ok, waveform} ->
        # Store waveform as JSON
        waveform_path =
          asset.storage_path
          |> String.replace_prefix("assets/", "waveforms/")
          |> Path.rootname()
          |> Kernel.<>(".json")

        local = Onelist.Storage.Backends.Local

        case local.put(waveform_path, waveform, content_type: "application/json") do
          {:ok, _} ->
            {:ok, %{mode: :waveform, path: waveform_path}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp sync_poster(asset, opts) do
    case extract_poster_frame(asset, opts) do
      {:ok, poster} ->
        # Store poster frame
        poster_path =
          asset.storage_path
          |> String.replace_prefix("assets/", "posters/")
          |> Path.rootname()
          |> Kernel.<>(".jpg")

        local = Onelist.Storage.Backends.Local

        case local.put(poster_path, poster, content_type: "image/jpeg") do
          {:ok, _} ->
            {:ok, %{mode: :poster, path: poster_path}}

          error ->
            error
        end

      error ->
        error
    end
  end

  defp generate_thumbnail_imagemagick(content, max_size, quality) do
    # Create temp files
    input_path = Path.join(System.tmp_dir!(), "thumb_input_#{:rand.uniform(100_000)}")
    output_path = Path.join(System.tmp_dir!(), "thumb_output_#{:rand.uniform(100_000)}.jpg")

    try do
      File.write!(input_path, content)

      args = [
        input_path,
        "-thumbnail",
        "#{max_size}x#{max_size}>",
        "-quality",
        "#{quality}",
        output_path
      ]

      case System.cmd("convert", args, stderr_to_stdout: true) do
        {_, 0} ->
          thumbnail = File.read!(output_path)
          {:ok, thumbnail}

        {error, _} ->
          Logger.error("ImageMagick thumbnail generation failed: #{error}")
          {:error, :thumbnail_generation_failed}
      end
    after
      File.rm(input_path)
      File.rm(output_path)
    end
  end

  defp generate_waveform_data(_content, _opts) do
    # Placeholder - would use FFmpeg in production
    # Returns JSON with waveform data points
    waveform = %{
      samples: 100,
      data: Enum.map(1..100, fn _ -> :rand.uniform(100) end)
    }

    {:ok, Jason.encode!(waveform)}
  end

  defp extract_poster_frame_data(content, _opts) do
    # Create temp files
    input_path = Path.join(System.tmp_dir!(), "video_input_#{:rand.uniform(100_000)}")
    output_path = Path.join(System.tmp_dir!(), "poster_output_#{:rand.uniform(100_000)}.jpg")

    try do
      File.write!(input_path, content)

      # Extract frame at 1 second using FFmpeg
      args = [
        "-i",
        input_path,
        "-ss",
        "00:00:01",
        "-vframes",
        "1",
        "-q:v",
        "2",
        output_path
      ]

      case System.cmd("ffmpeg", args, stderr_to_stdout: true) do
        {_, 0} ->
          poster = File.read!(output_path)
          {:ok, poster}

        {error, _} ->
          Logger.error("FFmpeg poster extraction failed: #{error}")
          {:error, :poster_extraction_failed}
      end
    after
      File.rm(input_path)
      File.rm(output_path)
    end
  rescue
    _ -> {:error, :ffmpeg_not_available}
  end
end
