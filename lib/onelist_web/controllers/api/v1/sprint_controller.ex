defmodule OnelistWeb.Api.V1.SprintController do
  @moduledoc """
  API controller for sprint operations.

  Provides endpoints for listing sprints, getting sprint items, and querying blocked items.
  """

  use OnelistWeb, :controller
  alias Onelist.Sprints

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Lists all sprint entries for the authenticated user.

  ## Query Parameters

    * `limit` - Maximum number of sprints to return (default: 50, max: 100)
    * `offset` - Number of sprints to skip (default: 0)

  ## Response

      200 OK
      {
        "sprints": [
          {
            "id": "uuid",
            "title": "Sprint 009",
            "public_id": "abc123",
            "entry_type": "sprint",
            "metadata": {...},
            "inserted_at": "2026-02-05T...",
            "updated_at": "2026-02-05T..."
          }
        ],
        "total": 5
      }
  """
  def index(conn, params) do
    user = conn.assigns.current_user

    limit = min(params["limit"] || 50, 100)
    offset = params["offset"] || 0

    sprints = Sprints.list_sprints(user, limit: limit, offset: offset)
    total = Sprints.count_sprints(user)

    render(conn, :index, sprints: sprints, total: total)
  end

  @doc """
  Gets a single sprint with its stats.

  ## Response

      200 OK
      {
        "sprint": {
          "id": "uuid",
          "title": "Sprint 009",
          ...
        },
        "stats": {
          "total_items": 10,
          "blocked_count": 2,
          "items_by_type": {"task": 5, "deliverable": 3}
        }
      }
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    case Sprints.get_sprint(user, id) do
      nil ->
        {:error, :not_found}

      sprint ->
        {:ok, stats} = Sprints.get_sprint_stats(user, id)
        render(conn, :show, sprint: sprint, stats: stats)
    end
  end

  @doc """
  Lists all items linked to a sprint.

  ## Query Parameters

    * `entry_types` - Comma-separated list of entry types to filter by (e.g., "task,deliverable")
    * `limit` - Maximum number of items to return (default: 100, max: 500)
    * `offset` - Number of items to skip (default: 0)

  ## Response

      200 OK
      {
        "items": [
          {
            "id": "uuid",
            "title": "Implement feature X",
            "entry_type": "task",
            ...
          }
        ],
        "count": 10
      }

      404 Not Found - Sprint doesn't exist or doesn't belong to user
  """
  def items(conn, %{"sprint_id" => sprint_id} = params) do
    user = conn.assigns.current_user

    limit = min(params["limit"] || 100, 500)
    offset = params["offset"] || 0

    entry_types =
      case params["entry_types"] do
        nil -> nil
        types when is_binary(types) -> String.split(types, ",")
        types when is_list(types) -> types
      end

    opts = [limit: limit, offset: offset]
    opts = if entry_types, do: Keyword.put(opts, :entry_types, entry_types), else: opts

    case Sprints.list_sprint_items(user, sprint_id, opts) do
      {:ok, items} ->
        render(conn, :items, items: items, count: length(items))

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all blocked items in a sprint.

  ## Query Parameters

    * `include_blocker` - If "true", includes the blocking entry info (default: false)
    * `limit` - Maximum number of items to return (default: 100, max: 500)
    * `offset` - Number of items to skip (default: 0)

  ## Response

      200 OK (include_blocker=false)
      {
        "blocked_items": [
          {
            "id": "uuid",
            "title": "Waiting on API",
            "entry_type": "task",
            ...
          }
        ],
        "count": 2
      }

      200 OK (include_blocker=true)
      {
        "blocked_items": [
          {
            "entry": {...},
            "blocked_by": [{...}, ...]
          }
        ],
        "count": 2
      }
  """
  def blocked(conn, %{"sprint_id" => sprint_id} = params) do
    user = conn.assigns.current_user

    limit = min(params["limit"] || 100, 500)
    offset = params["offset"] || 0
    include_blocker = params["include_blocker"] == "true"

    opts = [limit: limit, offset: offset, include_blocker: include_blocker]

    case Sprints.list_blocked_items(user, sprint_id, opts) do
      {:ok, items} ->
        render(conn, :blocked,
          blocked_items: items,
          count: length(items),
          include_blocker: include_blocker
        )

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
