defmodule Onelist.River do
  @moduledoc """
  River Agent - Onelist's intelligent assistant.

  River provides:
  - Natural language queries over user's knowledge base
  - Intelligent entry filing and classification
  - GTD-based task and project management
  - Proactive reminders and coaching

  River is the singular AI personality of Onelist - the one assistant
  users build a relationship with.
  """

  alias Onelist.River.{Entries, GTD, Chat}

  # ============================================
  # CHAT / CONVERSATION
  # ============================================

  @doc """
  Process a message from the user and generate a response.

  ## Options
    * `:conversation_id` - Use specific conversation (default: get/create active)
  """
  def chat(user_id, message, opts \\ []) do
    Chat.process(user_id, message, opts)
  end

  @doc """
  Get conversation by ID.
  """
  def get_conversation(conversation_id) do
    Entries.get_conversation_messages(conversation_id)
  end

  @doc """
  List conversations for user.
  """
  def list_conversations(user_id, opts \\ []) do
    import Ecto.Query
    limit = Keyword.get(opts, :limit, 20)
    
    Onelist.Repo.all(
      from e in Onelist.Entries.Entry,
        where: e.user_id == ^user_id,
        where: e.entry_type == "river_conversation",
        order_by: [desc: e.updated_at],
        limit: ^limit
    )
  end

  # ============================================
  # QUERIES
  # ============================================

  @doc """
  Execute a natural language query over user's entries.
  """
  def query(user_id, query_text, opts \\ []) do
    Chat.Query.execute(user_id, query_text, opts)
  end

  @doc """
  Get a briefing for the user.
  """
  def briefing(user_id, type \\ :daily) do
    case type do
      :daily -> {:ok, GTD.daily_review_data(user_id)}
      :weekly -> {:ok, GTD.weekly_review_data(user_id)}
      _ -> {:error, :invalid_briefing_type}
    end
  end

  # ============================================
  # GTD / TASKS
  # ============================================

  defdelegate get_inbox(user_id), to: GTD
  defdelegate get_next_actions(user_id, opts \\ []), to: GTD
  defdelegate get_waiting_for(user_id, opts \\ []), to: GTD
  defdelegate get_someday_maybe(user_id), to: GTD
  defdelegate quick_capture(user_id, title, opts \\ []), to: GTD
  defdelegate process_inbox_item(task_id, decisions), to: GTD
  defdelegate daily_review_data(user_id), to: GTD
  defdelegate weekly_review_data(user_id), to: GTD

  @doc """
  Create a task.
  """
  def create_task(user_id, attrs) do
    Entries.create_task(user_id, attrs)
  end

  @doc """
  Complete a task.
  """
  def complete_task(task_id) do
    Entries.complete_task(task_id)
  end

  @doc """
  List tasks with optional filters.
  """
  def list_tasks(user_id, opts \\ []) do
    Entries.list_tasks(user_id, opts)
  end

  @doc """
  Get a task by ID.
  """
  def get_task(task_id) do
    Entries.get_task(task_id)
  end

  @doc """
  Update a task.
  """
  def update_task(task_id, attrs) do
    Entries.update_task(task_id, attrs)
  end

  @doc """
  Find task by fuzzy title match.
  """
  def find_task_by_title(user_id, title) do
    Entries.find_task_by_title(user_id, title)
  end
end
