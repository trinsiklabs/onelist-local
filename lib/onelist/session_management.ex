defmodule Onelist.SessionManagement do
  @moduledoc """
  Context module for session management functionality.
  Provides functions for managing user sessions.
  """

  alias Onelist.Sessions
  alias Onelist.Sessions.Session
  alias Onelist.Repo

  @doc """
  Gets session management data for a user and current session.

  Returns a map with sessions, grouped sessions by device, and current session ID.
  """
  def get_session_management_data(user, current_session_id) do
    # Get all active sessions
    sessions = Sessions.list_active_sessions(user)

    # Group sessions by device for better organization
    grouped_sessions = group_sessions_by_device(sessions)

    # Return data structure for rendering
    %{
      sessions: sessions,
      grouped_sessions: grouped_sessions,
      current_session_id: current_session_id,
      page_title: "Your Sessions"
    }
  end

  @doc """
  Revokes a specific session.

  Returns {:ok, session} on success or {:error, :not_found} if the session doesn't exist.
  """
  def revoke_session(session_id) do
    session = Repo.get(Session, session_id)

    if session do
      Sessions.revoke_session(session)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Revokes a specific session if it belongs to the specified user.

  Returns {:ok, session} on success, {:error, :not_found} if the session doesn't exist,
  or {:error, :unauthorized} if the session doesn't belong to the user.
  """
  def revoke_user_session(user, session_id) do
    session = Repo.get(Session, session_id)

    cond do
      # Session doesn't exist
      is_nil(session) ->
        {:error, :not_found}

      # Session doesn't belong to user
      session.user_id != user.id ->
        {:error, :unauthorized}

      # Session belongs to user
      true ->
        Sessions.revoke_session(session)
    end
  end

  @doc """
  Revokes all sessions for a user except the current one.

  Returns {:ok, count} where count is the number of sessions revoked.
  """
  def revoke_other_sessions(user, current_session_id) do
    # Get all active sessions except current one
    sessions =
      Sessions.list_active_sessions(user)
      |> Enum.filter(fn session -> session.id != current_session_id end)

    # Revoke each session
    Enum.each(sessions, fn session ->
      Sessions.revoke_session(session)
    end)

    {:ok, length(sessions)}
  end

  # Internal function made public for testing purposes 
  @doc false
  def group_sessions_by_device(sessions) do
    Enum.group_by(sessions, fn session ->
      case session.user_agent do
        user_agent when is_binary(user_agent) ->
          cond do
            String.contains?(user_agent, "iPhone") -> "iPhone"
            String.contains?(user_agent, "Android") -> "Android"
            String.contains?(user_agent, "Mobile") -> "Mobile"
            String.contains?(user_agent, "Tablet") -> "Tablet"
            String.contains?(user_agent, "Windows") -> "Windows"
            String.contains?(user_agent, "Mac") -> "Mac"
            String.contains?(user_agent, "Linux") -> "Linux"
            true -> "Other"
          end

        _ ->
          "Unknown"
      end
    end)
  end
end
