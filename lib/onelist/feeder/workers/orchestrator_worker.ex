defmodule Onelist.Feeder.Workers.OrchestratorWorker do
  @moduledoc """
  Coordinates sync and import operations for the Feeder Agent.

  Handles two types of jobs:
  1. **Sync jobs** - Continuous sync for external integrations (RSS, Notion, etc.)
  2. **Import jobs** - One-time import from files (ENEX, export ZIPs, etc.)

  ## Job Arguments

  For sync:
  ```elixir
  %{
    "type" => "sync",
    "integration_id" => "uuid"
  }
  ```

  For import:
  ```elixir
  %{
    "type" => "import",
    "import_job_id" => "uuid"
  }
  ```
  """

  use Oban.Worker, queue: :feeder, max_attempts: 3

  alias Onelist.Feeder
  alias Onelist.Feeder.{ExternalIntegration, ImportJob}
  alias Onelist.Entries

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "sync", "integration_id" => integration_id} = args}) do
    Logger.metadata(integration_id: integration_id)

    with {:ok, integration} <- get_integration(integration_id),
         true <- integration.sync_enabled do
      run_sync(integration, args)
    else
      false ->
        Logger.debug("Sync disabled for integration #{integration_id}")
        :ok

      {:error, :integration_not_found} = error ->
        Logger.warning("Integration #{integration_id} not found")
        error

      {:error, reason} = error ->
        Logger.error("Sync failed: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{args: %{"type" => "import", "import_job_id" => import_job_id} = args}) do
    Logger.metadata(import_job_id: import_job_id)

    with {:ok, import_job} <- get_import_job(import_job_id) do
      run_import(import_job, args)
    else
      {:error, :import_job_not_found} = error ->
        Logger.warning("Import job #{import_job_id} not found")
        error

      {:error, reason} = error ->
        Logger.error("Import failed: #{inspect(reason)}")
        error
    end
  end

  def perform(%Oban.Job{args: args}) do
    Logger.error("Unknown job type: #{inspect(args)}")
    {:error, :unknown_job_type}
  end

  # ============================================
  # SYNC OPERATIONS
  # ============================================

  defp run_sync(integration, _args) do
    Logger.info("Starting sync for integration #{integration.id} (#{integration.source_type})")

    # Mark as syncing
    {:ok, integration} = Feeder.update_sync_state(integration, %{status: :syncing})

    case Feeder.get_adapter(integration.source_type) do
      {:ok, adapter} ->
        perform_sync(adapter, integration)

      {:error, :unknown_source_type} ->
        Logger.error("Unknown source type: #{integration.source_type}")
        Feeder.update_sync_state(integration, %{
          status: :failed,
          error: "Unknown source type: #{integration.source_type}"
        })
        {:error, :unknown_source_type}
    end
  end

  defp perform_sync(adapter, integration) do
    cursor = integration.sync_cursor || %{}
    credentials = integration.credentials
    opts = integration.sync_filter || %{}

    case adapter.fetch_changes(credentials, cursor, opts) do
      {:ok, items, new_cursor} ->
        Logger.info("Fetched #{length(items)} items from #{integration.source_type}")
        result = process_sync_items(adapter, integration, items)

        Feeder.update_sync_state(integration, %{
          status: if(result.failed > 0, do: :partial, else: :success),
          cursor: new_cursor,
          stats: %{
            entries_created: result.created,
            entries_updated: result.updated,
            errors: result.failed
          }
        })

        :ok

      {:error, reason} ->
        Logger.error("Sync fetch failed: #{inspect(reason)}")
        Feeder.update_sync_state(integration, %{
          status: :failed,
          error: inspect(reason)
        })
        {:error, reason}
    end
  end

  defp process_sync_items(adapter, integration, items) do
    Enum.reduce(items, %{created: 0, updated: 0, failed: 0}, fn item, acc ->
      case create_or_update_entry(adapter, integration, item) do
        {:ok, :created} -> %{acc | created: acc.created + 1}
        {:ok, :updated} -> %{acc | updated: acc.updated + 1}
        {:ok, :skipped} -> acc
        {:error, _reason} -> %{acc | failed: acc.failed + 1}
      end
    end)
  end

  defp create_or_update_entry(adapter, integration, item) do
    user_id = integration.user_id
    source_id = item[:guid] || item["guid"] || item[:id] || item["id"]

    # Check if we already have this item
    case Feeder.get_mapping(user_id, integration.source_type, source_id) do
      nil ->
        # Create new entry
        entry_attrs = adapter.to_entry(item, user_id)
        tags = adapter.extract_tags(item)

        content =
          case adapter.convert_content(item) do
            {:ok, md} -> md
            {:error, _} -> entry_attrs[:content] || ""
          end

        case Entries.create_entry(user_id, Map.put(entry_attrs, :content, content)) do
          {:ok, entry} ->
            # Create mapping
            Feeder.create_mapping(%{
              user_id: user_id,
              integration_id: integration.id,
              entry_id: entry.id,
              source_type: integration.source_type,
              source_id: source_id,
              source_updated_at: item[:updated_at] || item[:published_at]
            })

            # Apply tags
            Enum.each(tags, fn tag ->
              Onelist.Tags.add_tag_to_entry(entry.id, tag, user_id)
            end)

            # Schedule asset downloads
            schedule_asset_downloads(adapter, entry, item)

            {:ok, :created}

          {:error, reason} ->
            Logger.warning("Failed to create entry: #{inspect(reason)}")
            {:error, reason}
        end

      _existing_mapping ->
        # TODO: Implement update logic for changed items
        {:ok, :skipped}
    end
  end

  defp schedule_asset_downloads(adapter, entry, item) do
    assets = adapter.extract_assets(item)

    Enum.each(assets, fn asset ->
      # Queue asset download (would use a separate worker in production)
      Logger.debug("Would download asset: #{asset[:url]} for entry #{entry.id}")
    end)
  end

  # ============================================
  # IMPORT OPERATIONS
  # ============================================

  defp run_import(import_job, _args) do
    Logger.info("Starting import job #{import_job.id} (#{import_job.source_type})")

    # Mark as processing
    {:ok, import_job} = Feeder.update_import_job(import_job, %{
      status: "processing",
      started_at: DateTime.utc_now()
    })

    case Feeder.get_adapter(import_job.source_type) do
      {:ok, adapter} ->
        if adapter.supports_one_time_import?() do
          perform_import(adapter, import_job)
        else
          Logger.error("Adapter #{import_job.source_type} doesn't support import")
          Feeder.fail_import_job(import_job, [%{error: "Adapter doesn't support import"}])
          {:error, :import_not_supported}
        end

      {:error, :unknown_source_type} ->
        Logger.error("Unknown source type: #{import_job.source_type}")
        Feeder.fail_import_job(import_job, [%{error: "Unknown source type"}])
        {:error, :unknown_source_type}
    end
  end

  defp perform_import(adapter, import_job) do
    opts = import_job.options || %{}

    case adapter.parse_export(import_job.file_path, opts) do
      {:ok, stream} ->
        result = process_import_stream(adapter, import_job, stream)

        if result.failed > 0 do
          Feeder.fail_import_job(import_job, result.errors)
        else
          Feeder.complete_import_job(import_job, %{
            entries_created: result.created,
            assets_uploaded: result.assets,
            tags_created: result.tags
          })
        end

        :ok

      {:error, reason} ->
        Logger.error("Import parse failed: #{inspect(reason)}")
        Feeder.fail_import_job(import_job, [%{error: inspect(reason)}])
        {:error, reason}
    end
  end

  defp process_import_stream(adapter, import_job, stream) do
    user_id = import_job.user_id

    stream
    |> Stream.with_index()
    |> Enum.reduce(%{created: 0, failed: 0, assets: 0, tags: 0, errors: []}, fn {item, index}, acc ->
      # Update progress every 10 items
      if rem(index, 10) == 0 do
        Feeder.update_import_progress(import_job, %{
          processed: index,
          succeeded: acc.created,
          failed: acc.failed
        })
      end

      case import_single_item(adapter, user_id, item) do
        {:ok, stats} ->
          %{acc |
            created: acc.created + 1,
            assets: acc.assets + (stats[:assets] || 0),
            tags: acc.tags + (stats[:tags] || 0)
          }

        {:error, reason} ->
          %{acc |
            failed: acc.failed + 1,
            errors: [%{item: index, error: inspect(reason)} | acc.errors]
          }
      end
    end)
  end

  defp import_single_item(adapter, user_id, item) do
    entry_attrs = adapter.to_entry(item, user_id)
    tags = adapter.extract_tags(item)

    content =
      case adapter.convert_content(item) do
        {:ok, md} -> md
        {:error, _} -> entry_attrs[:content] || ""
      end

    case Entries.create_entry(user_id, Map.put(entry_attrs, :content, content)) do
      {:ok, entry} ->
        # Apply tags
        Enum.each(tags, fn tag ->
          Onelist.Tags.add_tag_to_entry(entry.id, tag, user_id)
        end)

        {:ok, %{assets: 0, tags: length(tags)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  defp get_integration(id) do
    case Feeder.get_integration(id) do
      nil -> {:error, :integration_not_found}
      integration -> {:ok, integration}
    end
  end

  defp get_import_job(id) do
    case Feeder.get_import_job(id) do
      nil -> {:error, :import_job_not_found}
      job -> {:ok, job}
    end
  end
end
