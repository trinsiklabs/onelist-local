defmodule Onelist.Entries.Representation do
  @moduledoc """
  Representation schema for different forms of entry content.

  Each entry can have multiple representations (markdown, plaintext, html, etc.)
  allowing the same content to be stored and displayed in different formats.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @representation_types ~w(markdown plaintext html html_public editor_json transcript description ocr summary tags tag_suggestion chat_log chat_message)

  schema "representations" do
    field :version, :integer, default: 1
    field :type, :string
    field :content, :string
    field :storage_path, :string
    field :mime_type, :string
    field :metadata, :map
    field :encrypted, :boolean, default: true

    belongs_to :entry, Onelist.Entries.Entry
    has_many :assets, Onelist.Entries.Asset
    has_many :versions, Onelist.Entries.RepresentationVersion

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new representation.
  """
  def changeset(representation, attrs) do
    representation
    |> cast(attrs, [:type, :content, :storage_path, :mime_type, :metadata, :encrypted, :entry_id])
    |> validate_required([:type])
    |> validate_inclusion(:type, @representation_types)
  end

  @doc """
  Changeset for updating a representation. Increments version.
  """
  def update_changeset(representation, attrs) do
    representation
    |> cast(attrs, [:content, :storage_path, :mime_type, :metadata])
    |> increment_version()
  end

  defp increment_version(changeset) do
    current_version = get_field(changeset, :version) || 1
    put_change(changeset, :version, current_version + 1)
  end

  @doc """
  Returns the list of valid representation types.
  """
  def representation_types, do: @representation_types
end
