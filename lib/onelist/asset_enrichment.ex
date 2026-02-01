defmodule Onelist.AssetEnrichment do
  @moduledoc """
  Asset Enrichment Agent - transforms raw assets into searchable knowledge.

  Uses existing schemas:
  - Representations for enrichment results (transcripts, descriptions, OCR)
  - Entries for extracted items (action items, decisions)
  - Entry links to connect extracted items to sources
  - Search configs for user preferences

  ## Zero New Tables

  This module reuses existing database tables:
  - `representations` with new types: transcript, description, ocr, summary, tags
  - `entries` with types: task, decision
  - `entry_links` with link_type: has_extracted_item
  - `search_configs` extended with enrichment settings
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Entries.{Entry, Representation}
  alias Onelist.Searcher
  alias Onelist.Searcher.SearchConfig
  alias Onelist.AssetEnrichment.Workers.OrchestratorWorker

  @enrichment_types ~w(transcript description ocr summary tags)

  # ============================================
  # ENRICHMENT OPERATIONS
  # ============================================

  @doc """
  Enqueue asset for enrichment processing.

  ## Options
    * `:max_tier` - Maximum enrichment tier to run (0-4)
    * `:priority` - Job priority (default: 0)

  ## Examples

      iex> enqueue_enrichment(asset_id)
      {:ok, %Oban.Job{}}

      iex> enqueue_enrichment(asset_id, max_tier: 3, priority: 1)
      {:ok, %Oban.Job{}}
  """
  def enqueue_enrichment(asset_id, opts \\ []) do
    %{asset_id: asset_id, max_tier: Keyword.get(opts, :max_tier)}
    |> OrchestratorWorker.new(priority: Keyword.get(opts, :priority, 0))
    |> Oban.insert()
  end

  @doc """
  Get enrichment result for an asset.
  Returns the representation with enrichment metadata.
  """
  def get_enrichment(entry_id, enrichment_type, asset_id) do
    Repo.one(
      from r in Representation,
        where: r.entry_id == ^entry_id,
        where: r.type == ^enrichment_type,
        where: fragment("?->>'asset_id' = ?", r.metadata, ^asset_id)
    )
  end

  @doc """
  Get all enrichments for an asset.
  """
  def get_enrichments(entry_id, asset_id) do
    Repo.all(
      from r in Representation,
        where: r.entry_id == ^entry_id,
        where: r.type in ^@enrichment_types,
        where: fragment("?->>'asset_id' = ?", r.metadata, ^asset_id),
        order_by: r.type
    )
  end

  @doc """
  Get enrichment status for an asset.
  Returns a list of enrichment statuses.
  """
  def get_enrichment_status(entry_id, asset_id) do
    enrichments = get_enrichments(entry_id, asset_id)

    Enum.map(enrichments, fn rep ->
      enrichment_meta = get_in(rep.metadata, ["enrichment"]) || %{}

      %{
        type: rep.type,
        status: enrichment_meta["status"] || "unknown",
        completed_at: enrichment_meta["completed_at"],
        error: enrichment_meta["error"]
      }
    end)
  end

  @doc """
  Check if transcription exists and is completed.
  """
  def transcription_ready?(entry_id, asset_id) do
    case get_enrichment(entry_id, "transcript", asset_id) do
      %{metadata: %{"enrichment" => %{"status" => "completed"}}} -> true
      _ -> false
    end
  end

  @doc """
  Get transcript for an asset.

  ## Returns
    * `{:ok, transcript_data}` - Transcript with text, language, segments, duration
    * `{:pending, :processing}` - Transcript is being generated
    * `{:error, reason}` - Error getting transcript
  """
  def get_transcript(entry_id, asset_id) do
    case get_enrichment(entry_id, "transcript", asset_id) do
      %{content: content, metadata: meta} when not is_nil(content) ->
        {:ok,
         %{
           text: content,
           language: meta["language"],
           segments: meta["segments"] || [],
           duration: meta["duration_seconds"]
         }}

      %{metadata: %{"enrichment" => %{"status" => "processing"}}} ->
        {:pending, :processing}

      %{metadata: %{"enrichment" => %{"status" => "failed", "error" => error}}} ->
        {:error, error}

      nil ->
        {:error, :not_found}
    end
  end

  # ============================================
  # EXTRACTED ITEMS
  # ============================================

  @doc """
  Get extracted items for an entry (action items, decisions, etc.)
  These are entries linked via entry_links with link_type "has_extracted_item".

  ## Options
    * `:item_type` - Filter by item type (e.g., "action_item", "decision")
  """
  def get_extracted_items(entry_id, opts \\ []) do
    item_type = Keyword.get(opts, :item_type)

    query =
      from e in Entry,
        join: link in assoc(e, :incoming_links),
        where: link.source_entry_id == ^entry_id,
        where: link.link_type == "has_extracted_item",
        order_by: [asc: e.inserted_at]

    query =
      if item_type do
        from e in query,
          where: fragment("?->'extracted_from'->>'item_type' = ?", e.metadata, ^item_type)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get action items extracted from an entry.
  """
  def get_action_items(entry_id) do
    get_extracted_items(entry_id, item_type: "action_item")
  end

  @doc """
  Get decisions extracted from an entry.
  """
  def get_decisions(entry_id) do
    get_extracted_items(entry_id, item_type: "decision")
  end

  # ============================================
  # INTERNAL: CREATE ENRICHMENT RESULT
  # ============================================

  @doc false
  def create_enrichment_representation(entry_id, type, asset_id, content, metadata) do
    enrichment_meta = %{
      "status" => "completed",
      "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    full_metadata =
      Map.merge(metadata, %{
        "asset_id" => asset_id,
        "enrichment" => Map.merge(metadata["enrichment"] || %{}, enrichment_meta)
      })

    # Check if representation already exists
    case get_enrichment(entry_id, type, asset_id) do
      nil ->
        # Create new representation
        %Representation{entry_id: entry_id}
        |> Representation.changeset(%{
          type: type,
          content: content,
          metadata: full_metadata,
          encrypted: false
        })
        |> Repo.insert()

      existing ->
        # Update existing representation
        existing
        |> Representation.update_changeset(%{
          content: content,
          metadata: full_metadata
        })
        |> Repo.update()
    end
  end

  @doc false
  def mark_enrichment_processing(entry_id, type, asset_id) do
    metadata = %{
      "asset_id" => asset_id,
      "enrichment" => %{
        "status" => "processing",
        "started_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }
    }

    case get_enrichment(entry_id, type, asset_id) do
      nil ->
        %Representation{entry_id: entry_id}
        |> Representation.changeset(%{
          type: type,
          content: nil,
          metadata: metadata,
          encrypted: false
        })
        |> Repo.insert()

      existing ->
        updated_meta =
          Map.merge(existing.metadata || %{}, metadata)

        existing
        |> Representation.update_changeset(%{metadata: updated_meta})
        |> Repo.update()
    end
  end

  @doc false
  def mark_enrichment_failed(entry_id, type, asset_id, error) do
    case get_enrichment(entry_id, type, asset_id) do
      %Representation{} = rep ->
        current_meta = rep.metadata || %{}
        current_enrichment = current_meta["enrichment"] || %{}

        updated_enrichment =
          Map.merge(current_enrichment, %{
            "status" => "failed",
            "error" => error,
            "completed_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

        updated_meta = Map.put(current_meta, "enrichment", updated_enrichment)

        rep
        |> Representation.update_changeset(%{metadata: updated_meta})
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  # ============================================
  # CONFIGURATION
  # ============================================

  @doc """
  Check if auto-enrichment is enabled for user.
  """
  def auto_enrich_enabled?(user_id) do
    config = Searcher.get_search_config!(user_id)
    Map.get(config, :auto_enrich_enabled, true)
  end

  @doc """
  Get max enrichment tier for user.
  """
  def max_tier(user_id) do
    config = Searcher.get_search_config!(user_id)
    Map.get(config, :max_enrichment_tier, 2)
  end

  @doc """
  Get enrichment settings for a specific asset type.
  """
  def get_settings(user_id, asset_type) when asset_type in ~w(image audio video document) do
    config = Searcher.get_search_config!(user_id)
    SearchConfig.get_enrichment_settings(config, asset_type)
  end

  def get_settings(_user_id, _asset_type), do: %{"enabled" => false}

  @doc """
  Check if user can afford an enrichment operation based on budget.
  """
  def can_afford?(user_id, estimated_cost_cents) do
    config = Searcher.get_search_config!(user_id)

    cond do
      is_nil(config.daily_enrichment_budget_cents) ->
        true

      (config.spent_enrichment_today_cents || 0) + estimated_cost_cents <=
          config.daily_enrichment_budget_cents ->
        true

      true ->
        false
    end
  end

  @doc """
  Record cost spent on enrichment.
  """
  def record_cost(user_id, cost_cents) do
    config = Searcher.get_search_config!(user_id)

    Searcher.update_search_config(user_id, %{
      spent_enrichment_today_cents: (config.spent_enrichment_today_cents || 0) + cost_cents
    })
  end

  # ============================================
  # HELPERS
  # ============================================

  @doc """
  Returns the list of valid enrichment types.
  """
  def enrichment_types, do: @enrichment_types

  @doc """
  Determines the asset category based on MIME type.
  """
  def get_asset_category(mime_type) do
    cond do
      String.starts_with?(mime_type || "", "image/") -> :image
      String.starts_with?(mime_type || "", "audio/") -> :audio
      String.starts_with?(mime_type || "", "video/") -> :video
      mime_type in ~w(application/pdf text/plain text/markdown) -> :document
      true -> :unknown
    end
  end
end
