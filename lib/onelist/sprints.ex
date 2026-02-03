defmodule Onelist.Sprints do
  @moduledoc """
  The Sprints context.

  Provides query helpers for sprint-related operations including listing sprints,
  getting items linked to a sprint, and finding blocked items.
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Entries.Entry
  alias Onelist.Entries.EntryLink
  alias Onelist.Accounts.User

  @doc """
  Lists all sprint entries for a user.

  ## Options

    * `:limit` - Maximum number of sprints to return (default: 50)
    * `:offset` - Number of sprints to skip (default: 0)
    * `:order_by` - Field to order by (default: :inserted_at)
    * `:order` - Sort order (:asc or :desc, default: :desc)

  ## Examples

      iex> list_sprints(user)
      [%Entry{entry_type: "sprint"}, ...]
  """
  def list_sprints(%User{} = user, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    order_by = Keyword.get(opts, :order_by, :inserted_at)
    order = Keyword.get(opts, :order, :desc)

    from(e in Entry,
      where: e.user_id == ^user.id,
      where: e.entry_type == "sprint",
      order_by: [{^order, field(e, ^order_by)}],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc """
  Counts sprint entries for a user.

  ## Examples

      iex> count_sprints(user)
      5
  """
  def count_sprints(%User{} = user) do
    from(e in Entry,
      where: e.user_id == ^user.id,
      where: e.entry_type == "sprint",
      select: count(e.id)
    )
    |> Repo.one()
  end

  @doc """
  Gets a sprint entry by ID for a user.

  Returns nil if the sprint doesn't exist or doesn't belong to the user.

  ## Examples

      iex> get_sprint(user, "uuid")
      %Entry{entry_type: "sprint"}

      iex> get_sprint(user, "nonexistent")
      nil
  """
  def get_sprint(%User{} = user, id) when is_binary(id) do
    from(e in Entry,
      where: e.id == ^id,
      where: e.user_id == ^user.id,
      where: e.entry_type == "sprint"
    )
    |> Repo.one()
  end

  @doc """
  Lists all items linked to a sprint via the `contains` relationship.

  Returns entries where the sprint is the source and link_type is "contains".

  ## Options

    * `:entry_types` - Filter by specific entry types (e.g., ["task", "deliverable"])
    * `:limit` - Maximum number of items to return (default: 100)
    * `:offset` - Number of items to skip (default: 0)

  ## Examples

      iex> list_sprint_items(user, sprint_id)
      [%Entry{}, ...]

      iex> list_sprint_items(user, sprint_id, entry_types: ["task"])
      [%Entry{entry_type: "task"}, ...]
  """
  def list_sprint_items(%User{} = user, sprint_id, opts \\ []) when is_binary(sprint_id) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    entry_types = Keyword.get(opts, :entry_types)

    # First verify the sprint belongs to the user
    case get_sprint(user, sprint_id) do
      nil ->
        {:error, :not_found}

      _sprint ->
        query =
          from(e in Entry,
            join: l in EntryLink,
            on: l.target_entry_id == e.id,
            where: l.source_entry_id == ^sprint_id,
            where: l.link_type == "contains",
            where: e.user_id == ^user.id,
            order_by: [asc: l.inserted_at],
            limit: ^limit,
            offset: ^offset
          )

        query =
          if entry_types do
            where(query, [e, _l], e.entry_type in ^entry_types)
          else
            query
          end

        {:ok, Repo.all(query)}
    end
  end

  @doc """
  Lists all blocked items in a sprint.

  Returns items that:
  1. Are linked to the sprint via `contains`
  2. Have a `blocked_by` relationship to another entry

  ## Options

    * `:include_blocker` - Include the blocking entry info (default: false)
    * `:limit` - Maximum number of items to return (default: 100)
    * `:offset` - Number of items to skip (default: 0)

  ## Examples

      iex> list_blocked_items(user, sprint_id)
      [%Entry{}, ...]

      iex> list_blocked_items(user, sprint_id, include_blocker: true)
      [%{entry: %Entry{}, blocked_by: [%Entry{}, ...]}, ...]
  """
  def list_blocked_items(%User{} = user, sprint_id, opts \\ []) when is_binary(sprint_id) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)
    include_blocker = Keyword.get(opts, :include_blocker, false)

    # First verify the sprint belongs to the user
    case get_sprint(user, sprint_id) do
      nil ->
        {:error, :not_found}

      _sprint ->
        # Get items in sprint that have blocked_by links
        query =
          from(e in Entry,
            join: sprint_link in EntryLink,
            on: sprint_link.target_entry_id == e.id,
            join: block_link in EntryLink,
            on: block_link.source_entry_id == e.id,
            where: sprint_link.source_entry_id == ^sprint_id,
            where: sprint_link.link_type == "contains",
            where: block_link.link_type == "blocked_by",
            where: e.user_id == ^user.id,
            distinct: e.id,
            order_by: [asc: e.inserted_at],
            limit: ^limit,
            offset: ^offset
          )

        entries = Repo.all(query)

        result =
          if include_blocker do
            Enum.map(entries, fn entry ->
              blockers =
                from(e in Entry,
                  join: l in EntryLink,
                  on: l.target_entry_id == e.id,
                  where: l.source_entry_id == ^entry.id,
                  where: l.link_type == "blocked_by"
                )
                |> Repo.all()

              %{entry: entry, blocked_by: blockers}
            end)
          else
            entries
          end

        {:ok, result}
    end
  end

  @doc """
  Gets sprint statistics including item counts by type and status.

  ## Examples

      iex> get_sprint_stats(user, sprint_id)
      {:ok, %{
        total_items: 10,
        blocked_count: 2,
        items_by_type: %{"task" => 5, "deliverable" => 3, "milestone" => 2}
      }}
  """
  def get_sprint_stats(%User{} = user, sprint_id) when is_binary(sprint_id) do
    case get_sprint(user, sprint_id) do
      nil ->
        {:error, :not_found}

      _sprint ->
        # Count items by type
        items_by_type =
          from(e in Entry,
            join: l in EntryLink,
            on: l.target_entry_id == e.id,
            where: l.source_entry_id == ^sprint_id,
            where: l.link_type == "contains",
            where: e.user_id == ^user.id,
            group_by: e.entry_type,
            select: {e.entry_type, count(e.id)}
          )
          |> Repo.all()
          |> Map.new()

        total_items = items_by_type |> Map.values() |> Enum.sum()

        # Count blocked items
        blocked_count =
          from(e in Entry,
            join: sprint_link in EntryLink,
            on: sprint_link.target_entry_id == e.id,
            join: block_link in EntryLink,
            on: block_link.source_entry_id == e.id,
            where: sprint_link.source_entry_id == ^sprint_id,
            where: sprint_link.link_type == "contains",
            where: block_link.link_type == "blocked_by",
            where: e.user_id == ^user.id,
            select: count(e.id, :distinct)
          )
          |> Repo.one()

        {:ok,
         %{
           total_items: total_items,
           blocked_count: blocked_count,
           items_by_type: items_by_type
         }}
    end
  end
end
