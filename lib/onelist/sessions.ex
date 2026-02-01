defmodule Onelist.Sessions do
  @moduledoc """
  The Sessions context for session management.
  """
  
  alias Onelist.Repo
  alias Onelist.Sessions.Session
  alias Onelist.Accounts.User
  alias Onelist.Security
  import Ecto.Query
  
  # Configuration is accessed at runtime for flexibility
  @session_expiry_key :token_expiry_seconds
  @token_length_key :token_length
  @inactivity_timeout_key :inactivity_timeout_seconds
  
  @doc """
  Creates a new session for a user.
  
  ## Examples
  
      iex> create_session(user, %{user_agent: "Mozilla...", ip_address: "127.0.0.1"})
      {:ok, %{session: %Session{}, token: "token..."}}
      
      iex> create_session(nil, %{})
      {:error, :invalid_user}
  """
  def create_session(user, attrs \\ %{})
  
  def create_session(%User{} = user, attrs) do
    # Generate a secure random token
    token_length = get_config(@token_length_key, 32)
    token = Security.generate_token(token_length)
    
    # Create a token hash for storage (don't store the raw token)
    token_hash = Security.hash_token(token)
    
    # Prepare IP address for storage (anonymized)
    ip_address = Map.get(attrs, "ip_address", nil)
    |> Security.anonymize_ip()
    
    # Extract device name from user agent
    user_agent = Map.get(attrs, "user_agent", nil)
    device_name = if user_agent, do: Security.extract_device_info(user_agent), else: "Unknown Device"
    
    # Calculate token expiration (default 30 days)
    expiry_seconds = get_config(@session_expiry_key, 60 * 60 * 24 * 30)
    expires_at = DateTime.add(DateTime.utc_now(), expiry_seconds, :second) |> DateTime.truncate(:second)
    
    # Build session attributes
    session_attrs = %{
      user_id: user.id,
      token_hash: token_hash,
      ip_address: ip_address,
      user_agent: user_agent,
      device_name: device_name,
      context: Map.get(attrs, "context", "web"),
      expires_at: expires_at,
      last_active_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
    
    # Create the session
    case %Session{}
    |> Ecto.Changeset.cast(session_attrs, [:user_id, :token_hash, :ip_address, :user_agent, :device_name, :context, :expires_at, :last_active_at])
    |> Ecto.Changeset.validate_required([:user_id, :token_hash, :expires_at, :last_active_at])
    |> Repo.insert() do
      {:ok, session} ->
        # Return both the session record and the raw token
        {:ok, %{session: session, token: token}}
      
      {:error, changeset} ->
        {:error, changeset}
    end
  end
  
  def create_session(nil, _attrs) do
    {:error, :invalid_user}
  end
  
  @doc """
  Gets a session by token and validates it.
  Returns {:ok, session} if valid, or an error otherwise.

  ## Examples

      iex> get_session_by_token("valid_token")
      {:ok, %Session{}}

      iex> get_session_by_token("invalid_token")
      {:error, :invalid_token}

      iex> get_session_by_token("expired_token")
      {:error, :expired_token}

      iex> get_session_by_token("inactive_token")
      {:error, :inactive_session}
  """
  def get_session_by_token(token) when is_binary(token) do
    # Hash the token for comparison with stored hash
    # Security.hash_token is deterministic, so same token always produces same hash
    token_hash = Security.hash_token(token)

    # Query for the session with the token hash
    session_query = from s in Session,
      where: s.token_hash == ^token_hash,
      where: is_nil(s.revoked_at),
      preload: [:user]

    case Repo.one(session_query) do
      nil ->
        {:error, :invalid_token}

      session ->
        # Check if session is expired
        now = DateTime.utc_now()

        cond do
          DateTime.compare(session.expires_at, now) == :lt ->
            # Session is expired
            {:error, :expired_token}

          session_inactive?(session, now) ->
            # Session has been inactive for too long
            {:error, :inactive_session}

          true ->
            # Session is valid - update last_active_at if needed
            updated_session = maybe_update_last_active(session)

            # Refresh the session token if needed
            case refresh_needed?(updated_session) do
              true -> refresh_session(updated_session)
              false -> {:ok, updated_session}
            end
        end
    end
  end
  
  def get_session_by_token(_), do: {:error, :invalid_token}

  # Checks if a session has been inactive for longer than the configured timeout.
  # Default inactivity timeout is 24 hours (86400 seconds).
  # This provides an additional security layer beyond session expiry.
  defp session_inactive?(%Session{last_active_at: nil}, _now), do: false
  defp session_inactive?(%Session{last_active_at: last_active_at}, now) do
    # Default: 24 hours of inactivity triggers session invalidation
    inactivity_timeout = get_config(@inactivity_timeout_key, 60 * 60 * 24)

    # Calculate seconds since last activity
    seconds_inactive = DateTime.diff(now, last_active_at, :second)

    seconds_inactive > inactivity_timeout
  end

  # Updates the last_active_at field if needed.
  # Only updates if the last update was more than 15 minutes ago to reduce database writes.
  defp maybe_update_last_active(%Session{} = session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    last_active = session.last_active_at
    
    # Only update if last active time was more than 15 minutes ago
    if last_active && DateTime.diff(now, last_active, :second) > 15 * 60 do
      {:ok, updated_session} = session
        |> Ecto.Changeset.change(last_active_at: now)
        |> Repo.update()
      updated_session
    else
      session
    end
  end

  # Determines if a session token needs refreshing.
  # Returns true if the session is beyond 50% of its lifetime.
  defp refresh_needed?(%Session{} = session) do
    now = DateTime.utc_now()
    
    # Convert NaiveDateTime to DateTime with UTC timezone
    created_at_naive = session.inserted_at 
    # Convert to DateTime using :os.system_time - seconds since epoch
    created_at_secs = NaiveDateTime.diff(created_at_naive, ~N[1970-01-01 00:00:00], :second)
    created_at = DateTime.from_unix!(created_at_secs, :second)
    
    expires_at = session.expires_at
    
    # Calculate total lifetime and elapsed time
    total_lifetime = DateTime.diff(expires_at, created_at, :second)
    elapsed_time = DateTime.diff(now, created_at, :second)
    
    # Refresh if more than 50% of the lifetime has elapsed
    elapsed_time > total_lifetime * 0.5
  end

  # Refreshes a session by extending its expiration time and optionally updating the token.
  defp refresh_session(%Session{} = session) do
    # Calculate new expiration time
    expiry_seconds = get_config(@session_expiry_key, 60 * 60 * 24 * 30)
    new_expires_at = DateTime.add(DateTime.utc_now(), expiry_seconds, :second) |> DateTime.truncate(:second)
    
    # Update the session
    {:ok, updated_session} = session
      |> Ecto.Changeset.change(expires_at: new_expires_at)
      |> Repo.update()
    
    {:ok, updated_session}
  end
  
  @doc """
  Returns the configured inactivity timeout in seconds.
  Default is 24 hours (86400 seconds).

  ## Examples

      iex> get_inactivity_timeout()
      86400
  """
  def get_inactivity_timeout do
    get_config(@inactivity_timeout_key, 60 * 60 * 24)
  end

  @doc """
  Revokes a session.

  ## Examples

      iex> revoke_session(session)
      {:ok, %Session{revoked_at: ~U[2023-01-01 12:00:00Z]}}
  """
  def revoke_session(%Session{} = session) do
    session
    |> Ecto.Changeset.change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  # Updates the user's login information.
  defp update_user_login_info(%User{} = user, attrs) do
    ip_address = Map.get(attrs, "ip_address", nil)
    |> Security.anonymize_ip()
    
    user
    |> Ecto.Changeset.change(
      last_login_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second), 
      last_login_ip: ip_address
    )
    |> Repo.update()
  end
  
  @doc """
  Revokes all active sessions for a user.
  
  ## Examples
  
      iex> revoke_all_sessions(user)
      {3, nil}
  """
  def revoke_all_sessions(%User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    
    from(s in Session, where: s.user_id == ^user.id and is_nil(s.revoked_at))
    |> Repo.update_all(set: [revoked_at: now])
  end
  
  @doc """
  Lists all active sessions for a user.
  Excludes expired sessions and sessions that have been inactive too long.

  ## Examples

      iex> list_active_sessions(user)
      [%Session{}, ...]
  """
  def list_active_sessions(%User{} = user) do
    now = DateTime.utc_now()
    inactivity_timeout = get_config(@inactivity_timeout_key, 60 * 60 * 24)
    inactivity_cutoff = DateTime.add(now, -inactivity_timeout, :second)

    from(s in Session,
      where: s.user_id == ^user.id,
      where: is_nil(s.revoked_at),
      where: s.expires_at > ^now,
      where: is_nil(s.last_active_at) or s.last_active_at > ^inactivity_cutoff,
      order_by: [desc: s.last_active_at]
    )
    |> Repo.all()
  end
  
  @doc """
  Cleans up expired and inactive sessions.

  ## Examples

      iex> cleanup_expired_sessions()
      {42, nil}

      iex> cleanup_expired_sessions(100)
      {100, nil}
  """
  def cleanup_expired_sessions(batch_size \\ 1000) do
    now = DateTime.utc_now()
    inactivity_timeout = get_config(@inactivity_timeout_key, 60 * 60 * 24)
    inactivity_cutoff = DateTime.add(now, -inactivity_timeout, :second)

    # First select session IDs to delete, limited by batch size
    # Delete sessions that are either expired OR have been inactive too long
    session_ids = from(s in Session,
      where: s.expires_at < ^now or
             (not is_nil(s.last_active_at) and s.last_active_at < ^inactivity_cutoff),
      select: s.id,
      limit: ^batch_size)
    |> Repo.all()

    # Then delete the selected sessions
    from(s in Session, where: s.id in ^session_ids)
    |> Repo.delete_all()
  end
  
  @doc """
  Resets a user's password and revokes all their active sessions.
  
  ## Examples
  
      iex> reset_password_and_revoke_sessions(user, "valid_token", %{password: "new_password"})
      {:ok, %{user: %User{}, revoked_sessions: 2}}
      
      iex> reset_password_and_revoke_sessions(user, "invalid_token", %{password: "new_password"})
      {:error, :invalid_token}
  """
  def reset_password_and_revoke_sessions(user, token, attrs) do
    token_hash = Security.hash_token(token)

    # Verify the token matches and is not expired
    cond do
      is_nil(user.reset_token_hash) ->
        {:error, :invalid_token}

      Security.is_expired_reset_token?(user) ->
        {:error, :invalid_token}

      user.reset_token_hash != token_hash ->
        {:error, :invalid_token}

      true ->
        # Token is valid, proceed with password reset and session revocation
        Ecto.Multi.new()
        |> Ecto.Multi.run(:user, fn _repo, _changes ->
          user
          |> Onelist.Accounts.User.reset_password_changeset(attrs)
          |> Ecto.Changeset.change(reset_token_hash: nil, reset_token_created_at: nil)
          |> Repo.update()
        end)
        |> Ecto.Multi.run(:revoked_sessions, fn _repo, _changes ->
          result = revoke_all_sessions(user)
          {:ok, elem(result, 0)}
        end)
        |> Repo.transaction()
    end
  end
  
  @doc """
  Creates a session and updates user login information in a single transaction.
  
  ## Examples
  
      iex> create_session_with_login_tracking(user, %{ip_address: "192.168.1.1"})
      {:ok, %{session: %Session{}, token: "token", user: %User{}}}
  """
  def create_session_with_login_tracking(%User{} = user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:session_result, fn _repo, _changes ->
      create_session(user, attrs)
    end)
    |> Ecto.Multi.run(:user, fn _repo, %{session_result: %{session: _session}} ->
      update_user_login_info(user, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session_result: %{session: session, token: token}, user: updated_user}} ->
        {:ok, %{session: session, token: token, user: updated_user}}
        
      {:error, _operation, reason, _changes} ->
        {:error, reason}
    end
  end
  
  # Gets configuration value, first trying application config, then falling back to default.
  defp get_config(key, default) do
    Application.get_env(:onelist, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end 