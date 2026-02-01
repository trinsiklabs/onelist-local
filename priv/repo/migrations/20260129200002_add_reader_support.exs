defmodule Onelist.Repo.Migrations.AddReaderSupport do
  use Ecto.Migration

  def change do
    alter table(:search_configs) do
      # Reader settings
      add :auto_process_on_create, :boolean, default: true
      add :auto_process_on_update, :boolean, default: true
      add :extraction_model, :string, default: "gpt-4o-mini"
      add :reader_settings, :map, default: %{}
    end
  end
end
