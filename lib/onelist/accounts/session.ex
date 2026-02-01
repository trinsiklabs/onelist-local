defmodule Onelist.Accounts.Session do
  @moduledoc """
  Session schema for user authentication sessions.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field :token_hash, :string, redact: true
    field :context, :string, default: "web"
    field :user_agent, :string
    field :ip_address, :string
    field :device_name, :string
    field :location, :string
    field :expires_at, :utc_datetime_usec
    field :refreshed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :last_active_at, :utc_datetime_usec
    
    belongs_to :user, Onelist.Accounts.User
    
    timestamps(type: :utc_datetime_usec)
  end
  
  @doc """
  Changeset for creating a new session.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :token_hash, :context, :user_agent, :ip_address, 
                   :device_name, :location, :expires_at, :last_active_at])
    |> validate_required([:user_id, :token_hash, :expires_at, :last_active_at])
    |> foreign_key_constraint(:user_id)
  end
  
  @doc """
  Changeset for revoking a session.
  """
  def revoke_changeset(session, attrs) do
    session
    |> cast(attrs, [:revoked_at])
    |> validate_required([:revoked_at])
  end
  
  @doc """
  Changeset for refreshing a session.
  """
  def refresh_changeset(session, attrs) do
    session
    |> cast(attrs, [:refreshed_at, :expires_at])
    |> validate_required([:refreshed_at, :expires_at])
  end
  
  @doc """
  Changeset for updating session activity.
  """
  def update_activity_changeset(session, attrs) do
    session
    |> cast(attrs, [:last_active_at])
    |> validate_required([:last_active_at])
  end
end 