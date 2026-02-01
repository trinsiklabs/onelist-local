defmodule Onelist.Storage.PathGenerator do
  @moduledoc """
  Generates storage paths for assets.

  Paths are organized by date and entry for efficient storage and retrieval:

      assets/{year}/{month}/{day}/{entry_id_prefix}/{uuid}_{sanitized_filename}

  Example: `assets/2026/01/28/abc123de/550e8400-e29b_photo.jpg`

  This structure provides:
  - Date-based partitioning for efficient listing and cleanup
  - Entry grouping for related assets
  - UUID prefix to ensure uniqueness
  - Original filename preservation for user reference
  """

  @doc """
  Generates a storage path for a new asset.

  ## Parameters

  - `entry_id` - The entry UUID this asset belongs to
  - `filename` - Original filename (will be sanitized)
  - `opts` - Options
    - `:timestamp` - Custom timestamp (defaults to now)
    - `:uuid` - Custom UUID (defaults to generated)
    - `:prefix` - Custom path prefix (defaults to "assets")

  ## Examples

      iex> PathGenerator.generate("550e8400-e29b-41d4-a716-446655440000", "My Photo.jpg")
      "assets/2026/01/28/550e8400/a1b2c3d4-e5f6_my-photo.jpg"

      iex> PathGenerator.generate(entry_id, "file.txt", prefix: "thumbnails")
      "thumbnails/2026/01/28/550e8400/a1b2c3d4-e5f6_file.txt"
  """
  @spec generate(String.t(), String.t(), keyword()) :: String.t()
  def generate(entry_id, filename, opts \\ []) do
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())
    uuid = Keyword.get(opts, :uuid, generate_short_uuid())
    prefix = Keyword.get(opts, :prefix, "assets")

    date_path = date_path(timestamp)
    entry_prefix = entry_prefix(entry_id)
    safe_filename = sanitize_filename(filename)

    Path.join([prefix, date_path, entry_prefix, "#{uuid}_#{safe_filename}"])
  end

  @doc """
  Generates a path for a thumbnail/stub version of an asset.

  ## Examples

      iex> PathGenerator.generate_thumbnail("assets/2026/01/28/abc/uuid_photo.jpg")
      "thumbnails/2026/01/28/abc/uuid_photo.jpg"
  """
  @spec generate_thumbnail(String.t()) :: String.t()
  def generate_thumbnail(original_path) do
    original_path
    |> String.replace_prefix("assets/", "thumbnails/")
  end

  @doc """
  Extracts the date components from a storage path.

  ## Examples

      iex> PathGenerator.extract_date("assets/2026/01/28/abc/file.jpg")
      {:ok, ~D[2026-01-28]}

      iex> PathGenerator.extract_date("invalid/path")
      {:error, :invalid_path}
  """
  @spec extract_date(String.t()) :: {:ok, Date.t()} | {:error, :invalid_path}
  def extract_date(path) do
    case String.split(path, "/") do
      [_prefix, year, month, day | _rest] ->
        with {y, ""} <- Integer.parse(year),
             {m, ""} <- Integer.parse(month),
             {d, ""} <- Integer.parse(day),
             {:ok, date} <- Date.new(y, m, d) do
          {:ok, date}
        else
          _ -> {:error, :invalid_path}
        end

      _ ->
        {:error, :invalid_path}
    end
  end

  @doc """
  Sanitizes a filename for safe storage.

  - Converts to lowercase
  - Replaces spaces and special characters with hyphens
  - Removes consecutive hyphens
  - Preserves the file extension
  - Limits length to 100 characters

  ## Examples

      iex> PathGenerator.sanitize_filename("My Photo (2024).JPG")
      "my-photo-2024.jpg"

      iex> PathGenerator.sanitize_filename("résumé.pdf")
      "resume.pdf"
  """
  @spec sanitize_filename(String.t()) :: String.t()
  def sanitize_filename(filename) do
    # Handle dotfiles (e.g., ".txt" treated as hidden file with no extension)
    # In this case, we want to treat it as a regular extension
    original_ext = Path.extname(filename)

    {name, ext} =
      if original_ext == "" and String.starts_with?(filename, ".") do
        # Dotfile: treat the whole thing as the extension
        {"", String.downcase(filename)}
      else
        {Path.basename(filename, original_ext), String.downcase(original_ext)}
      end

    # Sanitize the name
    sanitized_name =
      name
      |> String.downcase()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^a-z0-9\s\-_]/u, "")
      |> String.replace(~r/[\s_]+/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")
      |> String.slice(0, 100 - String.length(ext))

    # Handle empty names
    sanitized_name =
      if sanitized_name == "" do
        "file"
      else
        sanitized_name
      end

    sanitized_name <> ext
  end

  # Private functions

  defp date_path(%DateTime{} = timestamp) do
    year = timestamp.year |> Integer.to_string()
    month = timestamp.month |> Integer.to_string() |> String.pad_leading(2, "0")
    day = timestamp.day |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{year}/#{month}/#{day}"
  end

  defp entry_prefix(entry_id) when is_binary(entry_id) do
    # Take first 8 characters of the UUID for grouping
    String.slice(entry_id, 0, 8)
  end

  defp generate_short_uuid do
    # Generate a shorter UUID (first 8 + last 4 chars of a UUID)
    uuid = Ecto.UUID.generate()
    String.slice(uuid, 0, 8) <> "-" <> String.slice(uuid, -4, 4)
  end
end
