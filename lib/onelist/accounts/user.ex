defmodule Onelist.Accounts.User do
  @moduledoc """
  User schema and validation for authentication.
  """

  use Ecto.Schema
  import Ecto.Changeset
  alias Onelist.Accounts.Password
  alias Onelist.Accounts.SocialAccount

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :naive_datetime
    field :password_changed_at, :naive_datetime
    field :email_verified, :boolean, default: false
    field :email_verification_token, :string
    field :name, :string
    field :verified_at, :utc_datetime

    # Fields for managing failed login attempts and account locking
    field :failed_attempts, :integer, default: 0
    field :locked_at, :naive_datetime

    # Fields for tracking login information
    field :last_login_at, :naive_datetime
    field :last_login_ip, :string

    # Fields for password reset functionality
    field :reset_token_hash, :string, redact: true
    field :reset_token_created_at, :naive_datetime

    # Fields for security and compliance
    field :require_password_change, :boolean, default: false
    field :data_consent_given_at, :naive_datetime

    # Public profile fields
    field :username, :string

    # Waitlist tracking (preserved from signup)
    field :waitlist_number, :integer
    # "headwaters", "tributaries", "public"
    field :waitlist_tier, :string

    # Trusted Memory (for AI accounts)
    # "human" or "ai"
    field :account_type, :string, default: "human"
    field :trusted_memory_mode, :boolean, default: false
    field :trusted_memory_enabled_at, :utc_datetime_usec
    field :last_weekly_review, :utc_datetime_usec
    field :gtd_settings, :map, default: %{}

    has_many :sessions, Onelist.Accounts.Session
    has_many :social_accounts, SocialAccount

    timestamps()
  end

  @doc """
  Registration changeset for user creation.

  ## Examples

      iex> registration_changeset(%User{}, %{email: "user@example.com", password: "Password123"})
      #Ecto.Changeset<valid?=true, ...>
      
      iex> registration_changeset(%User{}, %{email: "invalid", password: "short"})
      #Ecto.Changeset<valid?=false, ...>
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :name])
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
  end

  @doc """
  Changeset for OAuth registration (no password required).
  Sets a random unusable password to satisfy the database constraint.
  """
  def oauth_registration_changeset(user, attrs) do
    # Generate a random unusable password for OAuth users
    random_password = :crypto.strong_rand_bytes(32) |> Base.encode64()
    hashed = Password.hash_password(random_password)

    user
    |> cast(attrs, [:email, :name])
    |> validate_email()
    |> put_change(:hashed_password, hashed)
    |> put_change(:email_verified, true)
    |> put_change(:verified_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for updating failed login attempts.
  """
  def failed_attempts_changeset(user, attrs) do
    user
    |> cast(attrs, [:failed_attempts, :locked_at])
    |> validate_required([:failed_attempts])
  end

  @doc """
  Changeset for resetting a password.
  """
  def reset_password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :reset_token_hash, :reset_token_created_at])
    |> validate_password()
    |> put_password_hash()
    |> put_change(:reset_token_hash, nil)
    |> put_change(:reset_token_created_at, nil)
    |> put_change(:failed_attempts, 0)
    |> put_change(:locked_at, nil)
    |> put_change(
      :password_changed_at,
      NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    )
  end

  @doc """
  Changeset for tracking login activity.
  """
  def login_tracking_changeset(user, attrs) do
    user
    |> cast(attrs, [:last_login_at, :last_login_ip])
    |> validate_required([:last_login_at, :last_login_ip])
  end

  @doc """
  Changeset for setting or updating the reset token.
  """
  def reset_token_changeset(user, attrs) do
    user
    |> cast(attrs, [:reset_token_hash, :reset_token_created_at])
    |> validate_required([:reset_token_hash, :reset_token_created_at])
  end

  @doc """
  Changeset for email verification.
  """
  def email_verification_changeset(user, attrs) do
    user
    |> cast(attrs, [:email_verified, :verified_at])
    |> put_change(:email_verification_token, nil)
  end

  @doc """
  Changeset for setting or updating the user's username.

  Usernames must:
  - Be between 3 and 30 characters
  - Start and end with a letter or number
  - Contain only letters, numbers, underscores, and hyphens
  - Be unique (case-insensitive)
  """
  def username_changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]{1,2}$/,
      message: "must start and end with a letter or number, can contain underscores and hyphens"
    )
    |> validate_format(:username, ~r/^[a-zA-Z0-9_-]+$/,
      message: "can only contain letters, numbers, underscores, and hyphens"
    )
    |> unsafe_validate_unique(:username, Onelist.Repo, message: "has already been taken")
    |> unique_constraint(:username,
      name: :users_username_unique_idx,
      message: "has already been taken"
    )
  end

  # Validate email format and uniqueness
  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 255)
    |> unsafe_validate_unique(:email, Onelist.Repo)
    |> unique_constraint(:email)
  end

  # Validate password complexity
  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 10, max: 80)
    |> validate_format(:password, ~r/[a-z]/,
      message: "must have at least one lowercase character"
    )
    |> validate_format(:password, ~r/[A-Z]/,
      message: "must have at least one uppercase character"
    )
    |> validate_format(:password, ~r/[0-9]/, message: "must have at least one digit")
  end

  # Hash the password and store it
  defp put_password_hash(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :hashed_password, Password.hash_password(password))

      _ ->
        changeset
    end
  end

  @doc """
  Checks if a password is valid for this user.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password) do
    Password.verify_password(hashed_password, password)
  end

  def valid_password?(_, _), do: false

  @doc """
  Changeset for setting waitlist information during activation.
  """
  def waitlist_changeset(user, attrs) do
    user
    |> cast(attrs, [:waitlist_number, :waitlist_tier])
  end

  @doc """
  Returns the tier name for a given waitlist number.
  """
  def tier_for_number(number) when number <= 100, do: "headwaters"
  def tier_for_number(number) when number <= 1000, do: "tributaries"
  def tier_for_number(_number), do: "public"
end
