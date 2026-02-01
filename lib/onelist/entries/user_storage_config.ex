defmodule Onelist.Entries.UserStorageConfig do
  @moduledoc """
  Schema for user's BYOB (Bring Your Own Bucket) storage configuration.

  Allows users to connect their own cloud storage accounts instead of
  using Onelist-provided storage.

  ## Supported Providers

  - `s3` - AWS S3
  - `r2` - Cloudflare R2
  - `b2` - Backblaze B2
  - `gcs` - Google Cloud Storage
  - `spaces` - DigitalOcean Spaces
  - `wasabi` - Wasabi
  - `minio` - Self-hosted MinIO

  ## Security

  Credentials are encrypted at rest using the application's encryption key.
  See `Onelist.Storage.UserBucket` for credential encryption/decryption.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(s3 r2 b2 gcs spaces wasabi minio)

  schema "user_storage_configs" do
    field :provider, :string
    field :bucket_name, :string
    field :region, :string
    field :endpoint, :string
    # Encrypted credentials (access_key_id + secret_access_key)
    field :credentials, :binary
    field :is_active, :boolean, default: true
    field :verified_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :user, Onelist.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating or updating a storage configuration.
  """
  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :user_id,
      :provider,
      :bucket_name,
      :region,
      :endpoint,
      :credentials,
      :is_active,
      :verified_at,
      :metadata
    ])
    |> validate_required([:user_id, :provider, :bucket_name, :credentials])
    |> validate_inclusion(:provider, @providers)
    |> validate_length(:bucket_name, max: 255)
    |> validate_length(:region, max: 63)
    |> validate_length(:endpoint, max: 500)
    |> unique_constraint([:user_id], name: :user_storage_configs_active_user_unique)
  end

  @doc """
  Changeset for updating verification status.
  """
  def verify_changeset(config, attrs) do
    config
    |> cast(attrs, [:verified_at, :is_active])
  end

  @doc """
  Marks the configuration as verified.
  """
  def mark_verified(config) do
    verify_changeset(config, %{verified_at: DateTime.utc_now()})
  end

  @doc """
  Deactivates the configuration.
  """
  def deactivate(config) do
    verify_changeset(config, %{is_active: false})
  end

  @doc """
  Returns the list of supported providers.
  """
  def providers, do: @providers

  @doc """
  Returns true if the configuration has been verified.
  """
  def verified?(%__MODULE__{verified_at: nil}), do: false
  def verified?(%__MODULE__{}), do: true

  @doc """
  Returns true if this is an S3-compatible provider.
  """
  def s3_compatible?(%__MODULE__{provider: provider}) do
    provider in ~w(s3 r2 b2 spaces wasabi minio)
  end
end
