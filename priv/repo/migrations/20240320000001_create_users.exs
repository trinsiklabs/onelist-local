defmodule Onelist.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :naive_datetime
      add :password_changed_at, :naive_datetime
      add :email_verified, :boolean, default: false
      add :email_verification_token, :string
      add :name, :string
      add :verified_at, :utc_datetime

      timestamps()
    end

    create unique_index(:users, [:email])
  end
end 