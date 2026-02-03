defmodule Onelist.Accounts.Password do
  @moduledoc """
  Utilities for password hashing and verification.
  Provides a secure and consistent interface for password management.
  """

  # For a secure default, we prefer Argon2 but allow fallback to Bcrypt
  @hash_algorithm Application.compile_env(:onelist, :password_hash_algorithm, :argon2)

  @doc """
  Hashes a password using the configured hashing algorithm.

  ## Examples

      iex> hash_password("secure_password")
      "$argon2..."
  """
  @spec hash_password(binary()) :: binary()
  def hash_password(password) when is_binary(password) do
    case @hash_algorithm do
      :argon2 ->
        # Use Argon2 with recommended settings
        Argon2.hash_pwd_salt(password,
          # Recommended settings for interactive login
          # Time cost
          t_cost: 2,
          # Memory factor
          m_cost: 16
        )

      :bcrypt ->
        # Fallback to Bcrypt if Argon2 not available
        Bcrypt.hash_pwd_salt(password)

      :test ->
        # Use simplified test hasher
        test_hasher = Application.get_env(:onelist, :test_password_hasher)
        apply(test_hasher, :hash_password, [password])

      _ ->
        # Safeguard against misconfiguration
        raise "Unsupported password hashing algorithm: #{inspect(@hash_algorithm)}"
    end
  end

  @doc """
  Verifies a password against a stored hash.

  Uses a constant-time comparison to prevent timing attacks.

  ## Examples

      iex> verify_password(stored_hash, "correct_password")
      true

      iex> verify_password(stored_hash, "wrong_password")
      false
  """
  @spec verify_password(binary(), binary()) :: boolean()
  def verify_password(stored_hash, password)
      when is_binary(stored_hash) and is_binary(password) do
    case @hash_algorithm do
      :argon2 ->
        Argon2.verify_pass(password, stored_hash)

      :bcrypt ->
        Bcrypt.verify_pass(password, stored_hash)

      :test ->
        # Use simplified test hasher
        test_hasher = Application.get_env(:onelist, :test_password_hasher)
        apply(test_hasher, :verify_password, [stored_hash, password])

      _ ->
        # Safeguard against misconfiguration
        raise "Unsupported password hashing algorithm: #{inspect(@hash_algorithm)}"
    end
  end

  @doc """
  Validates the password meets security requirements.

  ## Examples

      iex> valid_password?("password123")
      {:error, "password must contain at least one uppercase character"}

      iex> valid_password?("Password123#")
      :ok
  """
  @spec valid_password?(binary()) :: :ok | {:error, binary()}
  def valid_password?(password) when is_binary(password) do
    cond do
      String.length(password) < 10 ->
        {:error, "password must be at least 10 characters"}

      String.length(password) > 80 ->
        {:error, "password must be at most 80 characters"}

      not contains_uppercase?(password) ->
        {:error, "password must contain at least one uppercase character"}

      not contains_lowercase?(password) ->
        {:error, "password must contain at least one lowercase character"}

      not contains_digit?(password) ->
        {:error, "password must contain at least one digit"}

      true ->
        :ok
    end
  end

  def valid_password?(_), do: {:error, "password must be a string"}

  # Helper functions for password validation
  defp contains_uppercase?(string), do: Regex.match?(~r/[A-Z]/, string)
  defp contains_lowercase?(string), do: Regex.match?(~r/[a-z]/, string)
  defp contains_digit?(string), do: Regex.match?(~r/[0-9]/, string)
end
