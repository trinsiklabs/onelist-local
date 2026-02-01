defmodule Onelist.Repo.Migrations.AddWaitlistNumberToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :waitlist_number, :integer
      add :waitlist_tier, :string  # "headwaters", "tributaries", "public"
    end

    # Index for quick lookups by waitlist number
    create index(:users, [:waitlist_number])
  end
end
