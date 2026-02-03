defmodule Onelist.Repo.Migrations.CreateUserStorageConfigs do
  use Ecto.Migration

  def change do
    create table(:user_storage_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      # Provider type: s3, r2, b2, gcs, spaces, wasabi, minio
      add :provider, :string, null: false
      # User's bucket name
      add :bucket_name, :string, null: false
      # Bucket region (e.g., us-east-1, auto for R2)
      add :region, :string
      # Custom endpoint URL (for S3-compatible services)
      add :endpoint, :string

      # Encrypted credentials (access_key_id + secret_access_key)
      # Encrypted at application level before storage
      add :credentials, :binary, null: false

      # Whether this config is currently active
      add :is_active, :boolean, default: true
      # Last successful connection verification
      add :verified_at, :utc_datetime_usec
      # Provider-specific settings (e.g., account_id for R2)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # Only one active storage config per user
    create unique_index(:user_storage_configs, [:user_id],
             where: "is_active = true",
             name: :user_storage_configs_active_user_unique
           )

    # Index for finding configs by provider
    create index(:user_storage_configs, [:provider])
  end
end
