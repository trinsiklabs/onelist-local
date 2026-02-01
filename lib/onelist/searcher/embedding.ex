defmodule Onelist.Searcher.Embedding do
  @moduledoc """
  Schema for vector embeddings of entry content.

  Embeddings are generated from entry text content and stored using pgvector
  for efficient similarity search. Long content is chunked into overlapping
  segments, each with its own embedding.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "embeddings" do
    field :model_name, :string
    field :model_version, :string
    field :dimensions, :integer
    field :vector, Pgvector.Ecto.Vector

    # Chunking support
    field :chunk_index, :integer, default: 0
    field :chunk_text, :string
    field :chunk_start_offset, :integer
    field :chunk_end_offset, :integer

    # Metadata
    field :token_count, :integer
    field :processing_time_ms, :integer
    field :error_message, :string

    belongs_to :entry, Onelist.Entries.Entry
    belongs_to :representation, Onelist.Entries.Representation

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:entry_id, :model_name, :dimensions, :vector]
  @optional_fields [
    :representation_id,
    :model_version,
    :chunk_index,
    :chunk_text,
    :chunk_start_offset,
    :chunk_end_offset,
    :token_count,
    :processing_time_ms,
    :error_message
  ]

  @doc """
  Creates a changeset for an embedding.
  """
  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:dimensions, greater_than: 0)
    |> validate_number(:chunk_index, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:representation_id)
    |> unique_constraint([:entry_id, :model_name, :chunk_index])
  end

  @doc """
  Creates a changeset for inserting a new embedding.
  """
  def create_changeset(attrs) do
    changeset(%__MODULE__{}, attrs)
  end
end
