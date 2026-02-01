defmodule Onelist.Entries.Entry do
  @moduledoc """
  Entry schema for storing user content.

  Entries are generic containers for information with different types
  (note, memory, photo, video) and sources (manual, web_clip, api).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @entry_types ~w(note memory photo video task decision chat_log conversation config job sprint project phase proposal deliverable milestone)
  @source_types ~w(manual web_clip api openclaw river_session)

  schema "entries" do
    field :public_id, :string
    field :title, :string
    field :version, :integer, default: 1
    field :entry_type, :string
    field :source_type, :string
    field :public, :boolean, default: false
    field :content_created_at, :utc_datetime_usec
    field :metadata, :map

    # Trusted Memory hash chain (for AI accounts)
    field :sequence_number, :integer
    field :previous_entry_hash, :string
    field :entry_hash, :string
    field :canonical_timestamp, :utc_datetime_usec

    belongs_to :user, Onelist.Accounts.User
    has_many :representations, Onelist.Entries.Representation
    has_many :assets, Onelist.Entries.Asset
    has_many :outgoing_links, Onelist.Entries.EntryLink, foreign_key: :source_entry_id
    has_many :incoming_links, Onelist.Entries.EntryLink, foreign_key: :target_entry_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new entry.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :title, :entry_type, :source_type, :public, :content_created_at, :metadata,
      # Trusted memory fields
      :sequence_number, :previous_entry_hash, :entry_hash, :canonical_timestamp
    ])
    |> validate_required([:entry_type])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_inclusion(:source_type, @source_types ++ [nil])
    |> put_public_id()
  end

  @doc """
  Changeset for updating an entry. Increments version.
  """
  def update_changeset(entry, attrs) do
    entry
    |> cast(attrs, [:title, :entry_type, :source_type, :public, :content_created_at, :metadata])
    |> validate_inclusion(:entry_type, @entry_types)
    |> validate_inclusion(:source_type, @source_types ++ [nil])
    |> increment_version()
  end

  defp put_public_id(changeset) do
    if get_field(changeset, :public_id) do
      changeset
    else
      put_change(changeset, :public_id, generate_public_id())
    end
  end

  defp generate_public_id do
    # Generate a URL-safe nanoid-style ID (21 characters)
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 21)
  end

  defp increment_version(changeset) do
    current_version = get_field(changeset, :version) || 1
    put_change(changeset, :version, current_version + 1)
  end

  @doc """
  Returns the list of valid entry types.
  """
  def entry_types, do: @entry_types

  @doc """
  Returns the list of valid source types.
  """
  def source_types, do: @source_types
end
