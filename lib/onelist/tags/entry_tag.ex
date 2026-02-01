defmodule Onelist.Tags.EntryTag do
  @moduledoc """
  EntryTag schema for the join table between entries and tags.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "entry_tags" do
    belongs_to :entry, Onelist.Entries.Entry
    belongs_to :tag, Onelist.Tags.Tag

    field :inserted_at, :utc_datetime_usec, read_after_writes: true
  end

  @doc """
  Changeset for creating an entry-tag association.
  """
  def changeset(entry_tag, attrs) do
    entry_tag
    |> cast(attrs, [:entry_id, :tag_id])
    |> validate_required([:entry_id, :tag_id])
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:entry_id, :tag_id], name: :entry_tags_entry_tag_unique)
  end
end
