defmodule Onelist.Repo.Migrations.AddStorageFieldsToAssets do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      # Which backend is the primary source for this asset
      add :primary_backend, :string, default: "local"
      # SHA-256 checksum for integrity verification
      add :checksum, :string
      # Whether the content is end-to-end encrypted
      add :encrypted, :boolean, default: false
      # Thumbnail/stub path for tiered sync (when full asset is in cloud only)
      add :thumbnail_path, :string
    end

    # Index for querying assets by backend
    create index(:assets, [:primary_backend])
  end
end
