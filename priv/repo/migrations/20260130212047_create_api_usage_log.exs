defmodule Onelist.Repo.Migrations.CreateApiUsageLog do
  use Ecto.Migration

  def change do
    create table(:api_usage_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      # "openai", "anthropic"
      add :provider, :string, null: false
      add :model, :string
      # "memory_extraction", "embedding", "tag_suggestion", etc.
      add :operation, :string
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      # Estimated cost
      add :cost_cents, :decimal, precision: 10, scale: 4
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :entry_id, references(:entries, type: :binary_id, on_delete: :nilify_all)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:api_usage_log, [:provider])
    create index(:api_usage_log, [:user_id])
    create index(:api_usage_log, [:inserted_at])
  end
end
