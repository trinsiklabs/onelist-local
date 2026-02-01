defmodule Onelist.Waitlist.Signup do
  @moduledoc """
  Schema for Headwaters waitlist signups.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "waitlist_signups" do
    field :email, :string
    field :name, :string
    field :queue_number, :integer
    field :status, :string, default: "waiting"
    field :status_token, :string
    field :invited_at, :utc_datetime
    field :activated_at, :utc_datetime
    field :referral_source, :string
    field :reason, :string

    belongs_to :user, Onelist.Accounts.User

    timestamps()
  end

  @doc """
  Changeset for creating a new signup.
  """
  def changeset(signup, attrs) do
    signup
    |> cast(attrs, [:email, :name, :queue_number, :status_token, :referral_source, :reason])
    |> validate_required([:email, :queue_number, :status_token])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 255)
    |> validate_length(:name, max: 255)
    |> validate_length(:reason, max: 1000)
    |> unique_constraint(:email, message: "is already on the waitlist")
    |> unique_constraint(:queue_number)
    |> unique_constraint(:status_token)
    |> downcase_email()
  end

  @doc """
  Changeset for inviting a signup.
  """
  def invite_changeset(signup) do
    signup
    |> change(%{
      status: "invited",
      invited_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc """
  Changeset for activating a signup.
  """
  def activate_changeset(signup, user_id) do
    signup
    |> change(%{
      status: "activated",
      activated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      user_id: user_id
    })
  end

  defp downcase_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email, String.downcase(email))
    end
  end
end
