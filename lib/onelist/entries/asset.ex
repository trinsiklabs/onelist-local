defmodule Onelist.Entries.Asset do
  @moduledoc """
  Asset schema for binary attachments and resources.

  Assets can be associated with an entry directly or with a specific
  representation of an entry (e.g., images embedded in markdown).

  ## Storage Fields

  - `storage_path` - Path in the primary backend
  - `primary_backend` - Which backend holds the authoritative copy (local, s3, gcs)
  - `checksum` - SHA-256 hash for integrity verification
  - `encrypted` - Whether content is end-to-end encrypted
  - `thumbnail_path` - Path to thumbnail/stub for tiered sync

  ## Mirrors

  Assets can be mirrored to multiple backends via the `mirrors` association.
  See `Onelist.Entries.AssetMirror` for mirror tracking.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @backend_values ~w(local s3 gcs)

  schema "assets" do
    field :filename, :string
    field :mime_type, :string
    field :storage_path, :string
    field :file_size, :integer
    field :metadata, :map

    # Storage backend fields
    field :primary_backend, :string, default: "local"
    field :checksum, :string
    field :encrypted, :boolean, default: false
    field :thumbnail_path, :string

    belongs_to :entry, Onelist.Entries.Entry
    belongs_to :representation, Onelist.Entries.Representation

    has_many :mirrors, Onelist.Entries.AssetMirror

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new asset.
  """
  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [
      :entry_id,
      :filename,
      :mime_type,
      :storage_path,
      :file_size,
      :metadata,
      :representation_id,
      :primary_backend,
      :checksum,
      :encrypted,
      :thumbnail_path
    ])
    |> validate_required([:entry_id, :filename, :mime_type, :storage_path])
    |> validate_length(:filename, max: 255)
    |> validate_length(:mime_type, max: 127)
    |> validate_length(:storage_path, max: 500)
    |> validate_inclusion(:primary_backend, @backend_values)
    |> foreign_key_constraint(:entry_id)
  end

  @doc """
  Changeset for updating asset metadata.
  """
  def update_changeset(asset, attrs) do
    asset
    |> cast(attrs, [:filename, :metadata, :thumbnail_path])
    |> validate_length(:filename, max: 255)
  end

  @doc """
  Returns true if the asset content is encrypted.
  """
  def encrypted?(%__MODULE__{encrypted: encrypted}), do: encrypted == true

  @doc """
  Returns true if this is an image asset.
  """
  def image?(%__MODULE__{mime_type: mime_type}) do
    String.starts_with?(mime_type || "", "image/")
  end

  @doc """
  Returns true if this is a video asset.
  """
  def video?(%__MODULE__{mime_type: mime_type}) do
    String.starts_with?(mime_type || "", "video/")
  end

  @doc """
  Returns true if this is an audio asset.
  """
  def audio?(%__MODULE__{mime_type: mime_type}) do
    String.starts_with?(mime_type || "", "audio/")
  end
end
