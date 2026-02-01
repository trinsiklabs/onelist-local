defmodule Onelist.Searcher.Telemetry do
  @moduledoc """
  OpenTelemetry instrumentation for the Searcher agent.

  Follows gen_ai.* semantic conventions from the OpenTelemetry specification
  for AI/LLM operations.

  ## Event Names

  - `[:onelist, :searcher, :search, :start]` - Search started
  - `[:onelist, :searcher, :search, :stop]` - Search completed
  - `[:onelist, :searcher, :embed, :start]` - Embedding started
  - `[:onelist, :searcher, :embed, :stop]` - Embedding completed
  - `[:onelist, :searcher, :rerank, :start]` - Reranking started
  - `[:onelist, :searcher, :rerank, :stop]` - Reranking completed
  - `[:onelist, :searcher, :rate_limited]` - Rate limit exceeded

  ## Measurements

  - `duration_ms` - Operation duration in milliseconds
  - `result_count` - Number of results returned
  - `chunks` - Number of chunks processed
  - `cost_cents` - API cost in cents
  - `score_improvement` - Score improvement from reranking

  ## Metadata (following gen_ai.* conventions)

  - `gen_ai.operation.name` - Operation type
  - `gen_ai.request.model` - Model used
  - `gen_ai.usage.input_tokens` - Input tokens consumed
  - `gen_ai.usage.output_tokens` - Output tokens produced
  """

  require Logger

  @doc """
  Track a search operation.

  ## Parameters
    - query: The search query string
    - results: List of search results
    - metadata: Map containing operation metadata
      - `:duration_ms` - Duration in milliseconds
      - `:result_count` - Number of results (optional, calculated from results)
      - `:search_type` - Type of search (hybrid, semantic, keyword)
      - `:model` - Embedding model used
  """
  def track_search(query, results, metadata \\ %{}) do
    result_count = Map.get(metadata, :result_count, length(results))

    measurements = %{
      duration_ms: Map.get(metadata, :duration_ms, 0),
      result_count: result_count
    }

    meta = %{
      query_length: String.length(query || ""),
      search_type: Map.get(metadata, :search_type, "hybrid"),
      model: Map.get(metadata, :model)
    }

    :telemetry.execute(
      [:onelist, :searcher, :search, :stop],
      measurements,
      meta
    )

    Logger.debug("Searcher: search completed",
      query_length: meta.query_length,
      search_type: meta.search_type,
      result_count: result_count,
      duration_ms: measurements.duration_ms
    )
  end

  @doc """
  Track an embedding operation.

  ## Parameters
    - entry_id: The entry being embedded
    - chunks: Number of chunks embedded
    - cost_cents: API cost in cents
  """
  def track_embed(entry_id, chunks, cost_cents) do
    measurements = %{
      chunks: chunks,
      cost_cents: cost_cents
    }

    meta = %{
      entry_id: entry_id
    }

    :telemetry.execute(
      [:onelist, :searcher, :embed, :stop],
      measurements,
      meta
    )

    Logger.debug("Searcher: embedding completed",
      entry_id: entry_id,
      chunks: chunks,
      cost_cents: cost_cents
    )
  end

  @doc """
  Track a reranking operation.

  ## Parameters
    - metadata: Map containing:
      - `:duration_ms` - Duration in milliseconds
      - `:input_count` - Number of results before reranking
      - `:output_count` - Number of results after reranking
      - `:model` - Reranking model used
      - `:score_improvement` - Average score improvement
  """
  def track_rerank(metadata) do
    measurements = %{
      duration_ms: Map.get(metadata, :duration_ms, 0),
      input_count: Map.get(metadata, :input_count, 0),
      output_count: Map.get(metadata, :output_count, 0),
      score_improvement: Map.get(metadata, :score_improvement, 0.0)
    }

    meta = %{
      model: Map.get(metadata, :model)
    }

    :telemetry.execute(
      [:onelist, :searcher, :rerank, :stop],
      measurements,
      meta
    )

    Logger.debug("Searcher: reranking completed",
      model: meta.model,
      input_count: measurements.input_count,
      output_count: measurements.output_count,
      duration_ms: measurements.duration_ms
    )
  end

  @doc """
  Track when a rate limit is exceeded.

  ## Parameters
    - user_id: The user who hit the rate limit
    - operation: The operation that was rate limited
    - retry_after_seconds: Seconds until the limit resets
  """
  def track_rate_limit(user_id, operation, retry_after_seconds) do
    measurements = %{
      retry_after_seconds: retry_after_seconds
    }

    meta = %{
      user_id: user_id,
      operation: operation
    }

    :telemetry.execute(
      [:onelist, :searcher, :rate_limited],
      measurements,
      meta
    )

    Logger.warning("Searcher: rate limit exceeded",
      user_id: user_id,
      operation: operation,
      retry_after_seconds: retry_after_seconds
    )
  end

  @doc """
  Execute a function within a telemetry span.

  Automatically measures duration and emits start/stop/exception events.

  ## Parameters
    - event_prefix: The telemetry event prefix (e.g., [:onelist, :searcher, :search])
    - metadata: Additional metadata to include in events
    - func: The function to execute

  ## Returns
    The result of the function.

  ## Example

      Telemetry.span([:onelist, :searcher, :search], %{user_id: user_id}, fn ->
        do_search(query)
      end)
  """
  def span(event_prefix, metadata, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(event_prefix ++ [:start], %{system_time: System.system_time()}, metadata)

    try do
      result = func.()
      duration = System.monotonic_time() - start_time
      duration_native = System.convert_time_unit(duration, :native, :microsecond)

      :telemetry.execute(
        event_prefix ++ [:stop],
        %{duration: duration_native},
        metadata
      )

      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        duration_native = System.convert_time_unit(duration, :native, :microsecond)

        :telemetry.execute(
          event_prefix ++ [:exception],
          %{duration: duration_native},
          Map.merge(metadata, %{kind: :error, reason: e})
        )

        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Generate OpenTelemetry gen_ai.* semantic attributes.

  ## Parameters
    - attrs: Map containing:
      - `:operation` - Operation name (search, embed, rerank)
      - `:model` - Model name
      - `:input_tokens` - Input tokens consumed
      - `:output_tokens` - Output tokens produced
      - `:finish_reason` - Completion reason

  ## Returns
    Map with gen_ai.* prefixed keys.
  """
  def gen_ai_attributes(attrs) when is_map(attrs) do
    mappings = [
      {:operation, "gen_ai.operation.name"},
      {:model, "gen_ai.request.model"},
      {:input_tokens, "gen_ai.usage.input_tokens"},
      {:output_tokens, "gen_ai.usage.output_tokens"},
      {:finish_reason, "gen_ai.response.finish_reasons"}
    ]

    mappings
    |> Enum.reduce(%{}, fn {key, otel_key}, acc ->
      case Map.get(attrs, key) do
        nil -> acc
        value -> Map.put(acc, otel_key, value)
      end
    end)
  end

  @doc """
  Attach default telemetry handlers for logging.

  Call this during application startup to enable automatic logging
  of all searcher telemetry events.
  """
  def attach_default_handlers do
    events = [
      [:onelist, :searcher, :search, :stop],
      [:onelist, :searcher, :embed, :stop],
      [:onelist, :searcher, :rerank, :stop],
      [:onelist, :searcher, :rate_limited]
    ]

    :telemetry.attach_many(
      "onelist-searcher-default-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event([:onelist, :searcher, :search, :stop], measurements, metadata, _config) do
    Logger.info("Search completed",
      result_count: measurements.result_count,
      duration_ms: measurements.duration_ms,
      search_type: metadata.search_type
    )
  end

  defp handle_event([:onelist, :searcher, :embed, :stop], measurements, metadata, _config) do
    Logger.info("Embedding completed",
      entry_id: metadata.entry_id,
      chunks: measurements.chunks,
      cost_cents: measurements.cost_cents
    )
  end

  defp handle_event([:onelist, :searcher, :rerank, :stop], measurements, metadata, _config) do
    Logger.info("Reranking completed",
      model: metadata.model,
      input_count: measurements.input_count,
      output_count: measurements.output_count
    )
  end

  defp handle_event([:onelist, :searcher, :rate_limited], measurements, metadata, _config) do
    Logger.warning("Rate limit exceeded",
      user_id: metadata.user_id,
      operation: metadata.operation,
      retry_after: measurements.retry_after_seconds
    )
  end
end
