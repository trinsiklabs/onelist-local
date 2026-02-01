defmodule Onelist.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Atomic memory content
      add :content, :text, null: false
      add :memory_type, :string, null: false
      add :confidence, :decimal, precision: 3, scale: 2, default: 1.0

      # Vector for retrieval
      add :embedding, :vector, size: 1536

      # Temporal context
      add :valid_from, :utc_datetime_usec
      add :valid_until, :utc_datetime_usec
      add :temporal_expression, :string
      add :resolved_time, :utc_datetime_usec

      # Source tracking
      add :source_text, :text
      add :chunk_index, :integer

      # Relationships (self-referential)
      add :supersedes_id, references(:memories, type: :binary_id, on_delete: :nilify_all)
      add :refines_id, references(:memories, type: :binary_id, on_delete: :nilify_all)

      # Entities and metadata
      add :entities, :map, default: %{}
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:memories, [:user_id])
    create index(:memories, [:entry_id])
    create index(:memories, [:user_id, :memory_type])
    create index(:memories, [:user_id, :valid_until], where: "valid_until IS NULL")
    create index(:memories, [:supersedes_id], where: "supersedes_id IS NOT NULL")
  end
end
