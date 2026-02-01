defmodule Onelist.Accounts.LoginAttempt do
  @moduledoc """
  Schema for tracking login attempts for rate limiting and security auditing.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "login_attempts" do
    field :email, :string
    field :ip_address, :string
    field :successful, :boolean, default: false
    field :user_agent, :string
    field :reason, :string
    
    timestamps(type: :utc_datetime_usec)
  end
  
  @doc """
  Changeset for creating a login attempt record.
  """
  def changeset(login_attempt, attrs) do
    login_attempt
    |> cast(attrs, [:email, :ip_address, :successful, :user_agent, :reason])
    |> validate_required([:email, :ip_address, :successful])
    |> validate_length(:email, max: 255)
    |> validate_length(:ip_address, max: 45)
    |> validate_length(:reason, max: 255)
  end
end 