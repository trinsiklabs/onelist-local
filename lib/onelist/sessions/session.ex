defmodule Onelist.Sessions.Session do
  @moduledoc """
  Schema for user sessions.

  Tracks user sessions with their tokens, expiration, revocation status,
  and device information.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Onelist.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field :token_hash, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :refreshed_at, :utc_datetime
    field :last_active_at, :utc_datetime
    field :ip_address, :string
    field :user_agent, :string
    field :device_name, :string
    field :context, :string, default: "web"

    belongs_to :user, User

    timestamps()
  end

  @doc """
  Changeset for creating a new session.
  """
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :user_id,
      :token_hash,
      :expires_at,
      :ip_address,
      :user_agent,
      :device_name,
      :context,
      :last_active_at
    ])
    |> validate_required([:user_id, :token_hash, :expires_at])
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
  Changeset for refreshing a session's token.
  """
  def refresh_changeset(session, attrs) do
    session
    |> cast(attrs, [:refreshed_at, :expires_at])
    |> validate_required([:refreshed_at, :expires_at])
  end

  @doc """
  Changeset for updating last_active_at timestamp.
  """
  def update_activity_changeset(session, attrs) do
    session
    |> cast(attrs, [:last_active_at])
    |> validate_required([:last_active_at])
  end
end
