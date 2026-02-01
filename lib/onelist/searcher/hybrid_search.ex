defmodule Onelist.Searcher.HybridSearch do
  @moduledoc """
  Hybrid search combining semantic vector similarity with full-text search.

  Results from both search methods are normalized and combined using
  configurable weights to produce a final ranked list.

  ## Enhanced Features (v2)

  Based on AI agent best practices, this module now supports:

  - **Rate Limiting**: Per-user, per-operation limits
  - **Telemetry**: OpenTelemetry-compatible instrumentation
  - **Reranking**: Optional cross-encoder reranking via Cohere
  - **Query Reformulation**: Expand abbreviations, generate synonyms
  - **Verification**: Self-verification loop (post-MVP)

  ## Configuration

      config :onelist, :searcher,
        rerank_enabled: true,
        reformulation_enabled: true,
        rate_limit_enabled: true,
        verification_enabled: false  # Post-MVP
  """

  alias Onelist.Searcher.Search
  alias Onelist.Searcher.Providers.OpenAI
  alias Onelist.Searcher.{Telemetry, RateLimiter, Reranker, QueryReformulator, Verifier}

  require Logger

  @default_semantic_weight 0.7
  @default_keyword_weight 0.3

  @doc """
  Perform hybrid search with configurable weights.

  ## Options
    * `:semantic_weight` - Weight for semantic results (default: 0.7)
    * `:keyword_weight` - Weight for keyword results (default: 0.3)
    * `:limit` - Max results (default: 20)
    * `:offset` - Pagination offset (default: 0)
    * `:filters` - Map of filters (entry_types, tags, date_range)
    * `:rerank` - Enable reranking (default: from config)
    * `:reformulate` - Enable query reformulation (default: from config)
    * `:verify` - Enable result verification (default: from config)
  """
  def search(user_id, query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    # Check rate limit
    case check_rate_limit(user_id) do
      {:ok, _remaining} ->
        do_search(user_id, query, opts, start_time)

      {:error, :rate_limited, retry_after} ->
        Telemetry.track_rate_limit(user_id, :search, retry_after)
        {:error, {:rate_limited, retry_after}}
    end
  end

  @doc """
  Perform enhanced search with all features.

  This is the full pipeline:
  1. Rate limit check
  2. Query reformulation (optional)
  3. Hybrid search
  4. Reranking (optional)
  5. Verification (optional)
  """
  def enhanced_search(user_id, query, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    with {:ok, _} <- check_rate_limit(user_id),
         {:ok, queries} <- maybe_reformulate(query, opts),
         {:ok, combined_results} <- search_all_variants(user_id, queries, opts),
         {:ok, reranked} <- maybe_rerank(query, combined_results, opts),
         {:ok, verified} <- maybe_verify(query, reranked, opts) do

      duration_ms = System.monotonic_time(:millisecond) - start_time

      Telemetry.track_search(query, verified.results, %{
        duration_ms: duration_ms,
        result_count: length(verified.results),
        search_type: "enhanced_hybrid",
        model: OpenAI.model_name()
      })

      {:ok, %{
        results: verified.results,
        total: length(verified.results),
        query: query,
        search_type: "enhanced_hybrid",
        confidence: verified.confidence,
        query_variants: length(queries),
        duration_ms: duration_ms
      }}
    end
  end

  # Standard search without enhanced features
  defp do_search(user_id, query, opts, start_time) do
    semantic_weight = Keyword.get(opts, :semantic_weight, @default_semantic_weight)
    keyword_weight = Keyword.get(opts, :keyword_weight, @default_keyword_weight)
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.get(opts, :filters, %{})

    # Fetch more results than needed for re-ranking
    fetch_limit = limit * 3

    with {:ok, query_embedding} <- embed_query(query),
         {:ok, semantic_results} <- semantic_search(user_id, query_embedding, filters, fetch_limit),
         {:ok, keyword_results} <- keyword_search(user_id, query, filters, fetch_limit) do

      # Combine and re-rank
      combined = combine_results(
        semantic_results,
        keyword_results,
        semantic_weight,
        keyword_weight
      )

      # Optional reranking
      reranked = if Keyword.get(opts, :rerank, Reranker.enabled?()) do
        case Reranker.rerank(query, combined, top_k: limit) do
          {:ok, results} -> results
          {:error, _} -> combined
        end
      else
        combined
      end

      # Apply pagination
      results =
        reranked
        |> Enum.drop(offset)
        |> Enum.take(limit)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      Telemetry.track_search(query, results, %{
        duration_ms: duration_ms,
        result_count: length(results),
        search_type: "hybrid",
        model: OpenAI.model_name()
      })

      {:ok, %{
        results: results,
        total: length(combined),
        query: query,
        search_type: "hybrid",
        weights: %{semantic: semantic_weight, keyword: keyword_weight},
        duration_ms: duration_ms
      }}
    end
  end

  defp embed_query(query) do
    OpenAI.embed(query)
  end

  defp semantic_search(user_id, query_vector, filters, limit) do
    results = Search.do_semantic_search(user_id, query_vector, filters, limit, 0)
    {:ok, results}
  end

  defp keyword_search(user_id, query, filters, limit) do
    results = Search.do_keyword_search(user_id, query, filters, limit, 0)
    {:ok, results}
  end

  defp combine_results(semantic_results, keyword_results, semantic_weight, keyword_weight) do
    # Normalize scores to 0-1 range
    semantic_normalized = normalize_scores(semantic_results)
    keyword_normalized = normalize_scores(keyword_results)

    # Build maps for efficient lookup
    semantic_map = Map.new(semantic_normalized, &{&1.entry_id, &1})
    keyword_map = Map.new(keyword_normalized, &{&1.entry_id, &1})

    # Get all unique entry IDs
    all_ids =
      (Enum.map(semantic_normalized, & &1.entry_id) ++
       Enum.map(keyword_normalized, & &1.entry_id))
      |> Enum.uniq()

    # Calculate combined scores
    all_ids
    |> Enum.map(fn id ->
      semantic_result = Map.get(semantic_map, id)
      keyword_result = Map.get(keyword_map, id)

      semantic_score = if semantic_result, do: semantic_result.score, else: 0.0
      keyword_score = if keyword_result, do: keyword_result.score, else: 0.0

      combined_score = (semantic_score * semantic_weight) + (keyword_score * keyword_weight)

      # Use the first available result for metadata
      base = semantic_result || keyword_result

      %{
        entry_id: id,
        title: base.title,
        entry_type: base.entry_type,
        combined_score: combined_score,
        semantic_score: semantic_score,
        keyword_score: keyword_score
      }
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

  # Enhanced search helper functions

  defp check_rate_limit(user_id) do
    if RateLimiter.enabled?() do
      # Check if RateLimiter is running
      if Process.whereis(RateLimiter) do
        RateLimiter.check_limit(user_id, :search)
      else
        {:ok, :not_started}
      end
    else
      {:ok, :disabled}
    end
  end

  defp maybe_reformulate(query, opts) do
    if Keyword.get(opts, :reformulate, QueryReformulator.enabled?()) do
      QueryReformulator.reformulate(query, opts)
    else
      {:ok, [query]}
    end
  end

  defp search_all_variants(user_id, queries, opts) do
    # Search with all query variants in parallel
    results =
      queries
      |> Task.async_stream(fn q ->
        case do_search(user_id, q, Keyword.put(opts, :rerank, false), System.monotonic_time(:millisecond)) do
          {:ok, %{results: r}} -> r
          _ -> []
        end
      end, timeout: 30_000)
      |> Enum.flat_map(fn
        {:ok, results} -> results
        _ -> []
      end)

    # Merge results, keeping highest score per entry
    merged = QueryReformulator.merge_results([results])

    {:ok, merged}
  end

  defp maybe_rerank(query, results, opts) do
    if Keyword.get(opts, :rerank, Reranker.enabled?()) do
      Reranker.rerank(query, results, opts)
    else
      {:ok, results}
    end
  end

  defp maybe_verify(query, results, opts) do
    if Keyword.get(opts, :verify, Verifier.enabled?()) do
      Verifier.verify_results(query, results, opts)
    else
      {:ok, %{results: results, confidence: :skipped}}
    end
  end
end
