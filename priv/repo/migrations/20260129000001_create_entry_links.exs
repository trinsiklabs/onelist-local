defmodule Onelist.Repo.Migrations.CreateEntryLinks do
  use Ecto.Migration

  def change do
    create table(:entry_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source_entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :target_entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :link_type, :string, null: false, size: 50
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:entry_links, [:source_entry_id])
    create index(:entry_links, [:target_entry_id])
    create index(:entry_links, [:link_type])
    create unique_index(:entry_links, [:source_entry_id, :target_entry_id, :link_type])
  end
end
