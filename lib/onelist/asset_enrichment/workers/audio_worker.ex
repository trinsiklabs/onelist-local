defmodule Onelist.AssetEnrichment.Workers.AudioWorker do
  @moduledoc """
  Processes audio assets: transcription and action item extraction.

  Stores results as representations on the parent entry:
  - Transcripts stored as type "transcript"
  - Action items stored as linked entries (entry_type "task")
  """

  use Oban.Worker, queue: :enrichment_audio, max_attempts: 3

  alias Onelist.Entries
  alias Onelist.AssetEnrichment
  alias Onelist.AssetEnrichment.Providers.OpenAIWhisper
  alias Onelist.AssetEnrichment.Extractors.ActionItemExtractor
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

  defp process_enrichment(asset, entry_id, "transcript") do
    metadata = %{asset_id: asset.id, entry_id: entry_id}
    
    Telemetry.span(:transcribe, metadata, fn ->
      # Mark as processing
      AssetEnrichment.mark_enrichment_processing(entry_id, "transcript", asset.id)

      # Get audio file path
      case get_asset_path(asset) do
        {:ok, audio_path} ->
          case whisper_provider().transcribe(audio_path, []) do
            {:ok, result} ->
              cost = estimate_whisper_cost(result.duration)
              
              rep_metadata = %{
                "enrichment" => %{
                  "provider" => "openai",
                  "model" => "whisper-1",
                  "tier" => 1,
                  "cost_cents" => cost
                },
                "language" => result.language,
                "duration_seconds" => result.duration,
                "word_count" => word_count(result.text),
                "segments" => result.segments
              }

              AssetEnrichment.create_enrichment_representation(
                entry_id,
                "transcript",
                asset.id,
                result.text,
                rep_metadata
              )

              # Record cost with telemetry
              entry = Entries.get_entry(entry_id)

              if entry do
                Telemetry.record_cost(:transcribe, cost, %{
                  user_id: entry.user_id,
                  provider: "openai",
                  duration_seconds: result.duration
                })
                AssetEnrichment.record_cost(entry.user_id, cost)
              end

              Logger.info("Completed transcription for asset #{asset.id}")
              :ok

            {:error, reason} ->
              AssetEnrichment.mark_enrichment_failed(
                entry_id,
                "transcript",
                asset.id,
                inspect(reason)
              )

              {:error, reason}
          end

        {:error, reason} ->
          AssetEnrichment.mark_enrichment_failed(entry_id, "transcript", asset.id, "File not found")
          {:error, reason}
      end
    end)
  end

  defp process_enrichment(asset, entry_id, "action_items") do
    metadata = %{asset_id: asset.id, entry_id: entry_id}
    
    Telemetry.span(:extract_actions, metadata, fn ->
      # Need transcript first
      case AssetEnrichment.get_transcript(entry_id, asset.id) do
        {:ok, %{text: text, segments: segments}} ->
          # Sanitize transcript before extraction (prompt injection protection)
          case Security.sanitize_transcript(text) do
            {:ok, sanitized_text} ->
              case ActionItemExtractor.extract(sanitized_text, segments) do
                {:ok, items} ->
                  # Validate extracted items before storing
                  {:ok, validated_items} = Security.validate_action_items(
                    Enum.map(items, fn item -> 
                      %{
                        "text" => item.text,
                        "owner" => item[:owner],
                        "deadline" => item[:deadline],
                        "confidence" => confidence_to_string(item[:confidence]),
                        "source_quote" => item[:source_quote]
                      }
                    end)
                  )
                  
                  # Create entries for each validated action item
                  entry = Entries.get_entry(entry_id)

                  if entry do
                    Enum.each(validated_items, fn item ->
                      create_extracted_entry(entry, asset, item, "action_item")
                    end)

                    Logger.info("Extracted #{length(validated_items)} action items from asset #{asset.id}")
                  end

                  :ok

                {:error, reason} ->
                  Logger.error("Action item extraction failed: #{inspect(reason)}")
                  {:error, reason}
              end
              
            {:error, reason} ->
              Logger.error("Transcript sanitization failed: #{inspect(reason)}")
              {:error, {:sanitization_failed, reason}}
          end

        {:pending, _} ->
          # Transcript not ready, snooze and retry
          {:snooze, 30}

        {:error, reason} ->
          Logger.error("Cannot extract action items, transcript error: #{inspect(reason)}")
          {:error, {:missing_transcript, reason}}
      end
    end)
  end

  defp process_enrichment(_asset, _entry_id, type) do
    Logger.warning("Unknown audio enrichment type: #{type}")
    :ok
  end

  defp create_extracted_entry(source_entry, asset, item, item_type) do
    entry_type =
      case item_type do
        "action_item" -> "task"
        "decision" -> "decision"
        _ -> "note"
      end

    attrs = %{
      entry_type: entry_type,
      title: item.text,
      metadata: %{
        "extracted_from" => %{
          "asset_id" => asset.id,
          "entry_id" => source_entry.id,
          "item_type" => item_type,
          "speaker" => item[:speaker],
          "timestamp_start" => item[:start_time],
          "timestamp_end" => item[:end_time],
          "confidence" => item[:confidence],
          "source_quote" => item[:source_quote]
        }
      }
    }

    user = Onelist.Accounts.get_user!(source_entry.user_id)

    case Entries.create_entry(user, attrs) do
      {:ok, new_entry} ->
        # Link back to source
        Entries.create_link(source_entry, new_entry, "has_extracted_item", %{
          "item_type" => item_type
        })

        {:ok, new_entry}

      error ->
        Logger.error("Failed to create extracted entry: #{inspect(error)}")
        error
    end
  end

  defp get_asset_path(asset) do
    # Use the storage_path from the asset
    if asset.storage_path && File.exists?(asset.storage_path) do
      {:ok, asset.storage_path}
    else
      # Try constructing path from uploads directory
      uploads_dir = Application.get_env(:onelist, :uploads_dir, "priv/static/uploads")
      path = Path.join(uploads_dir, Path.basename(asset.storage_path || ""))

      if File.exists?(path) do
        {:ok, path}
      else
        {:error, :file_not_found}
      end
    end
  end

  defp estimate_whisper_cost(duration_seconds) do
    # Whisper costs ~$0.006 per minute
    minutes = (duration_seconds || 0) / 60
    round(minutes * 0.6)
  end

  defp word_count(nil), do: 0
  defp word_count(text), do: text |> String.split() |> length()
  
  defp confidence_to_string(nil), do: "medium"
  defp confidence_to_string(c) when is_float(c) and c >= 0.8, do: "high"
  defp confidence_to_string(c) when is_float(c) and c >= 0.6, do: "medium"
  defp confidence_to_string(c) when is_float(c), do: "low"
  defp confidence_to_string(c) when is_binary(c), do: c
  defp confidence_to_string(_), do: "medium"
  
  defp whisper_provider do
    Application.get_env(:onelist, :whisper_provider, OpenAIWhisper)
  end
end
