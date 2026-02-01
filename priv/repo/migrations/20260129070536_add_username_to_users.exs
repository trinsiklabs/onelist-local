defmodule Onelist.Repo.Migrations.AddUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :string, size: 30
    end

    # Case-insensitive unique index using citext or lower()
    create unique_index(:users, ["lower(username)"], name: :users_username_unique_idx)
  end
end
