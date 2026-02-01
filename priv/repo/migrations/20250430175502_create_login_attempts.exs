defmodule Onelist.Repo.Migrations.CreateLoginAttempts do
  use Ecto.Migration

  def change do
    create table(:login_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, size: 255
      add :ip_address, :string, size: 45, comment: "Stores IP in anonymized form"
      add :successful, :boolean, default: false
      add :user_agent, :text
      add :reason, :string, size: 255, comment: "Reason for failure if applicable"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:login_attempts, [:email, :inserted_at])
    create index(:login_attempts, [:ip_address, :inserted_at])
    create index(:login_attempts, [:successful])
  end
end
