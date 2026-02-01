defmodule Onelist.Repo.Migrations.CreateWaitlist do
  use Ecto.Migration

  def change do
    create table(:waitlist_signups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      
      # Queue position (assigned on signup)
      add :queue_number, :integer, null: false
      
      # Status tracking
      add :status, :string, null: false, default: "waiting"  # waiting, invited, activated, declined
      
      # Unique token for status page access
      add :status_token, :string, null: false
      
      # Activation tracking
      add :invited_at, :utc_datetime
      add :activated_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      
      # Optional: how they heard about us
      add :referral_source, :string
      
      # Optional: why they want early access
      add :reason, :text
      
      timestamps()
    end

    create unique_index(:waitlist_signups, [:email])
    create unique_index(:waitlist_signups, [:queue_number])
    create unique_index(:waitlist_signups, [:status_token])
    create index(:waitlist_signups, [:status])
    create index(:waitlist_signups, [:inserted_at])
  end
end
