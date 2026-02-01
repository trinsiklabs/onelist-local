defmodule Onelist.Repo.Migrations.CreateSocialAccounts do
  use Ecto.Migration

  def change do
    create table(:social_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_id, :string, null: false
      add :provider_email, :string
      add :provider_username, :string
      add :provider_name, :string
      add :avatar_url, :text
      add :token_data, :text

      timestamps()
    end

    create index(:social_accounts, [:user_id])
    create unique_index(:social_accounts, [:provider, :provider_id], name: :unique_provider_account)
  end
end
