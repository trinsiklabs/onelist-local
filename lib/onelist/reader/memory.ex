defmodule Onelist.Reader.Memory do
  @moduledoc """
  Schema for atomic memories extracted from entry content.

  Memories represent discrete pieces of knowledge extracted from entries,
  such as facts, preferences, events, observations, and decisions.
  Each memory includes:
  - The extracted content
  - A memory type classification
  - Confidence score
  - Temporal context (when the memory is valid)
  - Relationships to other memories (supersedes/refines)
  - Extracted entities (people, places, organizations)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @memory_types ~w(fact preference event observation decision)

  schema "memories" do
    field :content, :string
    field :memory_type, :string
    field :confidence, :decimal, default: Decimal.new("1.0")

    # Vector embedding for retrieval
    field :embedding, Pgvector.Ecto.Vector

    # Temporal context
    field :valid_from, :utc_datetime_usec
    field :valid_until, :utc_datetime_usec
    field :temporal_expression, :string
    field :resolved_time, :utc_datetime_usec

    # Source tracking
    field :source_text, :string
    field :chunk_index, :integer

    # Agent attribution
    field :source_agent_id, :string
    field :source_agent_version, :string
    field :content_hash, :string

    # Memory chain integrity (all nullable - unchained memories valid)
    field :memory_sequence, :integer
    field :previous_memory_hash, :string
    field :memory_hash, :string
    field :chain_id, :string
    field :source_entry_hash, :string
    field :canonical_timestamp, :utc_datetime_usec

    # Current version tracking
    field :is_current, :boolean, default: true

    # Entities and metadata
    field :entities, :map, default: %{}
    field :metadata, :map, default: %{}

    # Relationships
    belongs_to :entry, Onelist.Entries.Entry
    belongs_to :user, Onelist.Accounts.User
    belongs_to :supersedes, __MODULE__, foreign_key: :supersedes_id
    belongs_to :refines, __MODULE__, foreign_key: :refines_id

    # Inverse relationships
    has_many :superseded_by, __MODULE__, foreign_key: :supersedes_id
    has_many :refined_by, __MODULE__, foreign_key: :refines_id

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:content, :memory_type, :user_id]
  @optional_fields [
    :entry_id,
    :confidence,
    :embedding,
    :valid_from,
    :valid_until,
    :temporal_expression,
    :resolved_time,
    :source_text,
    :chunk_index,
    :supersedes_id,
    :refines_id,
    :entities,
    :metadata,
    # Agent attribution
    :source_agent_id,
    :source_agent_version,
    :content_hash,
    # Memory chain integrity
    :memory_sequence,
    :previous_memory_hash,
    :memory_hash,
    :chain_id,
    :source_entry_hash,
    :canonical_timestamp,
    # Current version tracking
    :is_current
  ]

  @doc """
  Creates a changeset for a new memory.
  """
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:memory_type, @memory_types)
    |> validate_number(:confidence,
      greater_than_or_equal_to: Decimal.new("0"),
      less_than_or_equal_to: Decimal.new("1")
    )
    |> foreign_key_constraint(:entry_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:supersedes_id)
    |> foreign_key_constraint(:refines_id)
    |> unique_constraint([:chain_id, :memory_sequence], name: :memories_chain_sequence_unique_idx)
  end

  @doc """
  Creates a changeset for updating memory chain fields.
  Used when marking memories as not current during re-processing.
  """
  def chain_changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :memory_sequence,
      :previous_memory_hash,
      :memory_hash,
      :chain_id,
      :source_entry_hash,
      :canonical_timestamp,
      :content_hash,
      :source_agent_id,
      :source_agent_version,
      :is_current
    ])
  end

  @doc """
  Returns the list of valid memory types.

  - `fact` - A verifiable piece of information
  - `preference` - A user preference or opinion
  - `event` - Something that happened at a specific time
  - `observation` - An insight or observation
  - `decision` - A choice or decision made
  """
  def memory_types, do: @memory_types

  @doc """
  Marks a memory as superseded by setting valid_until to the current time.
  """
  def mark_superseded(memory, superseded_by_id \\ nil) do
    attrs = %{valid_until: DateTime.utc_now()}

    attrs =
      if superseded_by_id do
        Map.put(
          attrs,
          :metadata,
          Map.put(memory.metadata || %{}, "superseded_by", superseded_by_id)
        )
      else
        attrs
      end

    memory
    |> cast(attrs, [:valid_until, :metadata])
  end

  @doc """
  Returns true if the memory is currently valid (not superseded).
  """
  def current?(memory) do
    is_nil(memory.valid_until) or DateTime.compare(memory.valid_until, DateTime.utc_now()) == :gt
  end

  @doc """
  Creates a changeset for updating memory embedding.
  """
  def embedding_changeset(memory, embedding) do
    memory
    |> cast(%{embedding: embedding}, [:embedding])
  end

  @doc """
  Returns true if the memory is part of a chain (has chain_id set).
  """
  def chained?(memory) do
    not is_nil(memory.chain_id)
  end

  @doc """
  Returns true if this is a current (not superseded) memory.
  """
  def is_current?(memory) do
    memory.is_current == true
  end
end
