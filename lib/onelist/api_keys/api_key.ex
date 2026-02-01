defmodule Onelist.ApiKeys.ApiKey do
  @moduledoc """
  API Key schema for external API access.

  API keys allow users to access the Onelist API programmatically.
  Keys are hashed before storage and only shown once at creation time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_keys" do
    field :name, :string
    field :key_hash, :string, redact: true
    field :prefix, :string
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :user, Onelist.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new API key.
  """
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :key_hash, :prefix, :expires_at])
    |> validate_required([:name, :key_hash, :prefix])
    |> validate_length(:name, max: 255)
    |> unique_constraint(:key_hash)
  end

  @doc """
  Changeset for revoking an API key.
  """
  def revoke_changeset(api_key) do
    api_key
    |> change(%{revoked_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)})
  end

  @doc """
  Changeset for updating last_used_at.
  """
  def touch_changeset(api_key) do
    api_key
    |> change(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)})
  end

  @doc """
  Checks if the API key is revoked.
  """
  def revoked?(%__MODULE__{revoked_at: nil}), do: false
  def revoked?(%__MODULE__{}), do: true

  @doc """
  Checks if the API key is expired.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the API key is valid (not revoked and not expired).
  """
  def valid?(%__MODULE__{} = api_key) do
    not revoked?(api_key) and not expired?(api_key)
  end
end
