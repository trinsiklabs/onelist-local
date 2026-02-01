defmodule Onelist.Searcher.Providers.Cohere do
  @moduledoc """
  Cohere API provider for reranking search results.

  Uses Cohere's rerank API to improve search result relevance
  using cross-encoder models.

  ## Configuration

  Configure the API key in `config/runtime.exs`:

      config :onelist, :cohere_api_key, System.get_env("COHERE_API_KEY")

  ## Usage

      {:ok, results} = Cohere.rerank("query", documents, top_n: 10)

  ## Models

  - `rerank-english-v3.0` - English optimized (default)
  - `rerank-multilingual-v2.0` - Multilingual support
  """

  require Logger

  @api_url "https://api.cohere.ai/v1/rerank"
  @default_model "rerank-english-v3.0"
  @default_top_n 10

  # Cost per 1000 searches (approximate)
  @cost_per_1000 1.0

  @doc """
  Rerank documents based on relevance to query.

  ## Parameters
    - query: The search query
    - documents: List of document strings to rerank
    - opts: Options
      - `:top_n` - Number of top results to return (default: 10)
      - `:model` - Model to use (default: "rerank-english-v3.0")
      - `:return_documents` - Include document text in results (default: false)

  ## Returns
    - `{:ok, results}` - List of reranked results with scores
    - `{:error, reason}` - Error tuple
  """
  def rerank(query, documents, opts \\ []) when is_list(documents) do
    api_key = get_api_key()

    if is_nil(api_key) do
      {:error, :api_key_not_configured}
    else
      do_rerank(query, documents, opts, api_key)
    end
  end

  @doc """
  Returns the default model name.
  """
  def model_name, do: @default_model

  @doc """
  Returns the model name for a specific variant.

  ## Variants
    - `:english` - English optimized model
    - `:multilingual` - Multilingual model
  """
  def model_name(:english), do: "rerank-english-v3.0"
  def model_name(:multilingual), do: "rerank-multilingual-v2.0"
  def model_name(_), do: @default_model

  @doc """
  Estimate cost for a reranking operation.

  ## Parameters
    - document_count: Number of documents to rerank

  ## Returns
    Estimated cost in dollars.
  """
  def estimate_cost(document_count) when is_integer(document_count) and document_count >= 0 do
    document_count / 1000 * @cost_per_1000
  end

  @doc """
  Build the request body for the Cohere API.

  Exposed for testing.
  """
  def build_request(query, documents, opts) do
    model = Keyword.get(opts, :model, @default_model)
    top_n = Keyword.get(opts, :top_n, @default_top_n)
    return_documents = Keyword.get(opts, :return_documents, false)

    body = %{
      "model" => model,
      "query" => query,
      "documents" => documents,
      "top_n" => top_n
    }

    if return_documents do
      Map.put(body, "return_documents", true)
    else
      body
    end
  end

  @doc """
  Parse the API response into result structs.

  Exposed for testing.
  """
  def parse_response(%{"results" => results}) do
    parsed =
      results
      |> Enum.map(fn result ->
        %{
          index: result["index"],
          score: result["relevance_score"],
          document: get_in(result, ["document", "text"])
        }
      end)

    {:ok, parsed}
  end

  def parse_response(_), do: {:error, :invalid_response}

  # Private Functions

  defp do_rerank(query, documents, opts, api_key) do
    body = build_request(query, documents, opts)

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case Req.post(@api_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response_body}} ->
        parse_response(response_body)

      {:ok, %{status: status, body: body}} ->
        Logger.error("Cohere API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        Logger.error("Cohere request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_api_key do
    Application.get_env(:onelist, :cohere_api_key) ||
      System.get_env("COHERE_API_KEY")
  end
end
