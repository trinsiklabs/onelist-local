defmodule Onelist.Repo.Migrations.CreateRiverSessions do
  use Ecto.Migration

  def change do
    create table(:river_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :last_message_at, :utc_datetime_usec, null: false
      add :message_count, :integer, default: 0
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:river_sessions, [:user_id])
    create index(:river_sessions, [:user_id, :last_message_at])

    create table(:river_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :session_id, references(:river_sessions, type: :binary_id, on_delete: :delete_all),
        null: false

      # "user" or "river"
      add :role, :string, null: false
      add :content, :text, null: false
      add :tokens_used, :integer
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:river_messages, [:session_id])
    create index(:river_messages, [:session_id, :inserted_at])
  end
end
