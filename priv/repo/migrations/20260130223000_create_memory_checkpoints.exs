defmodule Onelist.Repo.Migrations.CreateMemoryCheckpoints do
  use Ecto.Migration

  def change do
    create table(:memory_checkpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Checkpoint type: "rollback", "snapshot", "recovery"
      add :checkpoint_type, :string, null: false

      # Human-readable reason for the checkpoint
      add :reason, :text

      # Entries with sequence_number > after_sequence are ignored
      add :after_sequence, :integer, null: false

      # Who created this checkpoint
      # "human", "system"
      add :created_by, :string, null: false

      # Who authorized it (required for rollbacks)
      add :authorized_by, :string

      # Is this checkpoint currently active?
      add :active, :boolean, default: true, null: false

      # When was it deactivated (for recovery)
      add :deactivated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:memory_checkpoints, [:user_id])
    create index(:memory_checkpoints, [:user_id, :active])
    create index(:memory_checkpoints, [:checkpoint_type])
  end
end
