defmodule Onelist.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create index(:tags, [:user_id])
    create unique_index(:tags, [:user_id, :name], name: :tags_user_id_name_unique)
    create index(:tags, [:user_id, :name])

    # Create entry_tags join table
    create table(:entry_tags, primary_key: false) do
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create index(:entry_tags, [:entry_id])
    create index(:entry_tags, [:tag_id])
    create unique_index(:entry_tags, [:entry_id, :tag_id], name: :entry_tags_entry_tag_unique)
  end
end
