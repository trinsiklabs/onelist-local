defmodule Onelist.Repo.Migrations.AddEncryptedToRepresentations do
  use Ecto.Migration

  def change do
    alter table(:representations) do
      add :encrypted, :boolean, default: true, null: false
    end

    # Index for quick lookup of html_public representations
    create index(:representations, [:entry_id, :type],
      where: "type = 'html_public'",
      name: :representations_html_public_idx)
  end
end
