defmodule Onelist.Livelog do
  @moduledoc """
  Context module for Livelog functionality.

  Livelog is a real-time public display of Stream's conversations,
  with automatic privacy redaction.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Livelog.{Message, AuditLog}

  @doc """
  List recent messages for Livelog display.
  Messages are ordered by timestamp, newest first.
  """
  def list_recent_messages(limit \\ 50) do
    Message
    |> where([m], m.blocked == false)
    |> order_by([m], desc: m.original_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  List messages before a given timestamp (for pagination/load-more).
  """
  def list_messages_before(timestamp, limit \\ 50) do
    Message
    |> where([m], m.blocked == false)
    |> where([m], m.original_timestamp < ^timestamp)
    |> order_by([m], desc: m.original_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get a single message by ID.
  """
  def get_message(id) do
    Repo.get(Message, id)
  end

  @doc """
  Get aggregate statistics for Livelog.
  """
  def get_stats do
    total = Repo.aggregate(Message, :count)

    redacted =
      Repo.aggregate(
        from(m in Message, where: m.redaction_applied == true),
        :count
      )

    blocked = Repo.aggregate(AuditLog, :count, where: [action: "blocked"])

    %{
      total_messages: total || 0,
      redacted_count: redacted || 0,
      blocked_count: blocked || 0,
      redaction_rate:
        if(total && total > 0, do: Float.round(redacted / total * 100, 1), else: 0.0)
    }
  end

  @doc """
  Get messages by role (user/assistant).
  """
  def list_messages_by_role(role, limit \\ 50) when role in ["user", "assistant", "system"] do
    Message
    |> where([m], m.blocked == false)
    |> where([m], m.role == ^role)
    |> order_by([m], desc: m.original_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Search messages by content (basic text search).
  Note: Searches REDACTED content only, never original.
  """
  def search_messages(query_string, limit \\ 50) do
    search_term = "%#{query_string}%"

    Message
    |> where([m], m.blocked == false)
    |> where([m], ilike(m.content, ^search_term))
    |> order_by([m], desc: m.original_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get messages from a specific date range.
  """
  def list_messages_in_range(start_time, end_time, limit \\ 100) do
    Message
    |> where([m], m.blocked == false)
    |> where([m], m.original_timestamp >= ^start_time)
    |> where([m], m.original_timestamp <= ^end_time)
    |> order_by([m], desc: m.original_timestamp)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Count total messages (for stats display).
  """
  def count_messages do
    Repo.aggregate(
      from(m in Message, where: m.blocked == false),
      :count
    ) || 0
  end

  @doc """
  Get the most recent message timestamp.
  """
  def last_message_time do
    Message
    |> where([m], m.blocked == false)
    |> order_by([m], desc: m.original_timestamp)
    |> limit(1)
    |> select([m], m.original_timestamp)
    |> Repo.one()
  end

  @doc """
  Get audit log entries for compliance review.
  """
  def list_audit_entries(limit \\ 100) do
    AuditLog
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get audit entries for a specific action type.
  """
  def list_audit_by_action(action, limit \\ 100)
      when action in ["redacted", "blocked", "allowed"] do
    AuditLog
    |> where([a], a.action == ^action)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
