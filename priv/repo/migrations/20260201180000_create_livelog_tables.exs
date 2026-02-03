defmodule Onelist.Repo.Migrations.CreateLivelogTables do
  use Ecto.Migration

  def change do
    # Redacted messages for Livelog display
    create table(:livelog_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_entry_id, references(:entries, type: :binary_id, on_delete: :nilify_all)
      add :source_message_id, :string

      # Message content (already redacted)
      add :role, :string, null: false
      add :content, :text, null: false
      add :original_timestamp, :utc_datetime_usec, null: false

      # Redaction metadata
      add :redaction_applied, :boolean, default: true
      add :patterns_matched, {:array, :string}, default: []
      add :blocked, :boolean, default: false
      add :block_reason, :string

      # Display metadata
      add :session_label, :string
      add :sequence_in_session, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:livelog_messages, [:original_timestamp])
    create index(:livelog_messages, [:source_entry_id])
    create index(:livelog_messages, [:inserted_at])
    create unique_index(:livelog_messages, [:source_message_id])

    # Redaction audit log
    create table(:livelog_audit_log, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :livelog_message_id,
          references(:livelog_messages, type: :binary_id, on_delete: :delete_all)

      add :original_content_hash, :string, null: false
      add :redacted_content_hash, :string, null: false
      add :action, :string, null: false
      add :layer, :integer
      add :patterns_fired, {:array, :string}, default: []
      add :processing_time_us, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:livelog_audit_log, [:livelog_message_id])
    create index(:livelog_audit_log, [:inserted_at])
    create index(:livelog_audit_log, [:action])
  end
end
