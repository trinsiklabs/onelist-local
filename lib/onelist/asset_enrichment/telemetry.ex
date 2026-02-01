defmodule Onelist.AssetEnrichment.Telemetry do
  @moduledoc """
  OpenTelemetry instrumentation for Asset Enrichment.

  Provides tracing, metrics, and observability for all enrichment operations.
  
  ## Events Emitted
  
  - `[:asset_enrichment, :orchestrate, :start | :stop | :exception]`
  - `[:asset_enrichment, :transcribe, :start | :stop | :exception]`
  - `[:asset_enrichment, :describe, :start | :stop | :exception]`
  - `[:asset_enrichment, :ocr, :start | :stop | :exception]`
  - `[:asset_enrichment, :extract_actions, :start | :stop | :exception]`
  - `[:asset_enrichment, :cost, :recorded]`
  - `[:asset_enrichment, :budget, :exceeded]`
  
  ## Metrics Available
  
  - Duration of each enrichment type
  - Cost per enrichment
  - Error rates by type and provider
  - Queue latency (time from enqueue to start)
  """

  require Logger

  @doc """
  Execute a function with telemetry span tracking.
  
  Emits start/stop/exception events for the given enrichment type.
  
  ## Examples
  
      span(:transcribe, %{asset_id: "abc", entry_id: "xyz"}, fn ->
        OpenAIWhisper.transcribe(audio_path)
      end)
  """
  def span(enrichment_type, metadata, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time()
    
    :telemetry.execute(
      [:asset_enrichment, enrichment_type, :start],
      %{system_time: System.system_time()},
      metadata
    )
    
    try do
      result = fun.()
      
      duration = System.monotonic_time() - start_time
      
      status = case result do
        {:ok, _} -> :ok
        :ok -> :ok
        {:error, _} -> :error
        {:snooze, _} -> :snooze
        _ -> :unknown
      end
      
      :telemetry.execute(
        [:asset_enrichment, enrichment_type, :stop],
        %{duration: duration},
        Map.merge(metadata, %{status: status, result: result})
      )
      
      result
    rescue
      e ->
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          [:asset_enrichment, enrichment_type, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: :error, reason: e, stacktrace: __STACKTRACE__})
        )
        
        reraise e, __STACKTRACE__
    catch
      kind, reason ->
        duration = System.monotonic_time() - start_time
        
        :telemetry.execute(
          [:asset_enrichment, enrichment_type, :exception],
          %{duration: duration},
          Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: __STACKTRACE__})
        )
        
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc """
  Record cost for an enrichment operation.
  """
  def record_cost(enrichment_type, cost_cents, metadata \\ %{}) do
    :telemetry.execute(
      [:asset_enrichment, :cost, :recorded],
      %{cost_cents: cost_cents},
      Map.merge(metadata, %{enrichment_type: enrichment_type})
    )
  end

  @doc """
  Record when a budget limit is exceeded.
  """
  def record_budget_exceeded(user_id, metadata \\ %{}) do
    :telemetry.execute(
      [:asset_enrichment, :budget, :exceeded],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{user_id: user_id})
    )
  end

  @doc """
  Record queue latency - time from job insertion to processing start.
  """
  def record_queue_latency(enrichment_type, inserted_at, metadata \\ %{})
  
  def record_queue_latency(_enrichment_type, nil, _metadata) do
    # Skip if inserted_at is nil (e.g., in tests with inline Oban)
    :ok
  end
  
  def record_queue_latency(enrichment_type, inserted_at, metadata) do
    queue_latency_ms = 
      DateTime.diff(DateTime.utc_now(), inserted_at, :millisecond)
    
    :telemetry.execute(
      [:asset_enrichment, :queue, :latency],
      %{latency_ms: queue_latency_ms},
      Map.merge(metadata, %{enrichment_type: enrichment_type})
    )
  end

  @doc """
  Record provider-specific metrics.
  """
  def record_provider_call(provider, operation, metadata \\ %{}) do
    :telemetry.execute(
      [:asset_enrichment, :provider, operation],
      %{system_time: System.system_time()},
      Map.merge(metadata, %{provider: provider})
    )
  end

  @doc """
  Record token usage for LLM-based operations.
  """
  def record_token_usage(provider, input_tokens, output_tokens, metadata \\ %{}) do
    :telemetry.execute(
      [:asset_enrichment, :tokens, :used],
      %{input_tokens: input_tokens || 0, output_tokens: output_tokens || 0},
      Map.merge(metadata, %{provider: provider})
    )
  end

  @doc """
  Returns all event prefixes that this module emits.
  Useful for setting up event handlers.
  """
  def event_prefixes do
    [
      [:asset_enrichment, :orchestrate],
      [:asset_enrichment, :transcribe],
      [:asset_enrichment, :describe],
      [:asset_enrichment, :ocr],
      [:asset_enrichment, :extract_actions],
      [:asset_enrichment, :cost],
      [:asset_enrichment, :budget],
      [:asset_enrichment, :queue],
      [:asset_enrichment, :provider],
      [:asset_enrichment, :tokens]
    ]
  end

  @doc """
  Returns all events that can be emitted.
  """
  def events do
    [
      [:asset_enrichment, :orchestrate, :start],
      [:asset_enrichment, :orchestrate, :stop],
      [:asset_enrichment, :orchestrate, :exception],
      [:asset_enrichment, :transcribe, :start],
      [:asset_enrichment, :transcribe, :stop],
      [:asset_enrichment, :transcribe, :exception],
      [:asset_enrichment, :describe, :start],
      [:asset_enrichment, :describe, :stop],
      [:asset_enrichment, :describe, :exception],
      [:asset_enrichment, :ocr, :start],
      [:asset_enrichment, :ocr, :stop],
      [:asset_enrichment, :ocr, :exception],
      [:asset_enrichment, :extract_actions, :start],
      [:asset_enrichment, :extract_actions, :stop],
      [:asset_enrichment, :extract_actions, :exception],
      [:asset_enrichment, :cost, :recorded],
      [:asset_enrichment, :budget, :exceeded],
      [:asset_enrichment, :queue, :latency],
      [:asset_enrichment, :provider, :call],
      [:asset_enrichment, :provider, :success],
      [:asset_enrichment, :provider, :error],
      [:asset_enrichment, :tokens, :used]
    ]
  end
end
