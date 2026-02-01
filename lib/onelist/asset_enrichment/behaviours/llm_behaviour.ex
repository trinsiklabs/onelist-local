defmodule Onelist.AssetEnrichment.LLMBehaviour do
  @moduledoc """
  Behaviour for LLM providers used in extraction tasks.
  
  Implement this behaviour to provide LLM capabilities for action item
  extraction and other text analysis tasks.
  """

  @type llm_result :: %{
    content: term(),
    model: String.t(),
    input_tokens: integer() | nil,
    output_tokens: integer() | nil,
    cost_cents: integer()
  }

  @type llm_error :: 
    {:api_error, integer(), term()} |
    {:request_failed, term()} |
    :invalid_json_response

  @doc """
  Send a chat completion request to the LLM.
  
  ## Arguments
    * `messages` - List of message maps with :role and :content
    * `opts` - Options including:
      * `:model` - Model to use
      * `:temperature` - Temperature setting
      * `:max_tokens` - Maximum tokens in response
      * `:response_format` - Response format (e.g., json_object)
  
  ## Returns
    * `{:ok, result}` - Result with parsed content, model info, usage
    * `{:error, reason}` - Error details
  """
  @callback chat_completion(messages :: list(map()), opts :: keyword()) ::
    {:ok, llm_result()} | {:error, llm_error()}

  @doc """
  Estimate cost based on token usage.
  """
  @callback estimate_cost(model :: String.t(), input_tokens :: integer(), output_tokens :: integer()) :: integer()
end
