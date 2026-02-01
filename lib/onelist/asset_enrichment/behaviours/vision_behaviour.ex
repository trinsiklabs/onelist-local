defmodule Onelist.AssetEnrichment.VisionBehaviour do
  @moduledoc """
  Behaviour for vision/image analysis providers.
  
  Implement this behaviour to provide image description and OCR capabilities.
  The default implementation uses OpenAI's GPT-4 Vision API.
  """

  @type vision_result :: %{
    description: String.t() | nil,
    text: String.t() | nil,
    model: String.t(),
    input_tokens: integer() | nil,
    output_tokens: integer() | nil,
    cost_cents: integer()
  }

  @type vision_error :: 
    {:file_not_found, String.t()} | 
    {:api_error, integer(), term()} |
    {:request_failed, term()}

  @doc """
  Generate a description of an image.
  
  ## Arguments
    * `image_path` - Path to the image file
    * `opts` - Options (e.g., `:max_tokens`)
  
  ## Returns
    * `{:ok, result}` - Result with description, model info, token usage, cost
    * `{:error, reason}` - Error details
  """
  @callback describe(image_path :: String.t(), opts :: keyword()) ::
    {:ok, vision_result()} | {:error, vision_error()}

  @doc """
  Extract text from an image (OCR).
  
  ## Arguments
    * `image_path` - Path to the image file
    * `opts` - Options (e.g., `:max_tokens`)
  
  ## Returns
    * `{:ok, result}` - Result with extracted text, model info, token usage, cost
    * `{:error, reason}` - Error details
  """
  @callback extract_text(image_path :: String.t(), opts :: keyword()) ::
    {:ok, vision_result()} | {:error, vision_error()}

  @doc """
  Estimate cost based on token usage.
  
  ## Arguments
    * `input_tokens` - Number of input tokens
    * `output_tokens` - Number of output tokens
  
  ## Returns
    * Cost in cents
  """
  @callback estimate_cost(input_tokens :: integer() | nil, output_tokens :: integer() | nil) :: integer()
end
