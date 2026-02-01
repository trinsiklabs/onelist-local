defmodule Onelist.AssetEnrichment.Workers.OrchestratorWorker do
  @moduledoc """
  Coordinates enrichment processing for an asset.
  Determines which enrichments to run based on asset type and user config.
  """

  use Oban.Worker, queue: :enrichment, max_attempts: 3

  alias Onelist.Entries
  alias Onelist.AssetEnrichment
  alias Onelist.AssetEnrichment.Workers.{ImageWorker, AudioWorker, DocumentWorker}
  alias Onelist.AssetEnrichment.Telemetry

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"asset_id" => asset_id} = args, inserted_at: inserted_at}) do
    max_tier = args["max_tier"]
    
    # Record queue latency
    Telemetry.record_queue_latency(:orchestrate, inserted_at, %{asset_id: asset_id})
    
    metadata = %{asset_id: asset_id, max_tier: max_tier}
    
    Telemetry.span(:orchestrate, metadata, fn ->
      with {:ok, asset} <- get_asset(asset_id),
           {:ok, entry} <- get_entry(asset.entry_id),
           true <- AssetEnrichment.auto_enrich_enabled?(entry.user_id),
           {:ok, jobs} <- schedule_enrichments(asset, entry, max_tier) do
        Logger.info("Scheduled #{length(jobs)} enrichment jobs for asset #{asset_id}")
        :ok
      else
        false ->
          Logger.debug("Auto-enrichment disabled for asset #{asset_id}")
          :ok

        {:error, :asset_not_found} ->
          Logger.warning("Asset #{asset_id} not found, skipping enrichment")
          :ok

        {:error, :entry_not_found} ->
          Logger.warning("Entry not found for asset #{asset_id}, skipping enrichment")
          :ok

        {:error, reason} ->
          Logger.error("Orchestrator failed for asset #{asset_id}: #{inspect(reason)}")
          {:error, reason}
      end
    end)
  end

  defp get_asset(asset_id) do
    case Entries.get_asset(asset_id) do
      nil -> {:error, :asset_not_found}
      asset -> {:ok, asset}
    end
  end

  defp get_entry(entry_id) do
    case Entries.get_entry(entry_id) do
      nil -> {:error, :entry_not_found}
      entry -> {:ok, entry}
    end
  end

  defp schedule_enrichments(asset, entry, max_tier) do
    max_tier = max_tier || AssetEnrichment.max_tier(entry.user_id)
    category = AssetEnrichment.get_asset_category(asset.mime_type)
    settings = AssetEnrichment.get_settings(entry.user_id, to_string(category))

    if settings["enabled"] do
      jobs = schedule_for_category(category, asset, entry, max_tier, settings)
      {:ok, jobs}
    else
      {:ok, []}
    end
  end

  defp schedule_for_category(:image, asset, entry, _max_tier, settings) do
    jobs = []

    jobs =
      if settings["description"] do
        job =
          ImageWorker.new(%{
            asset_id: asset.id,
            entry_id: entry.id,
            enrichment_type: "description"
          })

        [Oban.insert!(job) | jobs]
      else
        jobs
      end

    jobs =
      if settings["ocr"] do
        job =
          ImageWorker.new(%{
            asset_id: asset.id,
            entry_id: entry.id,
            enrichment_type: "ocr"
          })

        [Oban.insert!(job) | jobs]
      else
        jobs
      end

    jobs
  end

  defp schedule_for_category(:audio, asset, entry, max_tier, settings) do
    jobs = []

    jobs =
      if settings["transcribe"] do
        job =
          AudioWorker.new(%{
            asset_id: asset.id,
            entry_id: entry.id,
            enrichment_type: "transcript"
          })

        [Oban.insert!(job) | jobs]
      else
        jobs
      end

    # Action extraction is tier 3, only schedule if max_tier >= 3
    jobs =
      if settings["extract_actions"] && max_tier >= 3 do
        job =
          AudioWorker.new(%{
            asset_id: asset.id,
            entry_id: entry.id,
            enrichment_type: "action_items"
          })

        [Oban.insert!(job) | jobs]
      else
        jobs
      end

    jobs
  end

  defp schedule_for_category(:document, asset, entry, _max_tier, settings) do
    if settings["ocr"] do
      job =
        DocumentWorker.new(%{
          asset_id: asset.id,
          entry_id: entry.id,
          enrichment_type: "ocr"
        })

      [Oban.insert!(job)]
    else
      []
    end
  end

  defp schedule_for_category(:video, _asset, _entry, _max_tier, _settings) do
    # Video processing not in MVP
    []
  end

  defp schedule_for_category(_, _, _, _, _), do: []
end
