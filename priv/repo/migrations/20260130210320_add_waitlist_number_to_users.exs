defmodule Onelist.Repo.Migrations.AddWaitlistNumberToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :waitlist_number, :integer
      # "headwaters", "tributaries", "public"
      add :waitlist_tier, :string
    end

    # Index for quick lookups by waitlist number
    create index(:users, [:waitlist_number])
  end
end
