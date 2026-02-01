defmodule Onelist.Privacy do
  @moduledoc """
  Privacy utilities for handling sensitive data.
  """
  
  alias Onelist.Security
  alias Onelist.Accounts.Session
  import Ecto.Query
  
  @doc """
  Anonymizes user data for privacy.
  Only keeps essential data and anonymizes sensitive fields.
  
  ## Examples
  
      iex> anonymize_session_data(session)
      %{device: "Windows", location: "Unknown", last_active: ~U[2023-01-01 00:00:00Z]}
  """
  def anonymize_session_data(%Session{} = session) do
    # Keep only non-sensitive data
    %{
      id: session.id,
      device_name: session.device_name || "Unknown device",
      location: session.location || "Unknown",
      last_active_at: session.last_active_at,
      created_at: session.inserted_at
    }
  end
  
  @doc """
  Clean up session data after account deletion.
  
  ## Examples
  
      iex> cleanup_user_data(user_id)
      {deleted_count, nil}
  """
  def cleanup_user_data(user_id) do
    # Delete all sessions for the user
    {session_count, _} = Onelist.Repo.delete_all(
      from s in Session, where: s.user_id == ^user_id
    )
    
    # Delete all login attempts for the user's email
    if user = Onelist.Repo.get(Onelist.Accounts.User, user_id) do
      {login_count, _} = Onelist.Repo.delete_all(
        from a in Onelist.Accounts.LoginAttempt, where: a.email == ^user.email
      )
      
      {session_count + login_count, nil}
    else
      {session_count, nil}
    end
  end
  
  @doc """
  Implements retention policy for login attempts.
  Deletes attempts older than the retention period.
  
  ## Examples
  
      iex> cleanup_login_attempts()
      {deleted_count, nil}
  """
  def cleanup_login_attempts(retention_days \\ 90) do
    # Calculate cutoff date
    cutoff = DateTime.add(DateTime.utc_now(), -retention_days * 24 * 60 * 60, :second)
    
    # Delete in batches
    Onelist.Repo.delete_all(
      from a in Onelist.Accounts.LoginAttempt, where: a.inserted_at < ^cutoff
    )
  end
  
  @doc """
  Create an audit log entry for privacy-relevant actions.
  
  ## Examples
  
      iex> log_privacy_action(:session_created, %{user_id: user.id, ip: ip})
      :ok
  """
  def log_privacy_action(action, details) do
    # Log privacy actions
    require Logger
    
    # Ensure we don't log sensitive data
    sanitized_details = sanitize_for_logging(details)
    
    Logger.info("Privacy action: #{action}, details: #{inspect(sanitized_details)}")
    :ok
  end
  
  @doc """
  Sanitize data for logging to prevent sensitive data exposure.
  """
  def sanitize_for_logging(details) do
    # Fields that should be anonymized
    sensitive_fields = [:ip, :ip_address, :email, :token, :password]
    
    Enum.reduce(details, %{}, fn {key, value}, acc ->
      if key in sensitive_fields do
        case key do
          :ip -> Map.put(acc, key, Security.anonymize_ip(value))
          :ip_address -> Map.put(acc, key, Security.anonymize_ip(value))
          :email -> Map.put(acc, key, anonymize_email(value))
          # Don't include tokens at all
          :token -> acc
          :password -> acc
          _ -> Map.put(acc, key, value)
        end
      else
        Map.put(acc, key, value)
      end
    end)
  end
  
  @doc """
  Anonymize an email address for privacy.
  
  ## Examples
  
      iex> anonymize_email("user@example.com")
      "u***@e***.com"
  """
  def anonymize_email(email) do
    case String.split(email, "@") do
      [name, domain] ->
        # Get first character of name and domain
        first_name_char = String.first(name)
        
        # Split domain into parts
        domain_parts = String.split(domain, ".")
        domain_name = List.first(domain_parts)
        tld = List.last(domain_parts)
        
        # Anonymize each part
        first_domain_char = String.first(domain_name)
        
        # Construct anonymized email
        "#{first_name_char}***@#{first_domain_char}***.#{tld}"
      
      _ -> "a***@e***.com" # Fallback for invalid email format
    end
  end
end 