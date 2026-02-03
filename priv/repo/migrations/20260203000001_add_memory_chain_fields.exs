defmodule Onelist.Repo.Migrations.AddMemoryChainFields do
  @moduledoc """
  Adds memory chain integrity fields to the memories table.

  This migration supports the R1 memory chain integrity feature:
  - memory_sequence: Position within the agent's chain
  - previous_memory_hash: Link to previous memory in chain
  - memory_hash: SHA256 hash of this memory
  - chain_id: Unique chain identifier (user:id:agent:agent_id)
  - source_entry_hash: Links to entry chain
  - canonical_timestamp: Immutable timestamp for hash calculation

  Also adds:
  - is_current: Whether this memory is the current version (not superseded by re-processing)
  - source_agent_id: Which agent created this memory
  - source_agent_version: Version of the agent
  - content_hash: SHA256 hash of the content

  All chain fields are nullable to support graceful degradation - unchained
  memories (from humans, imports, ignorant agents) remain valid.
  """
  use Ecto.Migration

  def change do
    alter table(:memories) do
      # Memory chain integrity fields (all nullable)
      add :memory_sequence, :integer
      add :previous_memory_hash, :string, size: 64
      add :memory_hash, :string, size: 64
      add :chain_id, :string, size: 128
      add :source_entry_hash, :string, size: 64
      add :canonical_timestamp, :utc_datetime_usec

      # Agent attribution (nullable - human/import memories may not have these)
      add :source_agent_id, :string, size: 64
      add :source_agent_version, :string, size: 32
      add :content_hash, :string, size: 64

      # Current version tracking
      add :is_current, :boolean, default: true
    end

    # Unique constraint: one sequence number per chain
    create unique_index(:memories, [:chain_id, :memory_sequence],
             where: "chain_id IS NOT NULL AND memory_sequence IS NOT NULL",
             name: :memories_chain_sequence_unique_idx
           )

    # Index for chain lookups
    create index(:memories, [:chain_id],
             where: "chain_id IS NOT NULL",
             name: :memories_chain_id_idx
           )

    # Index for hash verification
    create index(:memories, [:memory_hash],
             where: "memory_hash IS NOT NULL",
             name: :memories_memory_hash_idx
           )

    # Index for finding latest in chain
    create index(:memories, [:chain_id, :memory_sequence],
             where: "chain_id IS NOT NULL",
             name: :memories_chain_latest_idx
           )

    # Index for current memories
    create index(:memories, [:user_id, :is_current],
             where: "is_current = true",
             name: :memories_is_current_idx
           )

    # Index for agent attribution
    create index(:memories, [:source_agent_id],
             where: "source_agent_id IS NOT NULL",
             name: :memories_source_agent_idx
           )

    # Index for content hash (duplicate detection)
    create index(:memories, [:content_hash],
             where: "content_hash IS NOT NULL",
             name: :memories_content_hash_idx
           )
  end
end
