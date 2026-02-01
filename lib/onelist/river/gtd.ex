defmodule Onelist.River.GTD do
  @moduledoc """
  Getting Things Done (GTD) functionality for River.

  Implements the core GTD workflow:
  - Capture → Clarify → Organize → Reflect → Engage
  - Inbox, Next Actions, Waiting For, Someday/Maybe buckets
  - Context-based filtering (@phone, @computer, etc.)
  """

  alias Onelist.River.Entries, as: RiverEntries
  alias Onelist.Entries

  @valid_buckets ~w(inbox next_actions waiting_for someday_maybe)
  @standard_contexts ~w(@phone @computer @home @errands @office @anywhere)
  @energy_contexts ~w(@energy:high @energy:low)

  # ============================================
  # BUCKET ACCESSORS
  # ============================================

  @doc """
  Get inbox items for a user.
  """
  def get_inbox(user_id) do
    RiverEntries.list_tasks(user_id, bucket: "inbox", status: "pending")
  end

  @doc """
  Get inbox count.
  """
  def inbox_count(user_id) do
    get_inbox(user_id) |> length()
  end

  @doc """
  Get next actions for a user.

  ## Options
    * `:context` - Filter by context (@phone, @computer, etc.)
  """
  def get_next_actions(user_id, opts \\ []) do
    context = Keyword.get(opts, :context)
    RiverEntries.list_tasks(user_id, bucket: "next_actions", status: "pending", context: context)
  end

  @doc """
  Get waiting-for items.

  ## Options
    * `:waiting_on` - Filter by person name
  """
  def get_waiting_for(user_id, opts \\ []) do
    tasks = RiverEntries.list_tasks(user_id, bucket: "waiting_for", status: "pending")

    case Keyword.get(opts, :waiting_on) do
      nil ->
        tasks

      person ->
        Enum.filter(tasks, &(&1.metadata["waiting_on"] == person))
    end
  end

  @doc """
  Get someday/maybe items.
  """
  def get_someday_maybe(user_id) do
    RiverEntries.list_tasks(user_id, bucket: "someday_maybe", status: "pending")
  end

  # ============================================
  # CONTEXT VALIDATION
  # ============================================

  @doc """
  Check if a context string is valid.
  """
  def valid_context?(context) when is_binary(context) do
    cond do
      context in @standard_contexts -> true
      context in @energy_contexts -> true
      context =~ ~r/^@agenda:.+$/ -> true
      true -> false
    end
  end

  def valid_context?(_), do: false

  @doc """
  List all standard contexts.
  """
  def list_contexts do
    @standard_contexts
  end

  # ============================================
  # BUCKET VALIDATION
  # ============================================

  @doc """
  Check if a bucket name is valid.
  """
  def valid_bucket?(bucket) when bucket in @valid_buckets, do: true
  def valid_bucket?(_), do: false

  # ============================================
  # INBOX PROCESSING
  # ============================================

  @doc """
  Process an inbox item with decisions.

  ## Decisions
    * `:bucket` - Target bucket (next_actions, waiting_for, someday_maybe)
    * `:context` - GTD context to assign
    * `:waiting_on` - Person name if moving to waiting_for
    * `:action` - Special action (:delete to remove)
  """
  def process_inbox_item(task_id, decisions) do
    bucket = Map.get(decisions, :bucket)
    action = Map.get(decisions, :action)

    cond do
      action == :delete ->
        case RiverEntries.get_task(task_id) do
          nil -> {:error, :not_found}
          task ->
            Entries.delete_entry(task)
            {:ok, :deleted}
        end

      bucket && not valid_bucket?(bucket) ->
        {:error, :invalid_bucket}

      bucket ->
        updates = %{}

        updates =
          if bucket, do: Map.put(updates, :gtd_bucket, bucket), else: updates

        updates =
          if context = Map.get(decisions, :context),
            do: Map.put(updates, :gtd_context, context),
            else: updates

        updates =
          if waiting_on = Map.get(decisions, :waiting_on),
            do: Map.put(updates, :waiting_on, waiting_on),
            else: updates

        RiverEntries.update_task(task_id, updates)

      true ->
        {:error, :no_action}
    end
  end

  # ============================================
  # QUICK CAPTURE
  # ============================================

  @doc """
  Quick capture - create a task in inbox.

  ## Options
    * `:context` - Pre-set context (still goes to inbox for processing)
  """
  def quick_capture(user_id, title, opts \\ []) do
    context = Keyword.get(opts, :context)

    attrs = %{
      title: title,
      gtd_bucket: "inbox",
      source_type: "quick_capture"
    }

    attrs = if context, do: Map.put(attrs, :gtd_context, context), else: attrs

    RiverEntries.create_task(user_id, attrs)
  end

  # ============================================
  # REVIEWS
  # ============================================

  @doc """
  Get GTD state summary for a user.
  
  Returns the same structure as Onelist.GTD.state_summary/1.
  """
  def get_gtd_state(user_id) do
    try do
      user = Onelist.Accounts.get_user!(user_id)
      Onelist.GTD.state_summary(user)
    rescue
      Ecto.NoResultsError -> %{inbox_count: 0, active_projects: 0, nudges: []}
    end
  end

  @doc """
  Get data for daily review.
  """
  def daily_review_data(user_id) do
    %{
      date: Date.utc_today(),
      inbox_count: inbox_count(user_id),
      due_today: RiverEntries.list_tasks_due_today(user_id),
      overdue: RiverEntries.list_overdue_tasks(user_id),
      next_actions_count: get_next_actions(user_id) |> length(),
      waiting_for_count: get_waiting_for(user_id) |> length()
    }
  end

  @doc """
  Get data for weekly review.
  """
  def weekly_review_data(user_id) do
    week_start = Date.beginning_of_week(Date.utc_today())

    %{
      week_of: week_start,
      inbox_items: get_inbox(user_id),
      next_actions: get_next_actions(user_id),
      waiting_for: get_waiting_for(user_id),
      someday_maybe: get_someday_maybe(user_id),
      # These would need additional queries for tasks completed this week
      completed_this_week: [],
      stale_projects: []
    }
  end
end
