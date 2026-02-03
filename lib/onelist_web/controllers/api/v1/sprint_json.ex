defmodule OnelistWeb.Api.V1.SprintJSON do
  @moduledoc """
  JSON rendering for Sprint API responses.
  """

  alias Onelist.Entries.Entry

  @doc """
  Renders a list of sprints.
  """
  def index(%{sprints: sprints, total: total}) do
    %{
      sprints: Enum.map(sprints, &sprint_data/1),
      total: total
    }
  end

  @doc """
  Renders a single sprint with stats.
  """
  def show(%{sprint: sprint, stats: stats}) do
    %{
      sprint: sprint_data(sprint),
      stats: stats
    }
  end

  @doc """
  Renders items linked to a sprint.
  """
  def items(%{items: items, count: count}) do
    %{
      items: Enum.map(items, &entry_data/1),
      count: count
    }
  end

  @doc """
  Renders blocked items in a sprint.
  """
  def blocked(%{blocked_items: items, count: count, include_blocker: include_blocker}) do
    blocked_data =
      if include_blocker do
        Enum.map(items, fn %{entry: entry, blocked_by: blockers} ->
          %{
            entry: entry_data(entry),
            blocked_by: Enum.map(blockers, &entry_data/1)
          }
        end)
      else
        Enum.map(items, &entry_data/1)
      end

    %{
      blocked_items: blocked_data,
      count: count
    }
  end

  # Sprint-specific data (could include sprint metadata like dates, goals)
  defp sprint_data(%Entry{} = sprint) do
    %{
      id: sprint.id,
      public_id: sprint.public_id,
      title: sprint.title,
      entry_type: sprint.entry_type,
      metadata: sprint.metadata,
      inserted_at: sprint.inserted_at,
      updated_at: sprint.updated_at
    }
  end

  # Generic entry data
  defp entry_data(%Entry{} = entry) do
    %{
      id: entry.id,
      public_id: entry.public_id,
      title: entry.title,
      entry_type: entry.entry_type,
      source_type: entry.source_type,
      metadata: entry.metadata,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end
end
