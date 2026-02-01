defmodule Onelist.Searcher.Verifier do
  @moduledoc """
  Self-verification for search results.

  Implements the verification loop from Agentic RAG patterns:
  1. Assess relevance of results to query
  2. Determine confidence level
  3. Suggest reformulation if confidence is low
  4. Optionally trigger re-search

  ## Configuration

  Configure in `config/config.exs`:

      config :onelist, :searcher,
        verification_enabled: false,  # Enable post-MVP
        verification_threshold: 0.5,
        max_verification_retries: 3

  ## Usage

      {:ok, verification} = Verifier.verify_results(query, results)
      if verification.confidence == :low do
        # Re-search with reformulated query
      end
  """

  require Logger

  @default_threshold 0.5
  @default_max_retries 3

  @high_threshold 0.7
  @medium_threshold 0.4

  @doc """
  Verify that search results are relevant to the query.

  ## Parameters
    - query: The original search query
    - results: List of search result maps
    - opts: Options
      - `:enabled` - Whether to perform verification (default: from config)
      - `:threshold` - Minimum relevance threshold (default: 0.5)

  ## Returns
    - `{:ok, verification}` - Verification result with:
      - `:results` - Results with relevance scores
      - `:confidence` - :high, :medium, :low, :insufficient, or :skipped
      - `:suggestion` - Optional reformulation suggestion
  """
  def verify_results(query, results, opts \\ []) do
    enabled = Keyword.get(opts, :enabled, enabled?())

    cond do
      not enabled ->
        {:ok, %{
          results: results,
          confidence: :skipped,
          suggestion: nil
        }}

      results == [] ->
        {:ok, %{
          results: [],
          confidence: :insufficient,
          suggestion: suggest_reformulation(query, [])
        }}

      true ->
        do_verify(query, results, opts)
    end
  end

  @doc """
  Check if verification is enabled.
  """
  def enabled? do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:verification_enabled, false)  # Disabled by default (post-MVP)
  end

  @doc """
  Assess relevance of results to query.

  Returns results with added relevance_score field.
  """
  def assess_relevance(query, results) do
    Enum.map(results, fn result ->
      text = build_text(result)
      score = calculate_keyword_overlap(query, text)

      Map.put(result, :relevance_score, score)
    end)
  end

  @doc """
  Determine overall confidence level from assessments.
  """
  def determine_confidence(assessments) do
    if assessments == [] do
      :insufficient
    else
      avg_score =
        assessments
        |> Enum.map(& &1.relevance_score)
        |> Enum.sum()
        |> Kernel./(length(assessments))

      cond do
        avg_score >= @high_threshold -> :high
        avg_score >= @medium_threshold -> :medium
        true -> :low
      end
    end
  end

  @doc """
  Check if we should retry with a reformulated query.
  """
  def should_retry?(confidence) do
    confidence in [:low, :insufficient]
  end

  @doc """
  Suggest how to reformulate the query for better results.
  """
  def suggest_reformulation(query, results) do
    cond do
      String.length(query) < 10 ->
        "Try adding more context to your search query"

      String.contains?(query, " and ") or String.contains?(query, " or ") ->
        "Try splitting your query into separate searches"

      results == [] ->
        "Try using different keywords or broadening your search"

      true ->
        nil
    end
  end

  @doc """
  Filter results by minimum relevance threshold.
  """
  def filter_by_relevance(results, threshold) do
    Enum.filter(results, fn result ->
      Map.get(result, :relevance_score, 1.0) >= threshold
    end)
  end

  @doc """
  Calculate keyword overlap between query and text.

  Returns a score from 0.0 to 1.0 based on what percentage
  of query keywords appear in the text.
  """
  def calculate_keyword_overlap(query, text) do
    query_keywords = extract_keywords(query)
    text_keywords = extract_keywords(text)

    if query_keywords == [] do
      0.0
    else
      matches =
        query_keywords
        |> Enum.count(fn keyword -> keyword in text_keywords end)

      matches / length(query_keywords)
    end
  end

  @doc """
  Get default verification options.
  """
  def default_options do
    [
      enabled: enabled?(),
      threshold: config(:verification_threshold, @default_threshold),
      max_retries: config(:max_verification_retries, @default_max_retries)
    ]
  end

  # Private Functions

  defp do_verify(query, results, opts) do
    threshold = Keyword.get(opts, :threshold, @default_threshold)

    # Assess relevance of each result
    assessed = assess_relevance(query, results)

    # Determine overall confidence
    confidence = determine_confidence(assessed)

    # Filter by threshold
    filtered = filter_by_relevance(assessed, threshold)

    # Generate suggestion if confidence is low
    suggestion = if should_retry?(confidence) do
      suggest_reformulation(query, filtered)
    else
      nil
    end

    {:ok, %{
      results: filtered,
      confidence: confidence,
      suggestion: suggestion,
      original_count: length(results),
      filtered_count: length(filtered)
    }}
  end

  defp build_text(result) do
    title = Map.get(result, :title, "")
    content = Map.get(result, :content, "") ||
              Map.get(result, :chunk_text, "") ||
              Map.get(result, :content_preview, "")

    "#{title} #{content}"
  end

  defp extract_keywords(text) when is_binary(text) do
    stop_words = ~w(a an the is are was were be been being have has had do does did
                    will would could should may might must shall can this that these
                    those it its what which who whom whose when where why how and or
                    but if then else for of to from by with at in on as)

    text
    |> String.downcase()
    |> String.split(~r/[^\w]+/)
    |> Enum.filter(fn word ->
      String.length(word) > 2 and word not in stop_words
    end)
    |> Enum.uniq()
  end

  defp extract_keywords(_), do: []

  defp config(key, default) do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(key, default)
  end
end
