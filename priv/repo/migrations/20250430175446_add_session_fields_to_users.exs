defmodule Onelist.Repo.Migrations.AddSessionFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Fields for managing failed login attempts and account locking
      add :failed_attempts, :integer, default: 0
      add :locked_at, :naive_datetime
      
      # Fields for tracking login information
      add :last_login_at, :naive_datetime
      add :last_login_ip, :string, size: 45, comment: "Stores IP in anonymized form"
      
      # Fields for password reset functionality
      add :reset_token_hash, :string, size: 255
      add :reset_token_created_at, :naive_datetime
      
      # Fields for security and compliance
      add :require_password_change, :boolean, default: false
      add :data_consent_given_at, :naive_datetime, comment: "For GDPR compliance"
    end

    # Create indexes for efficient queries
    create index(:users, [:locked_at])
    create index(:users, [:reset_token_hash])
  end
end
