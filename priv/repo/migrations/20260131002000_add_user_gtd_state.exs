defmodule Onelist.Repo.Migrations.AddUserGtdState do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_weekly_review, :utc_datetime_usec
      add :gtd_settings, :map, default: %{}
    end
  end
end
