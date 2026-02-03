defmodule Onelist.Reader.Behaviours.LLMProviderBehaviour do
  @moduledoc """
  Behaviour for LLM providers used in Reader Agent operations.

  Implement this behaviour to provide LLM capabilities for:
  - Memory extraction
  - Tag suggestion
  - Summary generation
  - Reference resolution
  - Relationship classification
  """

  @type memory_result :: %{
          memories: list(map()),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          cost_cents: number()
        }

  @type tag_result :: %{
          suggestions: list(map()),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          cost_cents: number()
        }

  @type summary_result :: %{
          summary: String.t(),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          cost_cents: number()
        }

  @type relationship_result :: %{
          relationship: String.t(),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil,
          cost_cents: number()
        }

  @type llm_error ::
          {:api_error, integer(), term()}
          | {:request_failed, term()}
          | {:rate_limited, term()}
          | {:parse_error, term()}

  @doc """
  Extract atomic memories from text content.

  ## Options
    * `:max_tokens` - Maximum tokens for response
    * `:reference_date` - Date for resolving temporal expressions

  ## Returns
    * `{:ok, memory_result}` - Extracted memories with metadata
    * `{:error, llm_error}` - Error details
  """
  @callback extract_memories(text :: String.t(), opts :: keyword()) ::
              {:ok, memory_result()} | {:error, llm_error()}

  @doc """
  Suggest tags for content based on analysis.

  ## Options
    * `:max_tokens` - Maximum tokens for response
    * `:max_suggestions` - Maximum number of suggestions
    * `:existing_tags` - List of existing tags to prefer

  ## Returns
    * `{:ok, tag_result}` - Tag suggestions with metadata
    * `{:error, llm_error}` - Error details
  """
  @callback suggest_tags(text :: String.t(), opts :: keyword()) ::
              {:ok, tag_result()} | {:error, llm_error()}

  @doc """
  Generate a concise summary of content.

  ## Options
    * `:max_tokens` - Maximum tokens for response
    * `:style` - Summary style: "concise", "detailed", or "bullets"

  ## Returns
    * `{:ok, summary_result}` - Generated summary with metadata
    * `{:error, llm_error}` - Error details
  """
  @callback generate_summary(text :: String.t(), opts :: keyword()) ::
              {:ok, summary_result()} | {:error, llm_error()}

  @doc """
  Classify the relationship between two memories.

  ## Returns
    * `{:ok, relationship_result}` - Relationship type with metadata
    * `{:error, llm_error}` - Error details
  """
  @callback classify_relationship(memory1 :: String.t(), memory2 :: String.t(), opts :: keyword()) ::
              {:ok, relationship_result()} | {:error, llm_error()}
end
