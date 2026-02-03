defmodule Onelist.River.Sessions do
  @moduledoc """
  Manages River conversation sessions.

  Handles session lifecycle:
  - Get or create active session for user
  - Add messages to session
  - Session timeout (configurable, default 30 min)
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.River.{Session, Message}
  alias Onelist.Accounts.User

  @default_timeout_minutes 30
  @default_history_limit 20

  @doc """
  Get or create an active session for the user.

  Returns existing session if last message was within timeout window,
  otherwise creates a new session.
  """
  def get_or_create_session(%User{id: user_id}, opts \\ []) do
    timeout_minutes = Keyword.get(opts, :timeout_minutes, @default_timeout_minutes)
    cutoff = DateTime.add(DateTime.utc_now(), -timeout_minutes, :minute)

    case get_active_session(user_id, cutoff) do
      nil -> create_session(user_id)
      session -> {:ok, session}
    end
  end

  @doc """
  Get the most recent active session for a user.
  """
  def get_active_session(user_id, cutoff \\ nil) do
    cutoff = cutoff || DateTime.add(DateTime.utc_now(), -@default_timeout_minutes, :minute)

    Repo.one(
      from s in Session,
        where: s.user_id == ^user_id,
        where: s.last_message_at > ^cutoff,
        order_by: [desc: s.last_message_at],
        limit: 1
    )
  end

  @doc """
  Create a new session for a user.
  """
  def create_session(user_id) do
    now = DateTime.utc_now()

    %Session{}
    |> Session.changeset(%{
      user_id: user_id,
      started_at: now,
      last_message_at: now,
      message_count: 0
    })
    |> Repo.insert()
  end

  @doc """
  Add a message to a session.

  Updates session's last_message_at and message_count.
  """
  def add_message(%Session{} = session, role, content, opts \\ []) do
    tokens_used = Keyword.get(opts, :tokens_used)
    metadata = Keyword.get(opts, :metadata, %{})

    Repo.transaction(fn ->
      # Create message
      {:ok, message} =
        %Message{}
        |> Message.changeset(%{
          session_id: session.id,
          role: role,
          content: content,
          tokens_used: tokens_used,
          metadata: metadata
        })
        |> Repo.insert()

      # Update session
      {:ok, _session} =
        session
        |> Session.update_changeset(%{
          last_message_at: DateTime.utc_now(),
          message_count: session.message_count + 1
        })
        |> Repo.update()

      message
    end)
  end

  @doc """
  Get conversation history for a session.

  Returns messages in chronological order, limited to most recent N.
  """
  def get_history(%Session{id: session_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_history_limit)

    # Get most recent messages, then reverse for chronological order
    Repo.all(
      from m in Message,
        where: m.session_id == ^session_id,
        order_by: [desc: m.inserted_at],
        limit: ^limit
    )
    |> Enum.reverse()
  end

  @doc """
  Format session history for LLM consumption.

  Returns list of message maps with role and content.
  """
  def format_history_for_llm(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: if(msg.role == "user", do: "user", else: "assistant"),
        content: msg.content
      }
    end)
  end

  @doc """
  Get recent sessions for a user.
  """
  def list_sessions(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    Repo.all(
      from s in Session,
        where: s.user_id == ^user_id,
        order_by: [desc: s.last_message_at],
        limit: ^limit,
        preload: [:messages]
    )
  end

  @doc """
  Close a session and save it as a searchable entry.

  Creates an entry with:
  - source_type: river_session
  - Full conversation as representation
  - Links to any entries that were cited
  """
  def close_session(%Session{} = session) do
    session = Repo.preload(session, [:messages, :user])

    # Format conversation
    transcript = format_transcript(session.messages)

    # Generate title from first user message or timestamp
    title = generate_session_title(session)

    # Create entry (metadata must use string keys for JSONB)
    {:ok, entry} =
      Onelist.Entries.create_entry(session.user, %{
        title: title,
        entry_type: "note",
        source_type: "river_session",
        metadata: %{
          "session_id" => session.id,
          "message_count" => session.message_count,
          "started_at" => session.started_at,
          "closed_at" => DateTime.utc_now()
        }
      })

    # Add transcript as representation
    {:ok, _} =
      Onelist.Entries.add_representation(entry, %{
        type: "transcript",
        content: transcript
      })

    # Mark session as closed in metadata
    session
    |> Session.update_changeset(%{
      metadata: Map.put(session.metadata || %{}, "closed", true)
    })
    |> Repo.update()

    {:ok, entry}
  end

  @doc """
  Format messages as a readable transcript.
  """
  def format_transcript(messages) do
    messages
    |> Enum.sort_by(& &1.inserted_at)
    |> Enum.map(fn msg ->
      time = Calendar.strftime(msg.inserted_at, "%H:%M")
      role = if msg.role == "user", do: "You", else: "River"
      "#{time} #{role}: #{msg.content}"
    end)
    |> Enum.join("\n\n")
  end

  defp generate_session_title(%Session{messages: messages, started_at: started_at}) do
    date = Calendar.strftime(started_at, "%Y-%m-%d %H:%M")

    # Try to get first user message
    first_user_msg = Enum.find(messages, &(&1.role == "user"))

    case first_user_msg do
      nil ->
        "River Session: #{date}"

      msg ->
        # Truncate to first 50 chars
        topic = msg.content |> String.slice(0, 50) |> String.trim()
        topic = if String.length(msg.content) > 50, do: topic <> "...", else: topic
        "River: #{topic}"
    end
  end

  @doc """
  Auto-close old sessions and save them as entries.

  Call this periodically to archive sessions older than the timeout.
  """
  def archive_old_sessions(timeout_minutes \\ 30) do
    cutoff = DateTime.add(DateTime.utc_now(), -timeout_minutes, :minute)

    # Find sessions that are old and not yet closed
    old_sessions =
      Repo.all(
        from s in Session,
          where: s.last_message_at < ^cutoff,
          where: fragment("NOT (metadata->>'closed')::boolean OR metadata->>'closed' IS NULL"),
          preload: [:messages, :user]
      )

    # Close each one
    Enum.map(old_sessions, fn session ->
      case close_session(session) do
        {:ok, entry} -> {:ok, session.id, entry.id}
        error -> error
      end
    end)
  end
end
