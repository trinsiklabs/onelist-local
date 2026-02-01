defmodule Onelist.Searcher.Reranker do
  @moduledoc """
  Cross-encoder reranking for improved search result relevance.

  Uses Cohere's rerank API to reorder search results based on
  semantic relevance to the query. This can significantly improve
  search quality by using a more powerful model for the final
  ranking step.

  ## How it works

  1. Initial retrieval returns N results with approximate scores
  2. Reranker takes top K results and query
  3. Cross-encoder model scores each result against query
  4. Results are reordered by new scores

  ## Configuration

  Configure in `config/config.exs`:

      config :onelist, :searcher,
        rerank_enabled: true,
        rerank_top_k: 10,
        rerank_threshold: 0.0

  ## Usage

      {:ok, reranked} = Reranker.rerank(query, results, top_k: 10)
  """

  alias Onelist.Searcher.ModelRouter
  alias Onelist.Searcher.Providers.Cohere
  alias Onelist.Searcher.Telemetry

  require Logger

  @default_top_k 10
  @default_threshold 0.0

  @doc """
  Rerank search results using cross-encoder model.

  ## Parameters
    - query: The search query
    - results: List of search result maps
    - opts: Options
      - `:enabled` - Whether to perform reranking (default: from config)
      - `:top_k` - Number of results to return (default: 10)
      - `:threshold` - Minimum score threshold (default: 0.0)
      - `:model` - Model to use (default: auto-selected)

  ## Returns
    - `{:ok, results}` - Reranked results
    - `{:error, reason}` - Error tuple
  """
  def rerank(query, results, opts \\ []) do
    enabled = Keyword.get(opts, :enabled, enabled?())
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    cond do
      not enabled ->
        {:ok, results}

      length(results) <= 1 ->
        # No point reranking single or empty result
        {:ok, results}

      not api_configured?() ->
        Logger.debug("Reranker: No API key configured, returning original results")
        {:ok, results}

      true ->
        do_rerank(query, results, top_k, threshold, opts)
    end
  end

  @doc """
  Check if reranking is enabled.
  """
  def enabled? do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:rerank_enabled, true)
  end

  @doc """
  Prepare documents for reranking from result maps.

  Extracts text content from various possible fields.
  """
  def prepare_documents(results) do
    Enum.map(results, fn result ->
      title = Map.get(result, :title, "")
      content = get_content(result)

      if content && content != "" do
        "#{title}\n\n#{content}"
      else
        title
      end
    end)
  end

  @doc """
  Apply reranked scores to original results.

  ## Parameters
    - original: Original result list
    - rerank_results: List of `%{index: i, score: s}` from reranker

  ## Returns
    List of results with updated scores, sorted by rerank_score.
  """
  def apply_reranked_scores(original, rerank_results) do
    # Build index -> score map
    score_map = Map.new(rerank_results, &{&1.index, &1.score})

    original
    |> Enum.with_index()
    |> Enum.map(fn {result, idx} ->
      rerank_score = Map.get(score_map, idx, 0.0)

      result
      |> Map.put(:original_score, Map.get(result, :score, 0.0))
      |> Map.put(:rerank_score, rerank_score)
    end)
    |> Enum.sort_by(& &1.rerank_score, :desc)
  end

  @doc """
  Filter results by minimum threshold.
  """
  def filter_by_threshold(results, threshold) do
    Enum.filter(results, fn result ->
      Map.get(result, :rerank_score, 0.0) >= threshold
    end)
  end

  @doc """
  Calculate average score improvement from reranking.
  """
  def calculate_improvement(_original, reranked) do
    if length(reranked) == 0 do
      0.0
    else
      improvements =
        reranked
        |> Enum.map(fn r ->
          Map.get(r, :rerank_score, 0.0) - Map.get(r, :original_score, 0.0)
        end)

      Enum.sum(improvements) / length(improvements)
    end
  end

  @doc """
  Select the appropriate reranking model.
  """
  def select_model(opts) do
    result_count = Keyword.get(opts, :result_count, 0)
    ModelRouter.select_model(:rerank, %{result_count: result_count})
  end

  @doc """
  Get default reranking options.
  """
  def default_options do
    [
      enabled: enabled?(),
      top_k: config(:rerank_top_k, @default_top_k),
      threshold: config(:rerank_threshold, @default_threshold)
    ]
  end

  # Private Functions

  defp do_rerank(query, results, top_k, threshold, opts) do
    start_time = System.monotonic_time(:millisecond)

    # Prepare documents for reranking
    documents = prepare_documents(results)

    # Select model based on result count
    model = Keyword.get(opts, :model, select_model(result_count: length(results)))

    # Call Cohere rerank API
    case Cohere.rerank(query, documents, top_n: length(results), model: model) do
      {:ok, rerank_results} ->
        # Apply new scores
        reranked = apply_reranked_scores(results, rerank_results)

        # Filter by threshold
        filtered = filter_by_threshold(reranked, threshold)

        # Take top_k
        final = Enum.take(filtered, top_k)

        # Track telemetry
        duration_ms = System.monotonic_time(:millisecond) - start_time
        improvement = calculate_improvement(results, final)

        Telemetry.track_rerank(%{
          duration_ms: duration_ms,
          input_count: length(results),
          output_count: length(final),
          model: model,
          score_improvement: improvement
        })

        {:ok, final}

      {:error, :api_key_not_configured} ->
        Logger.debug("Reranker: API key not configured, returning original results")
        {:ok, results}

      {:error, reason} ->
        Logger.warning("Reranker failed: #{inspect(reason)}, returning original results")
        {:ok, results}
    end
  end

  defp get_content(result) do
    # Try various content fields in order of preference
    Map.get(result, :content) ||
      Map.get(result, :chunk_text) ||
      Map.get(result, :content_preview) ||
      Map.get(result, :source_chunk)
  end

  defp api_configured? do
    not is_nil(Application.get_env(:onelist, :cohere_api_key) || System.get_env("COHERE_API_KEY"))
  end

  defp config(key, default) do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(key, default)
  end
end
