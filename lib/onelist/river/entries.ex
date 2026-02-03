defmodule Onelist.River.Entries do
  @moduledoc """
  Query helpers for River entries-based data model.

  River uses the existing entries/representations ecosystem:
  - Conversations = entries with `entry_type: "conversation"`
  - Messages = representations with `representation_type: "chat_message"`
  - Tasks = entries with `entry_type: "task"` and GTD metadata
  """

  import Ecto.Query, warn: false

  alias Onelist.Repo
  alias Onelist.Entries
  alias Onelist.Entries.{Entry, Representation}
  alias Onelist.Accounts

  # ============================================
  # CONVERSATIONS
  # ============================================

  @doc """
  Create a new River conversation entry.
  """
  def create_conversation(user_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    user = Accounts.get_user!(user_id)

    # Skip auto-processing for River internal entries (conversations don't need Reader/Searcher)
    Entries.create_entry(
      user,
      %{
        entry_type: "conversation",
        title: "Conversation - #{Date.utc_today()}",
        metadata: %{
          "conversation_type" => "river",
          "status" => "active",
          "message_count" => 0,
          "started_at" => now,
          "last_message_at" => nil
        }
      },
      skip_auto_processing: true
    )
  end

  @doc """
  Get the most recent active conversation for a user.
  """
  def get_active_conversation(user_id) do
    Entry
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.entry_type == "conversation")
    |> where([e], fragment("?->>'status' = ?", e.metadata, "active"))
    |> where([e], fragment("?->>'conversation_type' = ?", e.metadata, "river"))
    |> order_by([e], desc: e.updated_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get or create an active conversation for the user.
  """
  def get_or_create_conversation(user_id) do
    case get_active_conversation(user_id) do
      nil -> create_conversation(user_id)
      conversation -> {:ok, conversation}
    end
  end

  @doc """
  Archive a conversation.
  """
  def archive_conversation(conversation_id) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    conversation = Repo.get!(Entry, conversation_id)

    metadata =
      conversation.metadata
      |> Map.put("status", "archived")
      |> Map.put("archived_at", now)

    conversation
    |> Ecto.Changeset.change(%{metadata: metadata})
    |> Repo.update()
  end

  # ============================================
  # MESSAGES
  # ============================================

  @doc """
  Add a message to a conversation.

  ## Options
    * `:model` - LLM model used (for assistant messages)
    * `:input_tokens` - Input token count
    * `:output_tokens` - Output token count
    * `:response_time_ms` - Response time in milliseconds
    * `:intent` - Classified intent
    * `:retrieved_entry_ids` - Entry IDs used as context
    * `:actions_taken` - Actions taken during processing
  """
  def add_message(conversation_id, role, content, opts \\ []) do
    conversation = Repo.get!(Entry, conversation_id)
    current_count = conversation.metadata["message_count"] || 0
    sequence = current_count + 1

    role_string = to_string(role)

    metadata = %{
      "role" => role_string,
      "sequence" => sequence
    }

    # Add optional metadata for assistant messages
    metadata =
      Enum.reduce(opts, metadata, fn
        {:model, v}, acc -> Map.put(acc, "model", v)
        {:input_tokens, v}, acc -> Map.put(acc, "input_tokens", v)
        {:output_tokens, v}, acc -> Map.put(acc, "output_tokens", v)
        {:response_time_ms, v}, acc -> Map.put(acc, "response_time_ms", v)
        {:intent, v}, acc -> Map.put(acc, "intent", to_string(v))
        {:retrieved_entry_ids, v}, acc -> Map.put(acc, "retrieved_entry_ids", v)
        {:actions_taken, v}, acc -> Map.put(acc, "actions_taken", v)
        _, acc -> acc
      end)

    # Create representation
    representation_attrs = %{
      entry_id: conversation_id,
      type: "chat_message",
      content: content,
      mime_type: "text/plain",
      metadata: metadata
    }

    result =
      %Representation{}
      |> Representation.changeset(representation_attrs)
      |> Repo.insert()

    # Update conversation message count and last_message_at
    case result do
      {:ok, message} ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        updated_metadata =
          conversation.metadata
          |> Map.put("message_count", sequence)
          |> Map.put("last_message_at", now)

        conversation
        |> Ecto.Changeset.change(%{metadata: updated_metadata})
        |> Repo.update()

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Get messages for a conversation in order.

  ## Options
    * `:limit` - Maximum number of messages to return (returns most recent)
  """
  def get_conversation_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    query =
      Representation
      |> where([r], r.entry_id == ^conversation_id)
      |> where([r], r.type == "chat_message")
      |> order_by([r], asc: fragment("(?->>'sequence')::int", r.metadata))

    query =
      if limit do
        # Get last N messages by using a subquery
        subquery =
          Representation
          |> where([r], r.entry_id == ^conversation_id)
          |> where([r], r.type == "chat_message")
          |> order_by([r], desc: fragment("(?->>'sequence')::int", r.metadata))
          |> limit(^limit)
          |> select([r], r.id)

        query
        |> where([r], r.id in subquery(subquery))
      else
        query
      end

    Repo.all(query)
  end

  # ============================================
  # TASKS
  # ============================================

  @valid_buckets ~w(inbox next_actions waiting_for someday_maybe)
  @valid_contexts ~w(@phone @computer @home @errands @office @anywhere @energy:high @energy:low)

  @doc """
  Create a task entry with GTD metadata.
  """
  def create_task(user_id, attrs) do
    title = Map.get(attrs, :title) || Map.get(attrs, "title")
    user = Accounts.get_user!(user_id)

    gtd_metadata = %{
      "gtd_bucket" => Map.get(attrs, :gtd_bucket) || Map.get(attrs, "gtd_bucket") || "inbox",
      "gtd_context" => Map.get(attrs, :gtd_context) || Map.get(attrs, "gtd_context"),
      "status" => Map.get(attrs, :status) || Map.get(attrs, "status") || "pending",
      "priority" => Map.get(attrs, :priority) || Map.get(attrs, "priority") || 0,
      "due_date" => Map.get(attrs, :due_date) || Map.get(attrs, "due_date"),
      "due_time" => Map.get(attrs, :due_time) || Map.get(attrs, "due_time"),
      "effort_estimate" => Map.get(attrs, :effort_estimate) || Map.get(attrs, "effort_estimate"),
      "effort_minutes" => Map.get(attrs, :effort_minutes) || Map.get(attrs, "effort_minutes"),
      "waiting_on" => Map.get(attrs, :waiting_on) || Map.get(attrs, "waiting_on"),
      "project_id" => Map.get(attrs, :project_id) || Map.get(attrs, "project_id"),
      "source_type" => Map.get(attrs, :source_type) || Map.get(attrs, "source_type"),
      "source_entry_id" => Map.get(attrs, :source_entry_id) || Map.get(attrs, "source_entry_id")
    }

    # Remove nil values
    gtd_metadata =
      gtd_metadata
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    # Skip auto-processing for tasks (they don't need Reader/Searcher by default)
    Entries.create_entry(
      user,
      %{
        entry_type: "task",
        title: title,
        content: Map.get(attrs, :description) || Map.get(attrs, "description"),
        metadata: gtd_metadata
      },
      skip_auto_processing: true
    )
  end

  @doc """
  List tasks for a user with optional filters.

  ## Options
    * `:bucket` - Filter by GTD bucket
    * `:context` - Filter by GTD context
    * `:status` - Filter by status (default: "pending")
  """
  def list_tasks(user_id, opts \\ []) do
    status = Keyword.get(opts, :status, "pending")
    bucket = Keyword.get(opts, :bucket)
    context = Keyword.get(opts, :context)

    query =
      Entry
      |> where([e], e.user_id == ^user_id)
      |> where([e], e.entry_type == "task")
      |> where([e], fragment("?->>'status' = ?", e.metadata, ^status))

    query =
      if bucket do
        where(query, [e], fragment("?->>'gtd_bucket' = ?", e.metadata, ^bucket))
      else
        query
      end

    query =
      if context do
        where(query, [e], fragment("?->>'gtd_context' = ?", e.metadata, ^context))
      else
        query
      end

    query
    |> order_by([e], desc: fragment("(?->>'priority')::int", e.metadata))
    |> Repo.all()
  end

  @doc """
  List overdue tasks (due_date < today, status = pending).
  """
  def list_overdue_tasks(user_id) do
    today = Date.utc_today() |> Date.to_string()

    Entry
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.entry_type == "task")
    |> where([e], fragment("?->>'status' = ?", e.metadata, "pending"))
    |> where([e], fragment("?->>'due_date' < ?", e.metadata, ^today))
    |> Repo.all()
  end

  @doc """
  List tasks due today.
  """
  def list_tasks_due_today(user_id) do
    today = Date.utc_today() |> Date.to_string()

    Entry
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.entry_type == "task")
    |> where([e], fragment("?->>'status' = ?", e.metadata, "pending"))
    |> where([e], fragment("?->>'due_date' = ?", e.metadata, ^today))
    |> Repo.all()
  end

  @doc """
  Get a task by ID.
  """
  def get_task(task_id) do
    Entry
    |> where([e], e.id == ^task_id)
    |> where([e], e.entry_type == "task")
    |> Repo.one()
  end

  @doc """
  Complete a task.
  """
  def complete_task(task_id) do
    task = get_task(task_id)

    cond do
      is_nil(task) ->
        {:error, :not_found}

      task.metadata["status"] == "completed" ->
        {:error, :already_completed}

      true ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        metadata =
          task.metadata
          |> Map.put("status", "completed")
          |> Map.put("completed_at", now)

        task
        |> Ecto.Changeset.change(%{metadata: metadata})
        |> Repo.update()
    end
  end

  @doc """
  Move a task to a different bucket.
  """
  def move_to_bucket(task_id, bucket) when bucket in @valid_buckets do
    task = get_task(task_id)

    if task do
      metadata = Map.put(task.metadata, "gtd_bucket", bucket)

      task
      |> Ecto.Changeset.change(%{metadata: metadata})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  def move_to_bucket(_task_id, _bucket), do: {:error, :invalid_bucket}

  @doc """
  Update task attributes.
  """
  def update_task(task_id, attrs) do
    task = get_task(task_id)

    if task do
      # Merge new attrs into metadata
      metadata_updates =
        attrs
        |> Enum.filter(fn {k, _v} ->
          k in [
            :gtd_bucket,
            :gtd_context,
            :priority,
            :due_date,
            :due_time,
            :effort_estimate,
            :effort_minutes,
            :waiting_on,
            :status,
            "gtd_bucket",
            "gtd_context",
            "priority",
            "due_date",
            "due_time",
            "effort_estimate",
            "effort_minutes",
            "waiting_on",
            "status"
          ]
        end)
        |> Enum.map(fn {k, v} -> {to_string(k), v} end)
        |> Map.new()

      new_metadata = Map.merge(task.metadata, metadata_updates)

      # Handle title update separately
      title = Map.get(attrs, :title) || Map.get(attrs, "title") || task.title

      task
      |> Ecto.Changeset.change(%{title: title, metadata: new_metadata})
      |> Repo.update()
    else
      {:error, :not_found}
    end
  end

  @doc """
  Find a task by fuzzy title match.
  """
  def find_task_by_title(user_id, search_term) do
    search_pattern = "%#{String.downcase(search_term)}%"

    Entry
    |> where([e], e.user_id == ^user_id)
    |> where([e], e.entry_type == "task")
    |> where([e], fragment("?->>'status' = ?", e.metadata, "pending"))
    |> where([e], fragment("LOWER(?) LIKE ?", e.title, ^search_pattern))
    |> order_by([e], desc: e.updated_at)
    |> limit(1)
    |> Repo.one()
  end
end
