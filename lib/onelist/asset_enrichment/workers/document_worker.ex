defmodule Onelist.AssetEnrichment.Workers.DocumentWorker do
  @moduledoc """
  Processes document assets: text extraction and OCR for PDFs.

  Stores results as representations on the parent entry:
  - Extracted text stored as type "ocr"
  """

  use Oban.Worker, queue: :enrichment_document, max_attempts: 3

  alias Onelist.Entries
  alias Onelist.AssetEnrichment

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"asset_id" => asset_id, "entry_id" => entry_id, "enrichment_type" => type}
      }) do
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

  defp process_enrichment(asset, entry_id, "ocr") do
    AssetEnrichment.mark_enrichment_processing(entry_id, "ocr", asset.id)

    case get_asset_path(asset) do
      {:ok, doc_path} ->
        case extract_text(doc_path, asset.mime_type) do
          {:ok, text} ->
            metadata = %{
              "enrichment" => %{
                "provider" => "local",
                "model" => "text_extraction",
                "tier" => 1,
                "cost_cents" => 0
              },
              "char_count" => String.length(text),
              "word_count" => word_count(text)
            }

            AssetEnrichment.create_enrichment_representation(
              entry_id,
              "ocr",
              asset.id,
              text,
              metadata
            )

            Logger.info("Completed document text extraction for asset #{asset.id}")
            :ok

          {:error, reason} ->
            AssetEnrichment.mark_enrichment_failed(entry_id, "ocr", asset.id, inspect(reason))
            {:error, reason}
        end

      {:error, reason} ->
        AssetEnrichment.mark_enrichment_failed(entry_id, "ocr", asset.id, "File not found")
        {:error, reason}
    end
  end

  defp process_enrichment(_asset, _entry_id, type) do
    Logger.warning("Unknown document enrichment type: #{type}")
    :ok
  end

  defp extract_text(path, "text/plain") do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:read_error, reason}}
    end
  end

  defp extract_text(path, "text/markdown") do
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, {:read_error, reason}}
    end
  end

  defp extract_text(_path, "application/pdf") do
    # PDF extraction would require a library like pdf_text or calling pdftotext
    # For MVP, return a placeholder
    {:error, :pdf_extraction_not_implemented}
  end

  defp extract_text(_path, mime_type) do
    {:error, {:unsupported_type, mime_type}}
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

  defp word_count(nil), do: 0
  defp word_count(text), do: text |> String.split() |> length()
end
