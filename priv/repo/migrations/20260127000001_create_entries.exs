defmodule Onelist.Repo.Migrations.CreateEntries do
  use Ecto.Migration

  def change do
    create table(:entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :public_id, :string, null: false, size: 21
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :text
      add :version, :integer, null: false, default: 1
      add :entry_type, :string, null: false, size: 32
      add :source_type, :string, size: 32
      add :public, :boolean, null: false, default: false
      add :content_created_at, :utc_datetime_usec
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:entries, [:public_id])
    create index(:entries, [:user_id])
    create index(:entries, [:user_id, :entry_type])
    create index(:entries, [:user_id, :public])
    create index(:entries, [:user_id, :inserted_at])
    create index(:entries, [:entry_type])
    create index(:entries, [:content_created_at])
  end
end
