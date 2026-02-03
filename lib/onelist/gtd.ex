defmodule Onelist.GTD do
  @moduledoc """
  GTD (Getting Things Done) support for Onelist.

  Provides queries and helpers for GTD workflow:
  - Inbox: unclarified items
  - Next Actions: actionable items ready to do
  - Waiting For: delegated/blocked items
  - Projects: multi-step outcomes
  - Someday/Maybe: future possibilities
  - Reference: non-actionable info

  ## Metadata Conventions

  Entries use metadata fields for GTD state:
  - `status`: inbox | next | waiting | someday | reference | complete
  - `context`: @home | @work | @errands | @calls | @computer | @anywhere
  - `project_id`: UUID of parent project entry
  - `due_date`: ISO8601 date string
  - `energy`: low | medium | high
  - `time_estimate`: minutes as integer
  - `waiting_on`: who/what we're waiting for
  - `category`: project | task | idea | question | note
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Entries.Entry
  alias Onelist.Accounts.User

  @statuses ~w(inbox next waiting someday reference complete)
  @contexts ~w(@home @work @errands @calls @computer @anywhere)
  @energies ~w(low medium high)

  def statuses, do: @statuses
  def contexts, do: @contexts
  def energies, do: @energies

  # ============================================
  # Core GTD Lists
  # ============================================

  @doc """
  Get all inbox items (unclarified).
  """
  def inbox_items(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' = ? OR metadata->>'status' IS NULL", "inbox"),
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Get next actions (ready to do).
  """
  def next_actions(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    context = Keyword.get(opts, :context)
    energy = Keyword.get(opts, :energy)

    query =
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' = ?", "next"),
        order_by: [asc: fragment("metadata->>'due_date'"), desc: e.inserted_at],
        limit: ^limit

    query =
      if context,
        do: where(query, [e], fragment("metadata->>'context' = ?", ^context)),
        else: query

    query =
      if energy, do: where(query, [e], fragment("metadata->>'energy' = ?", ^energy)), else: query

    Repo.all(query)
  end

  @doc """
  Get waiting for items (delegated/blocked).
  """
  def waiting_for(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' = ?", "waiting"),
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Get all projects (multi-step outcomes).
  """
  def projects(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    include_complete = Keyword.get(opts, :include_complete, false)

    query =
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'category' = ?", "project"),
        order_by: [desc: e.updated_at],
        limit: ^limit

    query =
      if include_complete do
        query
      else
        where(
          query,
          [e],
          fragment("metadata->>'status' != ? OR metadata->>'status' IS NULL", "complete")
        )
      end

    Repo.all(query)
  end

  @doc """
  Get someday/maybe items.
  """
  def someday_maybe(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' = ?", "someday"),
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Get reference items (non-actionable).
  """
  def reference(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' = ?", "reference"),
        order_by: [desc: e.inserted_at],
        limit: ^limit
    )
  end

  # ============================================
  # Contextual Queries
  # ============================================

  @doc """
  Get next actions by context.
  """
  def by_context(%User{} = user, context) do
    next_actions(user, context: context)
  end

  @doc """
  Get overdue items.
  """
  def overdue(%User{id: user_id}) do
    today = Date.to_iso8601(Date.utc_today())

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' IN ('next', 'waiting')"),
        where: fragment("metadata->>'due_date' < ?", ^today),
        order_by: [asc: fragment("metadata->>'due_date'")]
    )
  end

  @doc """
  Get items due soon (within N days).
  """
  def due_soon(%User{id: user_id}, days \\ 7) do
    today = Date.utc_today()
    future = Date.add(today, days) |> Date.to_iso8601()
    today_str = Date.to_iso8601(today)

    Repo.all(
      from e in Entry,
        where: e.user_id == ^user_id,
        where: fragment("metadata->>'status' IN ('next', 'waiting')"),
        where:
          fragment(
            "metadata->>'due_date' >= ? AND metadata->>'due_date' <= ?",
            ^today_str,
            ^future
          ),
        order_by: [asc: fragment("metadata->>'due_date'")]
    )
  end

  # ============================================
  # Project Health
  # ============================================

  @doc """
  Get project with health metrics.
  """
  def project_health(%Entry{id: project_id, user_id: user_id} = project) do
    # Get all items linked to this project
    items =
      Repo.all(
        from e in Entry,
          join: l in Onelist.Entries.EntryLink,
          on: l.source_entry_id == e.id,
          where: l.target_entry_id == ^project_id,
          where: e.user_id == ^user_id
      )

    total = length(items)
    complete = Enum.count(items, fn e -> e.metadata["status"] == "complete" end)
    has_next = Enum.any?(items, fn e -> e.metadata["status"] == "next" end)

    last_touched =
      items
      |> Enum.map(& &1.updated_at)
      |> Enum.max(DateTime, fn -> project.updated_at end)

    %{
      project: project,
      total_items: total,
      complete_items: complete,
      completion_percentage: if(total > 0, do: round(complete / total * 100), else: 0),
      has_next_action: has_next,
      last_touched: last_touched,
      stale: DateTime.diff(DateTime.utc_now(), last_touched, :day) > 14
    }
  end

  @doc """
  Get all projects with health metrics.
  """
  def projects_with_health(%User{} = user, opts \\ []) do
    user
    |> projects(opts)
    |> Enum.map(&project_health/1)
  end

  @doc """
  Get stale projects (no activity in 14+ days).
  """
  def stale_projects(%User{} = user) do
    user
    |> projects_with_health()
    |> Enum.filter(& &1.stale)
  end

  @doc """
  Get projects without next actions.
  """
  def stuck_projects(%User{} = user) do
    user
    |> projects_with_health()
    |> Enum.reject(& &1.has_next_action)
  end

  # ============================================
  # Weekly Review
  # ============================================

  @doc """
  Get comprehensive GTD state for weekly review.
  """
  def weekly_review_state(%User{} = user) do
    %{
      inbox: inbox_items(user) |> length(),
      next_actions: next_actions(user) |> length(),
      waiting_for: waiting_for(user) |> length(),
      projects: projects(user) |> length(),
      someday_maybe: someday_maybe(user) |> length(),
      overdue: overdue(user) |> length(),
      due_this_week: due_soon(user, 7) |> length(),
      stuck_projects: stuck_projects(user) |> length(),
      stale_projects: stale_projects(user) |> length(),
      last_review: user.last_weekly_review,
      days_since_review: days_since_review(user)
    }
  end

  @doc """
  Calculate days since last weekly review.
  """
  def days_since_review(%User{last_weekly_review: nil}), do: nil

  def days_since_review(%User{last_weekly_review: last_review}) do
    DateTime.diff(DateTime.utc_now(), last_review, :day)
  end

  @doc """
  Check if weekly review is due (7+ days since last review).
  """
  def review_due?(%User{} = user) do
    case days_since_review(user) do
      nil -> true
      days -> days >= 7
    end
  end

  @doc """
  Mark weekly review as completed.
  """
  def complete_weekly_review(%User{} = user) do
    user
    |> Ecto.Changeset.change(last_weekly_review: DateTime.utc_now())
    |> Repo.update()
  end

  # ============================================
  # GTD State Summary (for River)
  # ============================================

  @doc """
  Get GTD state summary for River context.

  Returns counts and actionable insights.
  """
  def state_summary(%User{} = user) do
    inbox = inbox_items(user)
    next = next_actions(user)
    waiting = waiting_for(user)
    overdue_items = overdue(user)
    due_soon_items = due_soon(user, 3)
    stuck = stuck_projects(user)
    days_since = days_since_review(user)

    %{
      inbox_count: length(inbox),
      next_actions_count: length(next),
      waiting_for_count: length(waiting),
      active_projects: length(projects(user)),
      overdue_count: length(overdue_items),
      due_soon_count: length(due_soon_items),
      stuck_projects_count: length(stuck),

      # Oldest inbox item age in days
      oldest_inbox_days: oldest_age(inbox),

      # Weekly review
      days_since_review: days_since,
      review_due: review_due?(user),

      # Nudges based on state
      nudges: generate_nudges(inbox, next, overdue_items, stuck, days_since)
    }
  end

  defp oldest_age([]), do: 0

  defp oldest_age(items) do
    oldest = items |> Enum.min_by(& &1.inserted_at)
    DateTime.diff(DateTime.utc_now(), oldest.inserted_at, :day)
  end

  defp generate_nudges(inbox, next, overdue, stuck, days_since_review) do
    nudges = []

    nudges =
      if length(inbox) > 10,
        do: ["Inbox has #{length(inbox)} items - time to clarify?" | nudges],
        else: nudges

    nudges =
      if length(inbox) > 0 and length(next) == 0,
        do: ["No next actions defined - what's the next step?" | nudges],
        else: nudges

    nudges =
      if length(overdue) > 0,
        do: ["#{length(overdue)} overdue items need attention" | nudges],
        else: nudges

    nudges =
      if length(stuck) > 0,
        do: ["#{length(stuck)} projects have no next action" | nudges],
        else: nudges

    # Weekly review nudge
    nudges =
      case days_since_review do
        nil -> ["Weekly review never done - let's do one!" | nudges]
        days when days >= 14 -> ["#{days} days since last weekly review - overdue!" | nudges]
        days when days >= 7 -> ["Weekly review due (#{days} days ago)" | nudges]
        _ -> nudges
      end

    Enum.reverse(nudges)
  end
end
