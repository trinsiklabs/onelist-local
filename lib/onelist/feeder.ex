defmodule Onelist.Feeder do
  @moduledoc """
  Feeder Agent - Onelist's unified gateway for external content.

  Handles all data ingestion from outside sources—whether one-time imports
  or continuous synchronization—converting foreign formats into Onelist entries.

  ## Core Capabilities

  | Capability | Description |
  |------------|-------------|
  | **One-time Import** | Bulk import from export files (ENEX, ZIP, folders) |
  | **Continuous Sync** | Ongoing synchronization via APIs, webhooks, polling |
  | **Format Conversion** | Transform source formats to Onelist entries |
  | **Agent Orchestration** | Trigger post-import processing chain |

  ## Supported Sources

  Currently:
  - RSS/Atom feeds (continuous sync)

  Planned:
  - Evernote (ENEX import + API sync)
  - Notion (export import + OAuth sync)
  - Obsidian (vault import + REST API sync)
  - Apple Notes (export import)
  - Web Clipper (URL capture)

  ## Usage

  ```elixir
  # Create an RSS feed integration
  {:ok, integration} = Feeder.create_integration(user_id, %{
    source_type: "rss",
    source_name: "Tech News",
    credentials: %{"feed_url" => "https://example.com/feed.xml"},
    sync_frequency_minutes: 60
  })

  # Trigger a sync
  {:ok, job} = Feeder.enqueue_sync(integration)

  # Create a one-time import
  {:ok, import_job} = Feeder.create_import_job(user_id, %{
    source_type: "evernote_enex",
    file_path: "/tmp/exports/notes.enex"
  })

  {:ok, job} = Feeder.enqueue_import(import_job)
  ```
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Feeder.{ExternalIntegration, ImportJob, SourceEntryMapping}
  alias Onelist.Feeder.Workers.OrchestratorWorker

  # Adapter registry - maps source_type to adapter module
  @adapters %{
    "rss" => Onelist.Feeder.Adapters.RSS
    # Future adapters:
    # "evernote" => Onelist.Feeder.Adapters.Evernote,
    # "notion" => Onelist.Feeder.Adapters.Notion,
    # "obsidian" => Onelist.Feeder.Adapters.Obsidian,
  }

  # ============================================
  # EXTERNAL INTEGRATIONS
  # ============================================

  @doc """
  Creates a new external integration.

  ## Parameters

  - `user_id` - The user ID
  - `attrs` - Integration attributes:
    - `:source_type` - Required. One of: #{inspect(Map.keys(@adapters))}
    - `:source_name` - Optional. User-friendly name
    - `:credentials` - Required. Source-specific credentials
    - `:sync_enabled` - Optional. Enable sync (default: true)
    - `:sync_frequency_minutes` - Optional. Sync interval (default: 60)
    - `:sync_filter` - Optional. Source-specific filters

  ## Returns

  - `{:ok, integration}` - Created integration
  - `{:error, changeset}` - Validation failed
  """
  def create_integration(user_id, attrs) do
    %ExternalIntegration{}
    |> ExternalIntegration.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Gets an integration by ID.
  """
  def get_integration(id) do
    Repo.get(ExternalIntegration, id)
  end

  @doc """
  Gets an integration by ID, raises if not found.
  """
  def get_integration!(id) do
    Repo.get!(ExternalIntegration, id)
  end

  @doc """
  Lists all integrations for a user.

  ## Options

  - `:source_type` - Filter by source type
  - `:sync_enabled` - Filter by sync status
  """
  def list_integrations(user_id, opts \\ []) do
    query = from i in ExternalIntegration, where: i.user_id == ^user_id

    query =
      case Keyword.get(opts, :source_type) do
        nil -> query
        type -> from i in query, where: i.source_type == ^type
      end

    query =
      case Keyword.get(opts, :sync_enabled) do
        nil -> query
        enabled -> from i in query, where: i.sync_enabled == ^enabled
      end

    query
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Updates an integration.
  """
  def update_integration(%ExternalIntegration{} = integration, attrs) do
    integration
    |> ExternalIntegration.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an integration and all associated mappings.
  """
  def delete_integration(%ExternalIntegration{} = integration) do
    Repo.delete(integration)
  end

  @doc """
  Updates sync state after a sync operation.

  ## Sync Result Format

  ```elixir
  %{
    status: :success | :partial | :failed | :syncing,
    cursor: %{...},  # New sync cursor
    stats: %{entries_created: 5, entries_updated: 2, errors: 0},
    error: "Error message"  # Only if failed
  }
  ```
  """
  def update_sync_state(%ExternalIntegration{} = integration, sync_result) do
    attrs = %{
      last_sync_at: DateTime.utc_now(),
      last_sync_status: to_string(sync_result[:status] || :success),
      last_sync_stats: sync_result[:stats],
      sync_cursor: sync_result[:cursor] || integration.sync_cursor,
      last_sync_error: sync_result[:error]
    }

    integration
    |> ExternalIntegration.sync_state_changeset(attrs)
    |> Repo.update()
  end

  # ============================================
  # IMPORT JOBS
  # ============================================

  @doc """
  Creates a new import job.

  ## Parameters

  - `user_id` - The user ID
  - `attrs` - Job attributes:
    - `:source_type` - Required. Type of import (e.g., "evernote_enex")
    - `:job_name` - Optional. User-friendly name
    - `:file_path` - Path to the import file
    - `:file_size_bytes` - File size
    - `:options` - Import options

  ## Returns

  - `{:ok, import_job}` - Created job
  - `{:error, changeset}` - Validation failed
  """
  def create_import_job(user_id, attrs) do
    %ImportJob{}
    |> ImportJob.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert()
  end

  @doc """
  Gets an import job by ID.
  """
  def get_import_job(id) do
    Repo.get(ImportJob, id)
  end

  @doc """
  Gets an import job by ID, raises if not found.
  """
  def get_import_job!(id) do
    Repo.get!(ImportJob, id)
  end

  @doc """
  Lists import jobs for a user.

  ## Options

  - `:status` - Filter by status
  - `:limit` - Limit results (default: 50)
  """
  def list_import_jobs(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query =
      from j in ImportJob,
        where: j.user_id == ^user_id,
        order_by: [desc: j.inserted_at],
        limit: ^limit

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from j in query, where: j.status == ^status
      end

    Repo.all(query)
  end

  @doc """
  Updates an import job.
  """
  def update_import_job(%ImportJob{} = job, attrs) do
    job
    |> ImportJob.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates import progress.
  """
  def update_import_progress(%ImportJob{} = job, progress) do
    job
    |> ImportJob.progress_changeset(progress)
    |> Repo.update()
  end

  @doc """
  Marks an import job as completed.
  """
  def complete_import_job(%ImportJob{} = job, stats) do
    job
    |> ImportJob.complete_changeset(stats)
    |> Repo.update()
  end

  @doc """
  Marks an import job as failed.
  """
  def fail_import_job(%ImportJob{} = job, errors) do
    job
    |> ImportJob.fail_changeset(errors)
    |> Repo.update()
  end

  # ============================================
  # SOURCE MAPPINGS
  # ============================================

  @doc """
  Creates a mapping between a source item and an Onelist entry.
  """
  def create_mapping(attrs) do
    %SourceEntryMapping{}
    |> SourceEntryMapping.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a mapping by source identifiers.
  """
  def get_mapping(user_id, source_type, source_id) do
    Repo.one(
      from m in SourceEntryMapping,
        where: m.user_id == ^user_id,
        where: m.source_type == ^source_type,
        where: m.source_id == ^source_id
    )
  end

  @doc """
  Gets a mapping by entry ID.
  """
  def get_mapping_by_entry(entry_id) do
    Repo.one(from m in SourceEntryMapping, where: m.entry_id == ^entry_id)
  end

  # ============================================
  # ADAPTERS
  # ============================================

  @doc """
  Returns the adapter module for a source type.
  """
  def get_adapter(source_type) do
    case Map.get(@adapters, source_type) do
      nil -> {:error, :unknown_source_type}
      adapter -> {:ok, adapter}
    end
  end

  @doc """
  Returns list of supported source types.
  """
  def supported_sources do
    Map.keys(@adapters)
  end

  @doc """
  Returns list of source types that support continuous sync.
  """
  def sync_capable_sources do
    @adapters
    |> Enum.filter(fn {_type, adapter} -> adapter.supports_continuous_sync?() end)
    |> Enum.map(fn {type, _} -> type end)
  end

  @doc """
  Returns list of source types that support one-time import.
  """
  def import_capable_sources do
    @adapters
    |> Enum.filter(fn {_type, adapter} -> adapter.supports_one_time_import?() end)
    |> Enum.map(fn {type, _} -> type end)
  end

  # ============================================
  # QUEUE OPERATIONS
  # ============================================

  @doc """
  Enqueues a sync job for an integration.

  ## Options

  - `:priority` - Job priority (default: 0)
  - `:scheduled_at` - Schedule for later execution
  """
  def enqueue_sync(%ExternalIntegration{} = integration, opts \\ []) do
    args = %{type: "sync", integration_id: integration.id}

    args
    |> OrchestratorWorker.new(opts)
    |> Oban.insert()
  end

  @doc """
  Enqueues an import job.

  ## Options

  - `:priority` - Job priority (default: 0)
  """
  def enqueue_import(%ImportJob{} = import_job, opts \\ []) do
    args = %{type: "import", import_job_id: import_job.id}

    args
    |> OrchestratorWorker.new(opts)
    |> Oban.insert()
  end

  @doc """
  Schedules recurring sync for all enabled integrations.
  Called by a scheduled job (e.g., Oban cron).
  """
  def schedule_due_syncs do
    now = DateTime.utc_now()

    query =
      from i in ExternalIntegration,
        where: i.sync_enabled == true,
        where:
          is_nil(i.last_sync_at) or
            fragment(
              "? + (? || ' minutes')::interval < ?",
              i.last_sync_at,
              i.sync_frequency_minutes,
              ^now
            )

    Repo.all(query)
    |> Enum.each(fn integration ->
      enqueue_sync(integration)
    end)
  end
end
