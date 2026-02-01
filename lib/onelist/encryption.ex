defmodule Onelist.Encryption do
  @moduledoc """
  Client-side encryption utilities for E2EE storage.

  Provides AES-256-GCM encryption for zero-knowledge cloud storage.
  Content is encrypted client-side before upload and decrypted after download,
  ensuring the cloud provider never sees plaintext content.

  ## Key Derivation

  Encryption keys should be derived from user passwords using PBKDF2 or similar:

      key = Encryption.derive_key(password, salt)

  ## Usage

      # Encrypt content
      {:ok, encrypted} = Encryption.encrypt(content, key)

      # Decrypt content
      {:ok, decrypted} = Encryption.decrypt(encrypted, key)

  ## Format

  Encrypted data format: `iv (12 bytes) || ciphertext || auth_tag (16 bytes)`
  """

  @aead_cipher :aes_256_gcm
  @iv_length 12
  @tag_length 16

  @doc """
  Encrypts content using AES-256-GCM.

  ## Parameters

  - `content` - Binary content to encrypt
  - `key` - 32-byte encryption key

  ## Returns

  - `{:ok, encrypted}` - Encrypted binary (iv || ciphertext || tag)
  - `{:error, reason}` - If encryption failed
  """
  @spec encrypt(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def encrypt(content, key) when byte_size(key) == 32 do
    iv = :crypto.strong_rand_bytes(@iv_length)

    try do
      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(@aead_cipher, key, iv, content, "", true)

      # Format: iv || ciphertext || tag
      encrypted = iv <> ciphertext <> tag
      {:ok, encrypted}
    rescue
      e -> {:error, e}
    end
  end

  def encrypt(_content, key) when byte_size(key) != 32 do
    {:error, :invalid_key_length}
  end

  def encrypt(_content, _key) do
    {:error, :invalid_key}
  end

  @doc """
  Decrypts content encrypted with AES-256-GCM.

  ## Parameters

  - `encrypted` - Encrypted binary (iv || ciphertext || tag)
  - `key` - 32-byte encryption key

  ## Returns

  - `{:ok, content}` - Decrypted binary
  - `{:error, :decryption_failed}` - If decryption or authentication failed
  """
  @spec decrypt(binary(), binary()) :: {:ok, binary()} | {:error, term()}
  def decrypt(encrypted, key) when byte_size(key) == 32 and byte_size(encrypted) > @iv_length + @tag_length do
    try do
      # Extract iv, ciphertext, and tag
      <<iv::binary-size(@iv_length), rest::binary>> = encrypted
      ciphertext_length = byte_size(rest) - @tag_length
      <<ciphertext::binary-size(ciphertext_length), tag::binary-size(@tag_length)>> = rest

      case :crypto.crypto_one_time_aead(@aead_cipher, key, iv, ciphertext, "", tag, false) do
        :error ->
          {:error, :decryption_failed}

        content ->
          {:ok, content}
      end
    rescue
      _ -> {:error, :decryption_failed}
    end
  end

  def decrypt(_encrypted, key) when byte_size(key) != 32 do
    {:error, :invalid_key_length}
  end

  def decrypt(_encrypted, _key) do
    {:error, :invalid_encrypted_data}
  end

  @doc """
  Derives an encryption key from a password using PBKDF2.

  ## Parameters

  - `password` - User password
  - `salt` - Random salt (should be stored with user)
  - `opts` - Options
    - `:iterations` - PBKDF2 iterations (default: 100_000)
    - `:length` - Key length in bytes (default: 32 for AES-256)

  ## Returns

  32-byte encryption key
  """
  @spec derive_key(String.t(), binary(), keyword()) :: binary()
  def derive_key(password, salt, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100_000)
    length = Keyword.get(opts, :length, 32)

    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, length)
  end

  @doc """
  Generates a random salt for key derivation.

  ## Returns

  16-byte random salt
  """
  @spec generate_salt() :: binary()
  def generate_salt do
    :crypto.strong_rand_bytes(16)
  end

  @doc """
  Generates a random encryption key.

  ## Returns

  32-byte random key
  """
  @spec generate_key() :: binary()
  def generate_key do
    :crypto.strong_rand_bytes(32)
  end
end
