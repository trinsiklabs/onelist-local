defmodule Onelist.AssetEnrichment.Workers.ImageWorker do
  @moduledoc """
  Processes image assets: description generation and OCR.

  Stores results as representations on the parent entry:
  - Descriptions stored as type "description"
  - OCR text stored as type "ocr"
  """

  use Oban.Worker, queue: :enrichment_image, max_attempts: 3

  alias Onelist.Entries
  alias Onelist.AssetEnrichment
  alias Onelist.AssetEnrichment.Providers.OpenAIVision
  alias Onelist.AssetEnrichment.Telemetry
  alias Onelist.AssetEnrichment.Security

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"asset_id" => asset_id, "entry_id" => entry_id, "enrichment_type" => type},
        inserted_at: inserted_at
      } = _job) do
    # Record queue latency
    Telemetry.record_queue_latency(
      String.to_atom(type),
      inserted_at,
      %{asset_id: asset_id, entry_id: entry_id}
    )
    
    with {:ok, asset} <- get_asset(asset_id) do
      process_enrichment(asset, entry_id, type)
    end
  end

  defp get_asset(asset_id) do
    case Entries.get_asset(asset_id) do
      nil -> {:error, :asset_not_found}
      asset -> {:ok, asset}
    end
  end

  defp process_enrichment(asset, entry_id, "description") do
    metadata = %{asset_id: asset.id, entry_id: entry_id}
    
    Telemetry.span(:describe, metadata, fn ->
      AssetEnrichment.mark_enrichment_processing(entry_id, "description", asset.id)

      case get_asset_path(asset) do
        {:ok, image_path} ->
          case vision_provider().describe(image_path, []) do
            {:ok, result} ->
              # Validate and sanitize the description output
              {:ok, validated_description} = Security.validate_description(result.description)
              
              rep_metadata = %{
                "enrichment" => %{
                  "provider" => "openai",
                  "model" => result.model,
                  "tier" => 2,
                  "cost_cents" => result.cost_cents,
                  "input_tokens" => result.input_tokens,
                  "output_tokens" => result.output_tokens
                }
              }

              AssetEnrichment.create_enrichment_representation(
                entry_id,
                "description",
                asset.id,
                validated_description,
                rep_metadata
              )

              # Record cost with telemetry
              entry = Entries.get_entry(entry_id)
              if entry do
                Telemetry.record_cost(:describe, result.cost_cents, %{
                  user_id: entry.user_id,
                  provider: "openai"
                })
                Telemetry.record_token_usage("openai", result.input_tokens, result.output_tokens, %{
                  operation: :describe,
                  asset_id: asset.id
                })
                AssetEnrichment.record_cost(entry.user_id, result.cost_cents)
              end

              Logger.info("Completed description for asset #{asset.id}")
              :ok

            {:error, reason} ->
              AssetEnrichment.mark_enrichment_failed(
                entry_id,
                "description",
                asset.id,
                inspect(reason)
              )

              {:error, reason}
          end

        {:error, reason} ->
          AssetEnrichment.mark_enrichment_failed(
            entry_id,
            "description",
            asset.id,
            "File not found"
          )

          {:error, reason}
      end
    end)
  end

  defp process_enrichment(asset, entry_id, "ocr") do
    metadata = %{asset_id: asset.id, entry_id: entry_id}
    
    Telemetry.span(:ocr, metadata, fn ->
      AssetEnrichment.mark_enrichment_processing(entry_id, "ocr", asset.id)

      case get_asset_path(asset) do
        {:ok, image_path} ->
          case vision_provider().extract_text(image_path, []) do
            {:ok, result} ->
              # Validate and sanitize the OCR output
              {:ok, validated_text} = Security.validate_ocr_text(result.text)
              
              rep_metadata = %{
                "enrichment" => %{
                  "provider" => "openai",
                  "model" => result.model,
                  "tier" => 1,
                  "cost_cents" => result.cost_cents,
                  "input_tokens" => result.input_tokens,
                  "output_tokens" => result.output_tokens
                },
                "has_text" => String.length(validated_text || "") > 0
              }

              AssetEnrichment.create_enrichment_representation(
                entry_id,
                "ocr",
                asset.id,
                validated_text,
                rep_metadata
              )

              # Record cost with telemetry
              entry = Entries.get_entry(entry_id)
              if entry do
                Telemetry.record_cost(:ocr, result.cost_cents, %{
                  user_id: entry.user_id,
                  provider: "openai"
                })
                Telemetry.record_token_usage("openai", result.input_tokens, result.output_tokens, %{
                  operation: :ocr,
                  asset_id: asset.id
                })
                AssetEnrichment.record_cost(entry.user_id, result.cost_cents)
              end

              Logger.info("Completed OCR for asset #{asset.id}")
              :ok

            {:error, reason} ->
              AssetEnrichment.mark_enrichment_failed(entry_id, "ocr", asset.id, inspect(reason))
              {:error, reason}
          end

        {:error, reason} ->
          AssetEnrichment.mark_enrichment_failed(entry_id, "ocr", asset.id, "File not found")
          {:error, reason}
      end
    end)
  end

  defp process_enrichment(_asset, _entry_id, type) do
    Logger.warning("Unknown image enrichment type: #{type}")
    :ok
  end

  defp get_asset_path(asset) do
    if asset.storage_path && File.exists?(asset.storage_path) do
      {:ok, asset.storage_path}
    else
      uploads_dir = Application.get_env(:onelist, :uploads_dir, "priv/static/uploads")
      path = Path.join(uploads_dir, Path.basename(asset.storage_path || ""))

      if File.exists?(path) do
        {:ok, path}
      else
        {:error, :file_not_found}
      end
    end
  end
  
  defp vision_provider do
    Application.get_env(:onelist, :vision_provider, OpenAIVision)
  end
end
