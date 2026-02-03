defmodule Onelist.Repo.Migrations.AddTrustedMemoryFields do
  use Ecto.Migration

  def change do
    # Add account type and trusted memory fields to users
    alter table(:users) do
      # "human" or "ai"
      add :account_type, :string, default: "human"
      add :trusted_memory_mode, :boolean, default: false
      add :trusted_memory_enabled_at, :utc_datetime_usec
    end

    # Add hash chain fields to entries for integrity verification
    alter table(:entries) do
      add :sequence_number, :integer
      add :previous_entry_hash, :string
      add :entry_hash, :string
      add :canonical_timestamp, :utc_datetime_usec
    end

    # Index for efficient chain verification
    create index(:entries, [:user_id, :sequence_number],
             unique: true,
             where: "sequence_number IS NOT NULL"
           )

    # Audit log for tracking all memory operations
    create table(:memory_audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :entry_id, references(:entries, type: :binary_id, on_delete: :nilify_all)
      # create, read, attempted_edit, attempted_delete
      add :action, :string, null: false
      # who performed action
      add :actor, :string
      # success, denied
      add :outcome, :string
      add :details, :map

      timestamps()
    end

    create index(:memory_audit_log, [:user_id])
    create index(:memory_audit_log, [:entry_id])
    create index(:memory_audit_log, [:action])
  end
end
