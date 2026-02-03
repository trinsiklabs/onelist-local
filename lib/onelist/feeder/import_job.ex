defmodule Onelist.Feeder.ImportJob do
  @moduledoc """
  Schema for one-time import jobs (file uploads, bulk imports).

  Tracks progress and results of importing files like ENEX, Notion exports,
  Obsidian vaults, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_source_types ~w(
    evernote_enex notion_export obsidian_vault apple_notes
    markdown_folder opml bookmarks_html browser_bookmarks
  )
  @valid_statuses ~w(pending processing completed failed cancelled)

  schema "import_jobs" do
    belongs_to :user, Onelist.Accounts.User

    # Job identification
    field :source_type, :string
    field :job_name, :string

    # File info
    field :file_path, :string
    field :file_size_bytes, :integer

    # Job configuration
    field :options, :map

    # Progress tracking
    field :status, :string, default: "pending"
    field :progress_percent, :integer, default: 0
    field :items_total, :integer
    field :items_processed, :integer, default: 0
    field :items_succeeded, :integer, default: 0
    field :items_failed, :integer, default: 0

    # Results
    field :entries_created, :integer, default: 0
    field :assets_uploaded, :integer, default: 0
    field :tags_created, :integer, default: 0
    field :errors, {:array, :map}

    # Timestamps
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Link to created entries
    field :entry_ids, {:array, :binary_id}

    timestamps()
  end

  @doc """
  Creates a changeset for a new import job.
  """
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :source_type,
      :job_name,
      :file_path,
      :file_size_bytes,
      :options
    ])
    |> validate_required([:user_id, :source_type])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> put_change(:status, "pending")
    |> put_change(:progress_percent, 0)
  end

  @doc """
  Updates job status and progress.
  """
  def update_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :status,
      :progress_percent,
      :items_total,
      :items_processed,
      :items_succeeded,
      :items_failed,
      :entries_created,
      :assets_uploaded,
      :tags_created,
      :errors,
      :started_at,
      :completed_at,
      :entry_ids
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:progress_percent, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

  @doc """
  Updates progress counts and calculates percentage.
  """
  def progress_changeset(job, progress) do
    processed = progress[:processed] || 0
    total = progress[:total] || job.items_total || 1

    percent =
      if total > 0 do
        round(processed / total * 100)
      else
        0
      end

    job
    |> cast(
      %{
        items_processed: processed,
        items_succeeded: progress[:succeeded] || 0,
        items_failed: progress[:failed] || 0,
        items_total: total,
        progress_percent: min(percent, 100)
      },
      [:items_processed, :items_succeeded, :items_failed, :items_total, :progress_percent]
    )
  end

  @doc """
  Marks job as completed with final stats.
  """
  def complete_changeset(job, stats) do
    job
    |> cast(
      %{
        status: "completed",
        progress_percent: 100,
        completed_at: DateTime.utc_now(),
        entries_created: stats[:entries_created] || 0,
        assets_uploaded: stats[:assets_uploaded] || 0,
        tags_created: stats[:tags_created] || 0
      },
      [
        :status,
        :progress_percent,
        :completed_at,
        :entries_created,
        :assets_uploaded,
        :tags_created
      ]
    )
  end

  @doc """
  Marks job as failed with error list.
  """
  def fail_changeset(job, errors) do
    job
    |> cast(
      %{
        status: "failed",
        completed_at: DateTime.utc_now(),
        errors: errors
      },
      [:status, :completed_at, :errors]
    )
  end

  @doc """
  Returns list of valid source types.
  """
  def valid_source_types, do: @valid_source_types

  @doc """
  Returns list of valid statuses.
  """
  def valid_statuses, do: @valid_statuses
end
