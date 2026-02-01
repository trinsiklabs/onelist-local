defmodule Onelist.Repo.Migrations.CreateFeederTables do
  use Ecto.Migration

  def change do
    # External Integrations - stores connection credentials and sync state
    create table(:external_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Source identification
      add :source_type, :string, null: false  # 'rss', 'evernote', 'notion', etc.
      add :source_name, :string               # User-friendly name

      # Authentication (encrypted at application layer)
      add :credentials, :map, null: false, default: %{}

      # Sync configuration
      add :sync_enabled, :boolean, default: true
      add :sync_frequency_minutes, :integer, default: 60
      add :sync_filter, :map  # Source-specific filters (notebooks, tags, folders)

      # Sync state
      add :last_sync_at, :utc_datetime
      add :last_sync_status, :string  # 'success', 'partial', 'failed', 'syncing'
      add :last_sync_error, :text
      add :last_sync_stats, :map  # {entries_created, entries_updated, errors}

      # Source-specific state
      add :sync_cursor, :map  # {update_count, next_cursor, last_modified, etc.}

      # Metadata
      add :metadata, :map  # {workspace_name, account_email, etc.}

      timestamps()
    end

    create index(:external_integrations, [:user_id])
    create index(:external_integrations, [:source_type])
    create index(:external_integrations, [:sync_enabled, :last_sync_at])
    create unique_index(:external_integrations, [:user_id, :source_type, :source_name],
      name: :external_integrations_user_source_name_idx)

    # Import Jobs - tracks one-time import jobs (file uploads)
    create table(:import_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Job identification
      add :source_type, :string, null: false  # 'evernote_enex', 'notion_export', 'obsidian_vault'
      add :job_name, :string                  # User-provided or generated name

      # File info
      add :file_path, :string                 # Path to uploaded file (if applicable)
      add :file_size_bytes, :bigint

      # Job configuration
      add :options, :map  # {skip_duplicates, folder_as_tags, resolve_links, etc.}

      # Progress tracking
      add :status, :string, null: false, default: "pending"  # pending, processing, completed, failed, cancelled
      add :progress_percent, :integer, default: 0
      add :items_total, :integer
      add :items_processed, :integer, default: 0
      add :items_succeeded, :integer, default: 0
      add :items_failed, :integer, default: 0

      # Results
      add :entries_created, :integer, default: 0
      add :assets_uploaded, :integer, default: 0
      add :tags_created, :integer, default: 0
      add :errors, {:array, :map}  # [{item, error, recoverable}, ...]

      # Timestamps
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # Link to created entries (for rollback if needed)
      add :entry_ids, {:array, :binary_id}

      timestamps()
    end

    create index(:import_jobs, [:user_id])
    create index(:import_jobs, [:status])
    create index(:import_jobs, [:inserted_at])

    # Source Entry Mappings - tracks mapping between source IDs and Onelist entry IDs
    create table(:source_entry_mappings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :integration_id, references(:external_integrations, type: :binary_id, on_delete: :delete_all)
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false

      # Source identification
      add :source_type, :string, null: false
      add :source_id, :string, null: false    # GUID, page_id, file path, etc.
      add :source_parent_id, :string          # For hierarchy tracking

      # Sync metadata
      add :source_updated_at, :utc_datetime
      add :last_synced_at, :utc_datetime
      add :sync_hash, :string                 # Content hash for change detection

      timestamps()
    end

    create index(:source_entry_mappings, [:entry_id])
    create index(:source_entry_mappings, [:source_type, :source_id])
    create unique_index(:source_entry_mappings, [:user_id, :source_type, :source_id],
      name: :source_entry_mappings_user_source_idx)
  end
end
