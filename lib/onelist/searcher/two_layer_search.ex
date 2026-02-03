defmodule Onelist.Searcher.TwoLayerSearch do
  @moduledoc """
  Two-layer search for atomic memory retrieval.

  This module implements the "atomic memory" retrieval strategy:
  - Layer 1: Search atomic memories (high precision, fine-grained facts)
  - Layer 2: Inject source context from original entries/representations

  ## Search Modes

  - `:atomic` - Search memories table only (high precision)
  - `:chunk` - Search embeddings table only (legacy, chunk-based)
  - `:hybrid` - Combine memory and chunk search with configurable weights

  ## Why Two Layers?

  Atomic memories are extracted facts/preferences/events that are very precise,
  but they lose context in isolation. By injecting source chunks back into results,
  we get the best of both worlds: precision of atomic search + context of chunks.

  ## Example

      TwoLayerSearch.search(user_id, "coffee preferences", [
        search_mode: :atomic,
        include_source_chunks: true,
        current_only: true,
        limit: 10
      ])
  """

  import Ecto.Query, warn: false
  alias Onelist.Repo
  alias Onelist.Reader.Memory
  alias Onelist.Entries.{Entry, Representation}
  alias Onelist.Searcher.Search
  alias Onelist.Searcher.Providers.OpenAI

  require Logger

  @default_limit 20
  @default_memory_weight 0.6
  @default_chunk_weight 0.4

  # ============================================
  # MAIN SEARCH INTERFACE
  # ============================================

  @doc """
  Perform two-layer search with configurable modes.

  ## Options

    * `:search_mode` - `:atomic`, `:chunk`, or `:hybrid` (default: `:atomic`)
    * `:include_source_chunks` - Inject original context (default: `true`)
    * `:current_only` - Only non-superseded memories (default: `true`)
    * `:limit` - Max results (default: 20)
    * `:offset` - Pagination offset (default: 0)
    * `:filters` - Map of filters (entry_types, tags, date_range, memory_types)
    * `:memory_weight` - Weight for memory results in hybrid mode (default: 0.6)
    * `:chunk_weight` - Weight for chunk results in hybrid mode (default: 0.4)
    * `:min_confidence` - Minimum memory confidence (default: nil, no filter)

  ## Returns

      {:ok, %{
        results: [...],
        total: integer,
        query: string,
        search_mode: atom,
        duration_ms: integer
      }}
  """
  def search(user_id, query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    search_mode = Keyword.get(opts, :search_mode, :atomic)

    result =
      case search_mode do
        :atomic -> atomic_search(user_id, query, opts)
        :chunk -> chunk_search(user_id, query, opts)
        :hybrid -> hybrid_memory_chunk_search(user_id, query, opts)
      end

    case result do
      {:ok, results} ->
        duration_ms = System.monotonic_time(:millisecond) - start_time

        {:ok,
         %{
           results: results,
           total: length(results),
           query: query,
           search_mode: search_mode,
           duration_ms: duration_ms
         }}

      error ->
        error
    end
  end

  @doc """
  Search memories (atomic facts) with vector similarity.

  This is Layer 1 - high precision search against extracted memories.
  """
  def atomic_search(user_id, query, opts \\ []) do
    include_source = Keyword.get(opts, :include_source_chunks, true)
    current_only = Keyword.get(opts, :current_only, true)
    limit = Keyword.get(opts, :limit, @default_limit)
    filters = Keyword.get(opts, :filters, %{})

    with {:ok, query_vector} <- embed_query(query) do
      memories = search_memories(user_id, query_vector, current_only, limit, filters)

      results =
        if include_source do
          inject_source_context(memories)
        else
          memories
        end

      {:ok, results}
    end
  end

  @doc """
  Search chunk embeddings (legacy entry-based search).

  Falls back to the original chunk-based search approach.
  """
  def chunk_search(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.get(opts, :filters, %{})

    with {:ok, query_vector} <- embed_query(query) do
      results = Search.do_semantic_search(user_id, query_vector, filters, limit, offset)

      # Enrich with full entry data
      enriched =
        Enum.map(results, fn result ->
          Map.merge(result, %{
            search_layer: :chunk,
            source_type: :embedding
          })
        end)

      {:ok, enriched}
    end
  end

  @doc """
  Hybrid search combining memory and chunk approaches.

  Merges results from both layers with configurable weights.
  """
  def hybrid_memory_chunk_search(user_id, query, opts \\ []) do
    memory_weight = Keyword.get(opts, :memory_weight, @default_memory_weight)
    chunk_weight = Keyword.get(opts, :chunk_weight, @default_chunk_weight)
    limit = Keyword.get(opts, :limit, @default_limit)
    dedupe = Keyword.get(opts, :deduplicate, true)

    # Fetch more results than needed for merging
    fetch_limit = limit * 2

    memory_opts = Keyword.put(opts, :limit, fetch_limit)
    chunk_opts = Keyword.put(opts, :limit, fetch_limit)

    with {:ok, memory_results} <- atomic_search(user_id, query, memory_opts),
         {:ok, chunk_results} <- chunk_search(user_id, query, chunk_opts) do
      # Normalize and combine
      combined =
        combine_memory_chunk_results(
          memory_results,
          chunk_results,
          memory_weight,
          chunk_weight
        )

      # Deduplicate by entry if requested
      final =
        if dedupe do
          deduplicate_by_entry(combined)
        else
          combined
        end

      {:ok, Enum.take(final, limit)}
    end
  end

  # ============================================
  # MEMORY SEARCH (LAYER 1)
  # ============================================

  @doc """
  Query memories table with vector similarity.

  ## Parameters

    * `user_id` - Owner of the memories
    * `query_vector` - Embedding vector for the query
    * `current_only` - Filter to non-superseded memories
    * `limit` - Max results
    * `filters` - Additional filters (memory_types, min_confidence, etc.)
  """
  def search_memories(user_id, query_vector, current_only, limit, filters \\ %{}) do
    base_query =
      from m in Memory,
        where: m.user_id == ^user_id,
        where: not is_nil(m.embedding),
        select: %{
          memory_id: m.id,
          entry_id: m.entry_id,
          content: m.content,
          memory_type: m.memory_type,
          confidence: m.confidence,
          source_text: m.source_text,
          chunk_index: m.chunk_index,
          valid_from: m.valid_from,
          valid_until: m.valid_until,
          entities: m.entities,
          metadata: m.metadata,
          score:
            fragment(
              "1 - (? <=> ?)",
              m.embedding,
              ^Pgvector.new(query_vector)
            )
        },
        order_by: [asc: fragment("? <=> ?", m.embedding, ^Pgvector.new(query_vector))],
        limit: ^limit

    query =
      base_query
      |> maybe_filter_current_only(current_only)
      |> apply_memory_filters(filters)

    results = Repo.all(query)

    # Add search layer info
    Enum.map(results, fn result ->
      Map.merge(result, %{
        search_layer: :memory,
        source_type: :atomic_memory
      })
    end)
  end

  defp maybe_filter_current_only(query, true) do
    where(query, [m], is_nil(m.valid_until))
  end

  defp maybe_filter_current_only(query, false), do: query

  defp apply_memory_filters(query, filters) do
    query
    |> maybe_filter_memory_types(filters["memory_types"] || filters[:memory_types])
    |> maybe_filter_min_confidence(filters["min_confidence"] || filters[:min_confidence])
    |> maybe_filter_entry_ids(filters["entry_ids"] || filters[:entry_ids])
  end

  defp maybe_filter_memory_types(query, nil), do: query
  defp maybe_filter_memory_types(query, []), do: query

  defp maybe_filter_memory_types(query, types) when is_list(types) do
    where(query, [m], m.memory_type in ^types)
  end

  defp maybe_filter_min_confidence(query, nil), do: query

  defp maybe_filter_min_confidence(query, min) do
    where(query, [m], m.confidence >= ^Decimal.new(to_string(min)))
  end

  defp maybe_filter_entry_ids(query, nil), do: query
  defp maybe_filter_entry_ids(query, []), do: query

  defp maybe_filter_entry_ids(query, entry_ids) when is_list(entry_ids) do
    where(query, [m], m.entry_id in ^entry_ids)
  end

  # ============================================
  # SOURCE CONTEXT INJECTION (LAYER 2)
  # ============================================

  @doc """
  Inject source context from original entry/representation into memory results.

  Adds `source_chunk` and `source_entry` fields to each result, preserving
  the original context that the atomic memory was extracted from.
  """
  def inject_source_context(memory_results) when is_list(memory_results) do
    # Collect unique entry IDs
    entry_ids =
      memory_results
      |> Enum.map(& &1.entry_id)
      |> Enum.uniq()

    # Batch load entries with their representations
    entries_with_context = load_entries_with_context(entry_ids)

    # Inject context into each result
    Enum.map(memory_results, fn result ->
      entry_context = Map.get(entries_with_context, result.entry_id, %{})

      Map.merge(result, %{
        source_entry: entry_context[:entry],
        source_representation: entry_context[:primary_representation],
        source_chunk: build_source_chunk(result, entry_context)
      })
    end)
  end

  defp load_entries_with_context(entry_ids) when entry_ids == [], do: %{}

  defp load_entries_with_context(entry_ids) do
    # Load entries
    entries =
      from(e in Entry, where: e.id in ^entry_ids)
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    # Load primary representations (markdown or plaintext preferred)
    representations =
      from(r in Representation,
        where: r.entry_id in ^entry_ids,
        where: r.type in ["markdown", "plaintext", "html"],
        order_by: [
          asc: fragment("CASE type WHEN 'markdown' THEN 1 WHEN 'plaintext' THEN 2 ELSE 3 END")
        ],
        distinct: r.entry_id
      )
      |> Repo.all()
      |> Map.new(&{&1.entry_id, &1})

    # Combine into context map
    Map.new(entry_ids, fn entry_id ->
      {entry_id,
       %{
         entry: Map.get(entries, entry_id),
         primary_representation: Map.get(representations, entry_id)
       }}
    end)
  end

  defp build_source_chunk(result, entry_context) do
    # Use source_text from memory if available
    if result.source_text && result.source_text != "" do
      %{
        text: result.source_text,
        chunk_index: result.chunk_index,
        from_memory: true
      }
    else
      # Fall back to representation content
      case entry_context[:primary_representation] do
        nil ->
          nil

        rep ->
          %{
            text: rep.content,
            type: rep.type,
            from_memory: false
          }
      end
    end
  end

  # ============================================
  # RESULT COMBINATION AND DEDUPLICATION
  # ============================================

  @doc """
  Deduplicate results by entry, keeping highest-scoring result per entry.

  This prevents showing multiple memories from the same entry, which can
  be redundant. Groups by entry_id and keeps the best score.
  """
  def deduplicate_by_entry(results) when is_list(results) do
    results
    |> Enum.group_by(& &1.entry_id)
    |> Enum.map(fn {_entry_id, group} ->
      # Keep the highest scoring result
      Enum.max_by(group, & &1.score, fn -> hd(group) end)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp combine_memory_chunk_results(memory_results, chunk_results, memory_weight, chunk_weight) do
    # Normalize scores for both result sets
    memory_normalized = normalize_scores(memory_results)
    chunk_normalized = normalize_scores(chunk_results)

    # Build maps keyed by entry_id
    memory_map = Map.new(memory_normalized, &{&1.entry_id, &1})
    chunk_map = Map.new(chunk_normalized, &{&1.entry_id, &1})

    # Get all unique entry IDs
    all_entry_ids =
      (Map.keys(memory_map) ++ Map.keys(chunk_map))
      |> Enum.uniq()

    # Calculate combined scores
    all_entry_ids
    |> Enum.map(fn entry_id ->
      memory_result = Map.get(memory_map, entry_id)
      chunk_result = Map.get(chunk_map, entry_id)

      memory_score = if memory_result, do: memory_result.score, else: 0.0
      chunk_score = if chunk_result, do: chunk_result.score, else: 0.0

      combined_score = memory_score * memory_weight + chunk_score * chunk_weight

      # Use memory result as base if available (richer data), else chunk
      base = memory_result || chunk_result

      base
      |> Map.put(:combined_score, combined_score)
      |> Map.put(:memory_score, memory_score)
      |> Map.put(:chunk_score, chunk_score)
      |> Map.put(:score, combined_score)
    end)
    |> Enum.sort_by(& &1.combined_score, :desc)
  end

  defp normalize_scores(results) when results == [], do: []

  defp normalize_scores(results) do
    scores = Enum.map(results, & &1.score)
    max_score = Enum.max(scores)
    min_score = Enum.min(scores)
    range = max_score - min_score

    if range == 0 do
      # All same score, normalize to 1.0
      Enum.map(results, &Map.put(&1, :score, 1.0))
    else
      Enum.map(results, fn r ->
        normalized = (r.score - min_score) / range
        Map.put(r, :score, normalized)
      end)
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  defp embed_query(query) do
    OpenAI.embed(query)
  end
end
