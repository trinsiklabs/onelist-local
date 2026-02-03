defmodule Onelist.Repo.Migrations.CreateAssets do
  use Ecto.Migration

  def change do
    create table(:assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entry_id, references(:entries, type: :binary_id, on_delete: :delete_all), null: false

      add :representation_id,
          references(:representations, type: :binary_id, on_delete: :nilify_all)

      add :filename, :string, null: false, size: 255
      add :mime_type, :string, null: false, size: 127
      add :storage_path, :string, null: false, size: 500
      add :file_size, :bigint
      add :metadata, :map

      timestamps(type: :utc_datetime_usec)
    end

    create index(:assets, [:entry_id])
    create index(:assets, [:representation_id])
    create index(:assets, [:entry_id, :mime_type])
  end
end
