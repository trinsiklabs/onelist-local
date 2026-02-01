defmodule Onelist.Repo.Migrations.CreateSearcherTables do
  use Ecto.Migration

  def change do
    # Enable pgvector extension for vector similarity search
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    # Create embeddings table for storing vector embeddings
    create table(:embeddings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :representation_id, references(:representations, type: :binary_id, on_delete: :delete_all)

      # Embedding data
      add :model_name, :string, null: false, size: 255
      add :model_version, :string, size: 50
      add :dimensions, :integer, null: false

      # Chunking support
      add :chunk_index, :integer, default: 0
      add :chunk_text, :text
      add :chunk_start_offset, :integer
      add :chunk_end_offset, :integer

      # Metadata
      add :token_count, :integer
      add :processing_time_ms, :integer
      add :error_message, :text

      timestamps(type: :utc_datetime_usec)
    end

    # Add vector column separately (Ecto doesn't support pgvector type directly in create table)
    execute "ALTER TABLE embeddings ADD COLUMN vector vector(1536)",
            "ALTER TABLE embeddings DROP COLUMN vector"

    create index(:embeddings, [:entry_id])
    create index(:embeddings, [:model_name])
    create unique_index(:embeddings, [:entry_id, :model_name, :chunk_index])

    # IVFFlat index for vector similarity search (good for MVP, HNSW better for production)
    # Note: IVFFlat requires data to be present before creating, so we create it with minimal lists
    execute """
            CREATE INDEX embeddings_vector_idx ON embeddings
            USING ivfflat (vector vector_cosine_ops) WITH (lists = 100)
            """,
            "DROP INDEX IF EXISTS embeddings_vector_idx"

    # Create search_configs table for user search preferences
    create table(:search_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Model settings
      add :embedding_model, :string, null: false, default: "text-embedding-3-small", size: 255
      add :embedding_dimensions, :integer, null: false, default: 1536

      # Search defaults
      add :default_search_type, :string, default: "hybrid", size: 50
      add :semantic_weight, :decimal, precision: 3, scale: 2, default: 0.7
      add :keyword_weight, :decimal, precision: 3, scale: 2, default: 0.3

      # Processing settings
      add :auto_embed_on_create, :boolean, default: true
      add :auto_embed_on_update, :boolean, default: true
      add :max_chunk_tokens, :integer, default: 500
      add :chunk_overlap_tokens, :integer, default: 50

      # Rate limiting
      add :daily_embedding_limit, :integer
      add :embeddings_today, :integer, default: 0
      add :limit_reset_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:search_configs, [:user_id])

    # Create embedding_jobs table for tracking embedding status
    create table(:embedding_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :oban_job_id, :bigint

      add :status, :string, null: false, default: "pending", size: 50
      add :priority, :integer, default: 0

      add :attempts, :integer, default: 0
      add :max_attempts, :integer, default: 3
      add :last_error, :text

      add :scheduled_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:embedding_jobs, [:entry_id])
    create index(:embedding_jobs, [:status])
  end
end
