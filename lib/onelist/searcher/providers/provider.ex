defmodule Onelist.Searcher.Providers.Provider do
  @moduledoc """
  Behaviour for embedding providers.

  Embedding providers are responsible for converting text into vector embeddings.
  Different providers (OpenAI, Anthropic, local models) implement this behaviour
  to provide a consistent interface.
  """

  @doc """
  Generate embedding for a single text string.

  Returns `{:ok, vector}` where vector is a list of floats,
  or `{:error, reason}` on failure.
  """
  @callback embed(text :: String.t()) :: {:ok, list(float())} | {:error, term()}

  @doc """
  Generate embeddings for multiple texts in batch.

  Returns `{:ok, vectors}` where vectors is a list of lists of floats,
  or `{:error, reason}` on failure.
  """
  @callback embed_batch(texts :: list(String.t())) ::
              {:ok, list(list(float()))} | {:error, term()}

  @doc """
  Returns the model name used by this provider.
  """
  @callback model_name() :: String.t()

  @doc """
  Returns the model version.
  """
  @callback model_version() :: String.t()

  @doc """
  Returns the number of dimensions in the embedding vectors.
  """
  @callback dimensions() :: pos_integer()
end
