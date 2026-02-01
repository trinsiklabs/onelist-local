defmodule Onelist.Searcher.ModelRouter do
  @moduledoc """
  Dynamic model selection for Searcher operations.

  Routes to appropriate models based on task complexity to optimize
  costs while maintaining quality. Following recommendations from
  the AI agent implementation guide, this can achieve 40-60% cost savings.

  ## Routing Strategy

  | Operation | Simple/Small | Complex/Large |
  |-----------|--------------|---------------|
  | Embedding | text-embedding-3-small | text-embedding-3-small |
  | Rerank | rerank-multilingual-v2.0 | rerank-english-v3.0 |
  | Query Expansion | gpt-4o-mini | gpt-4o |
  | Verification | gpt-4o-mini | gpt-4o-mini |
  | Summarization | gpt-4o-mini | gpt-4o |

  ## Usage

      model = ModelRouter.select_model(:rerank, %{result_count: 100})
      # => "rerank-english-v3.0"

      model = ModelRouter.select_model(:query_expansion, %{query_length: 10})
      # => "gpt-4o-mini"
  """

  @doc """
  Select the appropriate model for an operation based on context.

  ## Parameters
    - operation: The operation type
      - `:embedding` - Generate embeddings
      - `:rerank` - Rerank search results
      - `:query_expansion` - Expand/reformulate queries
      - `:verification` - Verify result relevance
      - `:summarization` - Summarize content
    - context: Map containing operation-specific context
      - For `:rerank`: `%{result_count: integer}`
      - For `:query_expansion`: `%{query_length: integer}`
      - For `:summarization`: `%{content_length: integer}`

  ## Returns
    Model name string.
  """
  def select_model(operation, context \\ %{})

  def select_model(:embedding, _context) do
    "text-embedding-3-small"
  end

  def select_model(:rerank, %{result_count: count}) when count > 50 do
    "rerank-english-v3.0"
  end

  def select_model(:rerank, _context) do
    "rerank-multilingual-v2.0"
  end

  def select_model(:query_expansion, %{query_length: length}) when length > 20 do
    "gpt-4o"
  end

  def select_model(:query_expansion, _context) do
    "gpt-4o-mini"
  end

  def select_model(:verification, _context) do
    "gpt-4o-mini"
  end

  def select_model(:summarization, %{content_length: length}) when length > 5000 do
    "gpt-4o"
  end

  def select_model(:summarization, _context) do
    "gpt-4o-mini"
  end

  def select_model(_unknown_operation, _context) do
    "gpt-4o-mini"
  end

  @doc """
  Get cost per 1K tokens for a model.

  ## Returns
    Map with `:input` and `:output` costs, or `nil` if unknown model.
  """
  def get_model_cost(model) do
    costs = %{
      # OpenAI GPT-4o models (as of 2024)
      "gpt-4o" => %{input: 0.0025, output: 0.01},
      "gpt-4o-mini" => %{input: 0.00015, output: 0.0006},

      # OpenAI embedding models
      "text-embedding-3-small" => %{input: 0.00002, output: 0.0},
      "text-embedding-3-large" => %{input: 0.00013, output: 0.0},

      # Cohere rerank models (approximate)
      "rerank-english-v3.0" => %{input: 0.001, output: 0.0},
      "rerank-multilingual-v2.0" => %{input: 0.0005, output: 0.0}
    }

    Map.get(costs, model)
  end

  @doc """
  Estimate the cost for a model call.

  ## Parameters
    - model: Model name
    - input_tokens: Number of input tokens
    - output_tokens: Number of output tokens

  ## Returns
    Estimated cost in dollars.
  """
  def estimate_cost(model, input_tokens, output_tokens) do
    case get_model_cost(model) do
      nil ->
        0.0

      %{input: input_rate, output: output_rate} ->
        (input_tokens / 1000 * input_rate) + (output_tokens / 1000 * output_rate)
    end
  end

  @doc """
  Check if a cheaper model should be used based on context.

  ## Parameters
    - operation: The operation type
    - context: Operation context

  ## Returns
    Boolean indicating if cheaper model is appropriate.
  """
  def should_use_cheaper_model?(operation, context) do
    case operation do
      :rerank ->
        Map.get(context, :result_count, 0) <= 50

      :query_expansion ->
        Map.get(context, :query_length, 0) <= 20

      :summarization ->
        Map.get(context, :content_length, 0) <= 5000

      :verification ->
        true  # Always use cheaper model

      :embedding ->
        true  # Only one embedding model

      _ ->
        true
    end
  end

  @doc """
  Get all available models for an operation.

  ## Parameters
    - operation: The operation type

  ## Returns
    List of model names.
  """
  def models_for_operation(operation) do
    case operation do
      :embedding ->
        ["text-embedding-3-small", "text-embedding-3-large"]

      :rerank ->
        ["rerank-english-v3.0", "rerank-multilingual-v2.0"]

      :query_expansion ->
        ["gpt-4o", "gpt-4o-mini"]

      :verification ->
        ["gpt-4o", "gpt-4o-mini"]

      :summarization ->
        ["gpt-4o", "gpt-4o-mini"]

      _ ->
        ["gpt-4o", "gpt-4o-mini"]
    end
  end

  @doc """
  Get the default model for an operation.
  """
  def default_model(operation) do
    select_model(operation, %{})
  end

  @doc """
  Calculate potential cost savings from using model routing.

  Compares the cost of always using the premium model vs.
  dynamically routing based on context.

  ## Parameters
    - operation: The operation type
    - contexts: List of context maps

  ## Returns
    Map with `:premium_cost`, `:routed_cost`, and `:savings_percent`.
  """
  def calculate_savings(operation, contexts) when is_list(contexts) do
    models = models_for_operation(operation)
    premium_model = List.first(models)  # Assume first is premium
    default_tokens = %{input: 500, output: 100}

    premium_cost =
      contexts
      |> Enum.map(fn _ctx ->
        estimate_cost(premium_model, default_tokens.input, default_tokens.output)
      end)
      |> Enum.sum()

    routed_cost =
      contexts
      |> Enum.map(fn ctx ->
        model = select_model(operation, ctx)
        estimate_cost(model, default_tokens.input, default_tokens.output)
      end)
      |> Enum.sum()

    savings_percent = if premium_cost > 0 do
      (premium_cost - routed_cost) / premium_cost * 100
    else
      0.0
    end

    %{
      premium_cost: premium_cost,
      routed_cost: routed_cost,
      savings_percent: Float.round(savings_percent, 2)
    }
  end
end
