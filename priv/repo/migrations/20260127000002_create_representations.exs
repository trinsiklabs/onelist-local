defmodule Onelist.Repo.Migrations.CreateRepresentations do
  use Ecto.Migration

  def change do
    create table(:representations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :integer, null: false, default: 1
      add :type, :string, null: false, size: 32
      add :content, :text
      add :storage_path, :string, size: 500
      add :mime_type, :string, size: 127
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:representations, [:entry_id])
    create index(:representations, [:entry_id, :type])
  end
end
