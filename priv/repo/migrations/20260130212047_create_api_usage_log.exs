defmodule Onelist.Repo.Migrations.CreateApiUsageLog do
  use Ecto.Migration

  def change do
    create table(:api_usage_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false  # "openai", "anthropic"
      add :model, :string
      add :operation, :string  # "memory_extraction", "embedding", "tag_suggestion", etc.
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :total_tokens, :integer, default: 0
      add :cost_cents, :decimal, precision: 10, scale: 4  # Estimated cost
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
