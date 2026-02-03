defmodule Onelist.Searcher.Providers.OpenAI do
  @moduledoc """
  OpenAI embedding provider implementation.

  Uses OpenAI's text-embedding-3-small model for generating vector embeddings.
  Supports both single and batch embedding requests.
  """

  @behaviour Onelist.Searcher.Providers.Provider

  require Logger

  @default_model "text-embedding-3-small"
  @default_dimensions 1536
  @model_version "2024-01"
  # OpenAI allows up to 2048 inputs per request, but we use smaller batches
  @batch_size 100
  @api_url "https://api.openai.com/v1/embeddings"

  @impl true
  def model_name, do: @default_model

  @impl true
  def model_version, do: @model_version

  @impl true
  def dimensions, do: @default_dimensions

  @doc """
  Generate embedding for a single text.
  """
  @impl true
  def embed(text) when is_binary(text) do
    case embed_batch([text]) do
      {:ok, [vector]} -> {:ok, vector}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate embeddings for multiple texts in batch.

  Automatically splits large batches into smaller chunks to avoid API limits.
  """
  @impl true
  def embed_batch(texts) when is_list(texts) do
    if Enum.empty?(texts) do
      {:ok, []}
    else
      api_key = get_api_key()

      texts
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
        case do_embed_request(batch, api_key) do
          {:ok, vectors} -> {:cont, {:ok, acc ++ vectors}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp do_embed_request(texts, api_key) do
    body = %{
      model: @default_model,
      input: texts,
      dimensions: @default_dimensions
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    start_time = System.monotonic_time(:millisecond)

    case Req.post(@api_url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %Req.Response{status: 200, body: response}} ->
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.debug(
          "OpenAI embedding request completed in #{duration}ms for #{length(texts)} texts"
        )

        vectors =
          response["data"]
          |> Enum.sort_by(& &1["index"])
          |> Enum.map(& &1["embedding"])

        {:ok, vectors}

      {:ok, %Req.Response{status: 401}} ->
        Logger.error("OpenAI API authentication failed - check API key")
        {:error, {:api_error, 401, "Authentication failed"}}

      {:ok, %Req.Response{status: 429, body: body}} ->
        Logger.warning("OpenAI API rate limited: #{inspect(body)}")
        {:error, {:rate_limited, body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, %Req.TransportError{reason: reason}} ->
        Logger.error("OpenAI request transport error: #{inspect(reason)}")
        {:error, {:transport_error, reason}}

      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise """
      OpenAI API key not configured.

      Set the OPENAI_API_KEY environment variable or configure it in your application:

          config :onelist, :openai_api_key, "sk-..."
      """
  end
end
