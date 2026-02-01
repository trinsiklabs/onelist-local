defmodule Onelist.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false, size: 255
      add :key_hash, :string, null: false, size: 255
      add :prefix, :string, null: false, size: 8
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:api_keys, [:user_id])
    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:prefix])
    create index(:api_keys, [:user_id, :revoked_at])
  end
end
