defmodule Onelist.Workers.SnapshotWorker do
  @moduledoc """
  Oban worker that creates periodic snapshots for active representations.

  This worker ensures that version history can be efficiently reconstructed
  by creating full content snapshots periodically, rather than requiring
  the application of many incremental diffs.

  ## Job Types

  ### Single Representation Snapshot

  Creates a snapshot for a specific representation:

      %{representation_id: "uuid", user_id: "uuid"}
      |> Onelist.Workers.SnapshotWorker.new()
      |> Oban.insert()

  ### Sweep (Scheduled Daily)

  Finds all representations needing snapshots and queues individual jobs:

      %{action: "sweep"}
      |> Onelist.Workers.SnapshotWorker.new()
      |> Oban.insert()

  The sweep job is scheduled to run daily at 3 AM via Oban.Plugins.Cron.
  """

  use Oban.Worker,
    queue: :snapshots,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue]]

  alias Onelist.Entries
  alias Onelist.Accounts.User
  alias Onelist.Repo

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"representation_id" => rep_id, "user_id" => user_id}}) do
    with {:ok, representation} <- get_representation(rep_id),
         {:ok, user} <- get_user(user_id),
         true <- Entries.needs_snapshot?(representation) do
      case Entries.create_snapshot(representation, user) do
        {:ok, _version} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      false ->
        # No snapshot needed, job completed successfully
        :ok

      {:error, :not_found} ->
        # Resource no longer exists, don't retry
        :discard

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"action" => "sweep"}}) do
    representations_needing_snapshots()
    |> Enum.each(fn {rep, user_id} ->
      %{"representation_id" => rep.id, "user_id" => user_id}
      |> __MODULE__.new(schedule_in: jitter())
      |> Oban.insert()
    end)

    :ok
  end

  # Add some random jitter (0-60 seconds) to spread out the load
  defp jitter do
    :rand.uniform(60)
  end

  defp get_representation(id) do
    case Entries.get_representation(id) do
      nil -> {:error, :not_found}
      rep -> {:ok, rep}
    end
  end

  defp get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Finds all representations that need a snapshot.

  A representation needs a snapshot if:
  - It has been modified (has versions)
  - AND either:
    - No snapshot exists
    - More than 24 hours since last snapshot
    - More than 50 diffs since last snapshot

  Returns a list of {representation, user_id} tuples.
  """
  def representations_needing_snapshots do
    # Find representations that have versions (have been edited)
    # and either have no recent snapshot or many diffs since last snapshot
    one_day_ago = DateTime.add(DateTime.utc_now(), -24 * 3600, :second)

    # Get representations with recent activity
    active_representations =
      from(r in Onelist.Entries.Representation,
        join: e in assoc(r, :entry),
        join: v in Onelist.Entries.RepresentationVersion,
        on: v.representation_id == r.id,
        where: v.inserted_at > ^one_day_ago,
        group_by: [r.id, e.user_id],
        select: {r, e.user_id}
      )
      |> Repo.all()

    # Filter to only those that actually need a snapshot
    active_representations
    |> Enum.filter(fn {rep, _user_id} ->
      Entries.needs_snapshot?(rep)
    end)
  end

  @doc """
  Manually triggers a snapshot for a representation if needed.

  Useful for calling after significant edits.
  """
  def maybe_queue_snapshot(%Onelist.Entries.Representation{} = representation, user_id) do
    if Entries.needs_snapshot?(representation) do
      %{"representation_id" => representation.id, "user_id" => user_id}
      |> __MODULE__.new()
      |> Oban.insert()
    else
      {:ok, :not_needed}
    end
  end
end
