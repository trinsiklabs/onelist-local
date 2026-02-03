defmodule Onelist.Repo.Migrations.CreateFeederTables do
  use Ecto.Migration

  def change do
    # External Integrations - stores connection credentials and sync state
    create table(:external_integrations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Source identification
      # 'rss', 'evernote', 'notion', etc.
      add :source_type, :string, null: false
      # User-friendly name
      add :source_name, :string

      # Authentication (encrypted at application layer)
      add :credentials, :map, null: false, default: %{}

      # Sync configuration
      add :sync_enabled, :boolean, default: true
      add :sync_frequency_minutes, :integer, default: 60
      # Source-specific filters (notebooks, tags, folders)
      add :sync_filter, :map

      # Sync state
      add :last_sync_at, :utc_datetime
      # 'success', 'partial', 'failed', 'syncing'
      add :last_sync_status, :string
      add :last_sync_error, :text
      # {entries_created, entries_updated, errors}
      add :last_sync_stats, :map

      # Source-specific state
      # {update_count, next_cursor, last_modified, etc.}
      add :sync_cursor, :map

      # Metadata
      # {workspace_name, account_email, etc.}
      add :metadata, :map

      timestamps()
    end

    create index(:external_integrations, [:user_id])
    create index(:external_integrations, [:source_type])
    create index(:external_integrations, [:sync_enabled, :last_sync_at])

    create unique_index(:external_integrations, [:user_id, :source_type, :source_name],
             name: :external_integrations_user_source_name_idx
           )

    # Import Jobs - tracks one-time import jobs (file uploads)
    create table(:import_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Job identification
      # 'evernote_enex', 'notion_export', 'obsidian_vault'
      add :source_type, :string, null: false
      # User-provided or generated name
      add :job_name, :string

      # File info
      # Path to uploaded file (if applicable)
      add :file_path, :string
      add :file_size_bytes, :bigint

      # Job configuration
      # {skip_duplicates, folder_as_tags, resolve_links, etc.}
      add :options, :map

      # Progress tracking
      # pending, processing, completed, failed, cancelled
      add :status, :string, null: false, default: "pending"
      add :progress_percent, :integer, default: 0
      add :items_total, :integer
      add :items_processed, :integer, default: 0
      add :items_succeeded, :integer, default: 0
      add :items_failed, :integer, default: 0

      # Results
      add :entries_created, :integer, default: 0
      add :assets_uploaded, :integer, default: 0
      add :tags_created, :integer, default: 0
      # [{item, error, recoverable}, ...]
      add :errors, {:array, :map}

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

      add :integration_id,
          references(:external_integrations, type: :binary_id, on_delete: :delete_all)

      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false

      # Source identification
      add :source_type, :string, null: false
      # GUID, page_id, file path, etc.
      add :source_id, :string, null: false
      # For hierarchy tracking
      add :source_parent_id, :string

      # Sync metadata
      add :source_updated_at, :utc_datetime
      add :last_synced_at, :utc_datetime
      # Content hash for change detection
      add :sync_hash, :string

      timestamps()
    end

    create index(:source_entry_mappings, [:entry_id])
    create index(:source_entry_mappings, [:source_type, :source_id])

    create unique_index(:source_entry_mappings, [:user_id, :source_type, :source_id],
             name: :source_entry_mappings_user_source_idx
           )
  end
end
