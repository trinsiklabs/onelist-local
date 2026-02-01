defmodule Onelist.Repo.Migrations.CreateRepresentationVersions do
  use Ecto.Migration

  def change do
    create table(:representation_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :representation_id, references(:representations, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :content, :text  # Full snapshot (null if diff)
      add :diff, :text     # Diff from previous (null if snapshot)
      add :version, :integer, null: false  # representations.version before this change
      add :version_type, :string, null: false, default: "diff"  # "snapshot" or "diff"
      add :byte_size, :integer  # Size of content or diff for tracking

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:representation_versions, [:representation_id])
    create index(:representation_versions, [:representation_id, :version])
    create index(:representation_versions, [:representation_id, :inserted_at])
    create index(:representation_versions, [:user_id])

    # Constraint: either content OR diff must be present, not both
    create constraint(:representation_versions, :content_or_diff_present,
      check: "(content IS NOT NULL AND diff IS NULL) OR (content IS NULL AND diff IS NOT NULL)"
    )
  end
end
