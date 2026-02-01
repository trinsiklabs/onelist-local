defmodule Onelist.Repo.Migrations.CreateAssetMirrors do
  use Ecto.Migration

  def change do
    create table(:asset_mirrors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :asset_id, references(:assets, on_delete: :delete_all, type: :binary_id), null: false

      # Backend identifier (s3, local, gcs, r2, b2, etc.)
      add :backend, :string, null: false
      # Path within this backend
      add :storage_path, :string, null: false
      # Sync status: pending, syncing, synced, failed
      add :status, :string, null: false, default: "pending"
      # Sync mode: full, stub, thumbnail (for tiered sync)
      add :sync_mode, :string, default: "full"
      # Whether content is E2EE in this backend
      add :encrypted, :boolean, default: false

      # Tracking
      add :synced_at, :utc_datetime_usec
      add :error_message, :text
      add :retry_count, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Unique constraint: one mirror per asset per backend
    create unique_index(:asset_mirrors, [:asset_id, :backend])
    # Index for finding mirrors by status (for retry worker)
    create index(:asset_mirrors, [:status])
    # Index for finding mirrors by backend
    create index(:asset_mirrors, [:backend])
  end
end
