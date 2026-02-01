defmodule Onelist.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_hash, :string, null: false, size: 255
      add :context, :string, null: false, default: "web", size: 32
      add :user_agent, :text, comment: "Storing for security auditing, PII consideration"
      add :ip_address, :string, size: 45, comment: "Stores IP in anonymized form"
      add :device_name, :string, size: 255
      add :location, :string, size: 255, comment: "Generalized location, not precise coordinates"
      add :expires_at, :utc_datetime_usec, null: false
      add :refreshed_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :last_active_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:sessions, [:user_id])
    create unique_index(:sessions, [:token_hash])
    create index(:sessions, [:expires_at])
    create index(:sessions, [:user_id, :revoked_at])
    create index(:sessions, [:expires_at, :revoked_at])
    create index(:sessions, [:user_id, :context, :revoked_at])
  end
end
