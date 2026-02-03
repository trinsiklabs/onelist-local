defmodule Onelist.Accounts.SocialAccount do
  @moduledoc """
  Schema and functions for managing social authentication accounts.
  Represents the connection between a Onelist user and a third-party OAuth provider.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Onelist.Accounts.User

  @providers ["github", "google", "apple"]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "social_accounts" do
    field :provider, :string
    field :provider_id, :string
    field :provider_email, :string
    field :provider_username, :string
    field :provider_name, :string
    field :avatar_url, :string
    field :token_data, :string

    belongs_to :user, User

    timestamps()
  end

  @doc """
  Changeset for creating a new social account.
  """
  def changeset(social_account, attrs) do
    social_account
    |> cast(attrs, [
      :user_id,
      :provider,
      :provider_id,
      :provider_email,
      :provider_username,
      :provider_name,
      :avatar_url,
      :token_data
    ])
    |> validate_required([:user_id, :provider, :provider_id])
    |> validate_inclusion(:provider, @providers)
    |> unique_constraint([:provider, :provider_id], name: :unique_provider_account)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for updating a social account's token data.
  """
  def token_update_changeset(social_account, attrs) do
    social_account
    |> cast(attrs, [:token_data])
    |> validate_required([:token_data])
  end

  @doc """
  Changeset for updating profile information from the provider.
  """
  def profile_update_changeset(social_account, attrs) do
    social_account
    |> cast(attrs, [:provider_email, :provider_username, :provider_name, :avatar_url])
  end
end
