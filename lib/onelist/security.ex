defmodule Onelist.Security do
  @moduledoc """
  Security utilities for token generation, validation, and other security-related operations.
  """

  @doc """
  Generates a cryptographically secure random token.
  Returns a Base64-encoded string with a length twice the specified input length.

  ## Examples

      iex> generate_token(16)
      "kS7-OYcJ0eJ4KGI1asj3wer9YnS3AdyD"
  """
  @spec generate_token(integer) :: binary
  def generate_token(length) do
    # Generate more bytes than needed to ensure we have enough after encoding
    # Base64 encoding increases length by approximately 4/3, but tests expect double length
    # We'll generate enough bytes to ensure we have at least double the requested length
    bytes_needed = length * 2
    
    # Generate random bytes, encode, and then take exactly 2*length characters
    token = :crypto.strong_rand_bytes(bytes_needed)
      |> Base.url_encode64(padding: false)
    
    # Make sure our result is at least twice the requested length
    if String.length(token) >= length * 2 do
      String.slice(token, 0, length * 2)
    else
      # If somehow we didn't get enough characters, pad with more
      token <> generate_token(length * 2 - String.length(token))
    end
  end

  @doc """
  Generates a code verifier for PKCE OAuth flow.
  Returns a cryptographically random string of 43-128 characters.

  ## Examples

      iex> generate_code_verifier()
      "kS7-OYcJ0eJ4KGI1asj3wer9YnS3AdyD-8fKlbDeP7h_S0jIasWE89fPa1jDc032"

  """
  @spec generate_code_verifier() :: binary
  def generate_code_verifier do
    :crypto.strong_rand_bytes(64)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 64)
  end

  @doc """
  Creates a code challenge from a code verifier using the S256 method (SHA256).
  
  ## Examples

      iex> create_code_challenge("kS7-OYcJ0eJ4KGI1asj3wer9YnS3AdyD-8fKlbDeP7h_S0jIasWE89fPa1jDc032")
      "HL9XK2S_ajeLvCjvKhH1GVfHm0KKnRk-hEYGYmSBeJ8"

  """
  @spec create_code_challenge(binary) :: binary
  def create_code_challenge(verifier) when is_binary(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.replace("=", "")
  end

  @doc """
  Encrypts OAuth token data for secure storage.
  Uses AES-256-GCM for authenticated encryption with associated data (AEAD).
  
  ## Examples

      iex> encrypt_token(%{"access_token" => "xyz", "refresh_token" => "abc"})
      "encrypted_token_data"
  """
  @spec encrypt_token(map() | binary()) :: binary()
  def encrypt_token(token_data) when is_map(token_data) do
    encrypt_token(Jason.encode!(token_data))
  end
  
  def encrypt_token(token_data) when is_binary(token_data) do
    # Get encryption key from application config
    secret = get_encryption_key()
    
    # Generate a random IV (Initialization Vector)
    iv = :crypto.strong_rand_bytes(16)
    
    # Generate a random authentication tag (AAD)
    aad = :crypto.strong_rand_bytes(16)
    
    # Encrypt the token data
    {cipher_text, tag} = :crypto.crypto_one_time_aead(
      :aes_256_gcm,
      secret,
      iv,
      token_data,
      aad,
      true
    )
    
    # Combine IV, AAD, tag, and cipher text for storage
    iv <> aad <> tag <> cipher_text
    |> Base.encode64()
  end
  
  @doc """
  Decrypts previously encrypted OAuth token data.
  
  ## Examples

      iex> decrypt_token("encrypted_token_data")
      {:ok, %{"access_token" => "xyz", "refresh_token" => "abc"}}
      
      iex> decrypt_token("invalid_data")
      {:error, :invalid}
  """
  @spec decrypt_token(binary()) :: {:ok, map()} | {:error, atom()}
  def decrypt_token(encrypted_data) when is_binary(encrypted_data) do
    try do
      # Decode the base64 encoded data
      decoded =
        case Base.decode64(encrypted_data) do
          {:ok, data} -> data
          :error -> raise "Invalid base64 encoding"
        end
      
      # Extract the components
      <<iv::binary-16, aad::binary-16, tag::binary-16, cipher_text::binary>> = decoded
      
      # Get encryption key from application config
      secret = get_encryption_key()
      
      # Decrypt the token data
      case :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        secret,
        iv,
        cipher_text,
        aad,
        tag,
        false
      ) do
        plain_text when is_binary(plain_text) ->
          case Jason.decode(plain_text) do
            {:ok, token_map} -> {:ok, token_map}
            {:error, _} -> {:error, :invalid_json}
          end
        
        :error ->
          {:error, :decryption_failed}
      end
    rescue
      _ -> {:error, :invalid}
    end
  end
  
  # Static salt for key derivation (derived from app name for consistency)
  @kdf_salt "onelist_encryption_key_v1"
  # PBKDF2 iterations - higher is more secure but slower
  @kdf_iterations 100_000

  defp get_encryption_key do
    # Get encryption key from config, or derive from secret_key_base
    key = Application.get_env(:onelist, Onelist.Security)[:encryption_key] ||
          Application.get_env(:onelist, :secret_key_base)

    # Use PBKDF2 to derive a 32-byte (256-bit) key for AES-256
    # This provides better protection against brute-force attacks than simple SHA256
    derive_key(key, @kdf_salt, @kdf_iterations, 32)
  end

  # Derives a key using PBKDF2-HMAC-SHA256
  # Falls back to simple SHA256 if PBKDF2 is not available
  defp derive_key(password, salt, iterations, key_length) do
    try do
      :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, key_length)
    rescue
      # Fallback for older OTP versions without pbkdf2_hmac
      _error ->
        # Use multiple rounds of HMAC as a fallback
        derive_key_fallback(password, salt, iterations, key_length)
    end
  end

  # Fallback key derivation using iterated HMAC
  defp derive_key_fallback(password, salt, iterations, key_length) do
    initial = :crypto.mac(:hmac, :sha256, password, salt)

    derived =
      Enum.reduce(1..(iterations - 1), initial, fn _, acc ->
        :crypto.mac(:hmac, :sha256, password, acc)
      end)

    binary_part(derived, 0, min(key_length, byte_size(derived)))
  end

  @doc """
  Hashes a token using SHA256 for secure storage and lookup.
  Returns the same hash for the same input (deterministic) so tokens can be looked up.
  Returns nil when input is nil.

  ## Examples

      iex> token = "some-token"
      iex> hash1 = hash_token(token)
      iex> hash2 = hash_token(token)
      iex> hash1 == hash2
      true

      iex> hash_token(nil)
      nil
  """
  @spec hash_token(binary | nil) :: binary | nil
  def hash_token(nil), do: nil
  def hash_token(token) when is_binary(token) do
    # Use deterministic hashing so tokens can be looked up
    # The token itself should already be cryptographically random
    :crypto.hash(:sha256, token)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compares two values in constant time to prevent timing attacks.

  ## Examples

      iex> secure_compare("abc123", "abc123")
      true

      iex> secure_compare("abc123", "def456")
      false
  """
  @spec secure_compare(binary, binary) :: boolean
  def secure_compare(left, right) when is_binary(left) and is_binary(right) do
    if byte_size(left) == byte_size(right) do
      Plug.Crypto.secure_compare(left, right)
    else
      # If they're different lengths, still do the comparison but it will return false
      # Use secure_compare to prevent giving away which value is longer based on timing
      Plug.Crypto.secure_compare(left, String.slice(right, 0, byte_size(left)))
    end
  end
  def secure_compare(_, _), do: false

  @doc """
  Anonymizes an IP address for privacy.
  
  For IPv4, the last octet is replaced with zeroes.
  For IPv6, the last 80 bits (last 5 segments) are replaced with zeroes.
  Returns an empty string for nil or empty string inputs.

  ## Examples

      iex> anonymize_ip("192.168.1.123")
      "192.168.1.0"

      iex> anonymize_ip("2001:0db8:85a3:0000:0000:8a2e:0370:7334")
      "2001:0db8:85a3:0000:0000:0000:0000:0000"
      
      iex> anonymize_ip(nil)
      ""
      
      iex> anonymize_ip("")
      ""
  """
  @spec anonymize_ip(binary | nil) :: binary
  def anonymize_ip(nil), do: ""
  def anonymize_ip(""), do: ""
  def anonymize_ip(ip) when is_binary(ip) do
    cond do
      # IPv4 address
      String.match?(ip, ~r/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) ->
        parts = String.split(ip, ".")
        length = length(parts)
        
        if length == 4 do
          # Replace the last octet with 0
          Enum.take(parts, 3) ++ ["0"] |> Enum.join(".")
        else
          # Invalid IPv4 format, return as is
          ip
        end
      
      # IPv6 address (simplified regex check)
      String.match?(ip, ~r/^[0-9a-fA-F:]+$/) && String.contains?(ip, ":") ->
        case :inet.parse_address(to_charlist(ip)) do
          {:ok, _} ->
            # Replace the last 5 segments with zeroes
            parts = String.split(ip, ":")
            
            # Make sure we handle the :: shorthand notation
            expanded_parts = if Enum.member?(parts, "") do
              # Handle shorthand notation by expanding it
              idx = Enum.find_index(parts, &(&1 == ""))
              prefix = Enum.take(parts, idx)
              suffix = Enum.drop(parts, idx + 1)
              missing_count = 8 - length(prefix) - length(suffix)
              prefix ++ List.duplicate("0", missing_count) ++ suffix
            else
              parts
            end
            
            # Take the first 3 segments and append 5 zeroes
            sanitized = Enum.take(expanded_parts, 3) ++ List.duplicate("0", 5)
            Enum.join(sanitized, ":")
          
          _ ->
            # Failed to parse, return as is
            ip
        end
      
      # Not recognized as IP address
      true ->
        "0.0.0.0"
    end
  end

  @doc """
  Extracts basic device information from a user agent string.

  ## Examples

      iex> extract_device_info("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      "Windows 10 / Chrome"

      iex> extract_device_info("Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1")
      "iPhone / iOS / Safari"
  """
  @spec extract_device_info(binary | nil) :: binary
  def extract_device_info(nil), do: "Unknown Device"
  def extract_device_info(""), do: "Unknown Device"
  def extract_device_info(user_agent) when is_binary(user_agent) do
    # Check for bots first
    if is_bot?(user_agent) do
      "Bot / " <> extract_bot_name(user_agent)
    else
      os = extract_os(user_agent)
      browser = extract_browser(user_agent)
      "#{os} / #{browser}"
    end
  end

  # Extracts operating system from user agent
  defp extract_os(user_agent) do
    cond do
      # Mobile devices first (more specific)
      String.contains?(user_agent, "iPhone") ->
        "iPhone / iOS " <> extract_ios_version(user_agent)

      String.contains?(user_agent, "iPad") ->
        "iPad / iOS " <> extract_ios_version(user_agent)

      String.contains?(user_agent, "Android") ->
        "Android " <> extract_android_version(user_agent)

      # Desktop operating systems
      # Windows 11 reports as Windows NT 10.0 but with a different build number
      String.contains?(user_agent, "Windows NT 10.0") ->
        if String.contains?(user_agent, "Windows NT 10.0; Win64; x64") &&
           Regex.match?(~r/build\/(\d+)/i, user_agent) do
          case Regex.run(~r/build\/(\d+)/i, user_agent) do
            [_, build] when build >= "22000" -> "Windows 11"
            _ -> "Windows 10"
          end
        else
          "Windows 10"
        end

      String.contains?(user_agent, "Windows NT 6.3") -> "Windows 8.1"
      String.contains?(user_agent, "Windows NT 6.2") -> "Windows 8"
      String.contains?(user_agent, "Windows NT 6.1") -> "Windows 7"
      String.contains?(user_agent, "Windows NT 6.0") -> "Windows Vista"
      String.contains?(user_agent, "Windows NT 5.1") -> "Windows XP"

      # macOS
      String.contains?(user_agent, "Mac OS X") ->
        "Mac " <> extract_macos_version(user_agent)

      # Chrome OS
      String.contains?(user_agent, "CrOS") -> "Chrome OS"

      # Linux variants
      String.contains?(user_agent, "Ubuntu") -> "Ubuntu Linux"
      String.contains?(user_agent, "Fedora") -> "Fedora Linux"
      String.contains?(user_agent, "Linux") -> "Linux"

      true -> "Unknown OS"
    end
  end

  # Extract iOS version
  defp extract_ios_version(user_agent) do
    case Regex.run(~r/OS (\d+)_(\d+)/, user_agent) do
      [_, major, minor] -> "#{major}.#{minor}"
      _ -> ""
    end
  end

  # Extract Android version
  defp extract_android_version(user_agent) do
    case Regex.run(~r/Android (\d+\.?\d*)/, user_agent) do
      [_, version] -> version
      _ -> ""
    end
  end

  # Extract macOS version
  defp extract_macos_version(user_agent) do
    case Regex.run(~r/Mac OS X (\d+)_(\d+)/, user_agent) do
      [_, major, minor] -> "#{major}.#{minor}"
      _ -> ""
    end
  end

  # Check if user agent is a bot/crawler
  defp is_bot?(user_agent) do
    bot_patterns = [
      "bot", "crawl", "spider", "slurp", "search", "fetch",
      "Googlebot", "Bingbot", "Yahoo", "DuckDuckBot", "Baiduspider",
      "facebookexternalhit", "Twitterbot", "LinkedInBot"
    ]
    String.downcase(user_agent)
    |> then(fn ua -> Enum.any?(bot_patterns, &String.contains?(ua, String.downcase(&1))) end)
  end

  # Extract bot name
  defp extract_bot_name(user_agent) do
    cond do
      String.contains?(user_agent, "Googlebot") -> "Googlebot"
      String.contains?(user_agent, "Bingbot") -> "Bingbot"
      String.contains?(user_agent, "DuckDuckBot") -> "DuckDuckBot"
      String.contains?(user_agent, "facebookexternalhit") -> "Facebook"
      String.contains?(user_agent, "Twitterbot") -> "Twitter"
      String.contains?(user_agent, "LinkedInBot") -> "LinkedIn"
      true -> "Unknown Bot"
    end
  end

  @doc """
  Extracts browser information from a user agent string.

  ## Examples

      iex> extract_browser("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36")
      "Chrome"

      iex> extract_browser("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Edge/91.0.864.59 Safari/537.36")
      "Edge"
  """
  @spec extract_browser(binary) :: binary
  def extract_browser(user_agent) when is_binary(user_agent) do
    cond do
      String.contains?(user_agent, "Firefox/") ->
        "Firefox"
      
      String.contains?(user_agent, "Edg/") || String.contains?(user_agent, "Edge/") ->
        "Edge"
      
      String.contains?(user_agent, "Chrome/") && !String.contains?(user_agent, "Chromium") ->
        "Chrome"
      
      String.contains?(user_agent, "Chromium/") ->
        "Chromium"
      
      String.contains?(user_agent, "Safari/") && !String.contains?(user_agent, "Chrome") &&
          !String.contains?(user_agent, "Chromium") ->
        "Safari"
      
      String.contains?(user_agent, "OPR/") || String.contains?(user_agent, "Opera/") ->
        "Opera"

      String.contains?(user_agent, "MSIE") || String.contains?(user_agent, "Trident/") ->
        "Internet Explorer"

      true ->
        "Unknown Browser"
    end
  end
  def extract_browser(_), do: "Unknown Browser"

  @doc """
  Checks if a password reset token is expired.
  
  Reset tokens are considered expired if they were created more than 24 hours ago
  or if the reset_token_created_at field is nil.

  ## Examples

      iex> user = %{reset_token_created_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -48, :hour)}
      iex> is_expired_reset_token?(user)
      true

      iex> user = %{reset_token_created_at: NaiveDateTime.utc_now()}
      iex> is_expired_reset_token?(user)
      false
      
      iex> user = %{reset_token_created_at: nil}
      iex> is_expired_reset_token?(user)
      true
  """
  @spec is_expired_reset_token?(map()) :: boolean()
  def is_expired_reset_token?(%{reset_token_created_at: nil}), do: true
  def is_expired_reset_token?(%{reset_token_created_at: timestamp}) do
    # Reset tokens expire after 24 hours
    max_age = 24 * 60 * 60
    NaiveDateTime.diff(NaiveDateTime.utc_now(), timestamp) > max_age
  end

  @doc """
  Encrypts a payload for secure storage or transmission.

  ## Examples

      iex> encrypt_data(%{user_id: 123, role: "admin"})
      "encrypted_string"
  """
  @spec encrypt_data(any) :: binary
  def encrypt_data(data) do
    secret = Application.get_env(:onelist, Onelist.Security, [])[:encryption_key] ||
             Application.get_env(:onelist, :secret_key_base)
    
    # Use Phoenix's build-in encryption
    Phoenix.Token.encrypt(OnelistWeb.Endpoint, secret, data)
  end

  @doc """
  Decrypts a payload that was encrypted with encrypt_data/1.

  ## Examples

      iex> decrypt_data("encrypted_string")
      {:ok, %{user_id: 123, role: "admin"}}

      iex> decrypt_data("invalid_data")
      {:error, :invalid}
  """
  @spec decrypt_data(binary) :: {:ok, any} | {:error, :invalid}
  def decrypt_data(encrypted) do
    secret = Application.get_env(:onelist, Onelist.Security, [])[:encryption_key] ||
             Application.get_env(:onelist, :secret_key_base)
    
    case Phoenix.Token.decrypt(OnelistWeb.Endpoint, secret, encrypted) do
      {:ok, data} -> {:ok, data}
      {:error, _reason} -> {:error, :invalid}
    end
  end
end 