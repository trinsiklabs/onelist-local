defmodule Onelist.Searcher.EmbeddingJob do
  @moduledoc """
  Schema for tracking embedding job status.

  While Oban handles the actual job queue, this table provides
  visibility into embedding status for the API and UI.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending processing completed failed)

  schema "embedding_jobs" do
    field :oban_job_id, :integer
    field :status, :string, default: "pending"
    field :priority, :integer, default: 0

    field :attempts, :integer, default: 0
    field :max_attempts, :integer, default: 3
    field :last_error, :string

    field :scheduled_at, :utc_datetime_usec
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :entry, Onelist.Entries.Entry

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:entry_id, :scheduled_at]
  @optional_fields [
    :oban_job_id,
    :status,
    :priority,
    :attempts,
    :max_attempts,
    :last_error,
    :started_at,
    :completed_at
  ]

  @doc """
  Creates a changeset for an embedding job.
  """
  def changeset(job, attrs) do
    job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:entry_id)
  end

  @doc """
  Creates a changeset for creating a new pending job.
  """
  def create_changeset(entry_id, opts \\ []) do
    attrs = %{
      entry_id: entry_id,
      scheduled_at: Keyword.get(opts, :scheduled_at, DateTime.utc_now()),
      priority: Keyword.get(opts, :priority, 0),
      status: "pending"
    }

    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Updates the job to processing status.
  """
  def mark_processing(job) do
    changeset(job, %{
      status: "processing",
      started_at: DateTime.utc_now(),
      attempts: (job.attempts || 0) + 1
    })
  end

  @doc """
  Updates the job to completed status.
  """
  def mark_completed(job) do
    changeset(job, %{
      status: "completed",
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Updates the job to failed status with error message.
  """
  def mark_failed(job, error_message) do
    changeset(job, %{
      status: "failed",
      last_error: error_message,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns the list of valid statuses.
  """
  def statuses, do: @statuses
end
