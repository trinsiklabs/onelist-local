defmodule Onelist.AssetEnrichment.Providers.OpenAIVision do
  @moduledoc """
  OpenAI Vision API for image description and OCR.

  Uses GPT-4o for:
  - Image description generation
  - Text extraction (OCR)

  ## Cost
  Costs vary based on image size and output tokens.
  Approximately $0.005-0.02 per image.
  """

  @behaviour Onelist.AssetEnrichment.VisionBehaviour

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-4o-mini"
  @timeout_ms 60_000

  @doc """
  Generate a description of an image.

  Returns a detailed description of the image contents including
  objects, people, scenes, text, and other relevant details.
  """
  @impl Onelist.AssetEnrichment.VisionBehaviour
  def describe(image_path, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 500)

    prompt = """
    Describe this image in detail. Include:
    - Main subject and objects
    - People (if any) and their actions
    - Setting/background
    - Any visible text
    - Colors, mood, or notable visual elements

    Be concise but comprehensive.
    """

    call_vision_api(image_path, prompt, api_key, max_tokens)
    |> process_description_result()
  end

  @doc """
  Extract text from an image (OCR).

  Returns any visible text in the image, preserving structure
  where possible.
  """
  @impl Onelist.AssetEnrichment.VisionBehaviour
  def extract_text(image_path, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    prompt = """
    Extract all visible text from this image.

    Rules:
    - Preserve the original structure (paragraphs, lists, etc.)
    - Include text from signs, labels, documents, screens, etc.
    - If no text is visible, respond with just: [no text found]
    - Do not describe the image, only extract text
    """

    call_vision_api(image_path, prompt, api_key, max_tokens)
    |> process_ocr_result()
  end

  defp call_vision_api(image_path, prompt, api_key, max_tokens) do
    unless File.exists?(image_path) do
      {:error, {:file_not_found, image_path}}
    else
      image_data = encode_image(image_path)

      body =
        Jason.encode!(%{
          model: @model,
          messages: [
            %{
              role: "user",
              content: [
                %{type: "text", text: prompt},
                %{
                  type: "image_url",
                  image_url: %{
                    url: "data:#{get_mime_type(image_path)};base64,#{image_data}",
                    detail: "auto"
                  }
                }
              ]
            }
          ],
          max_tokens: max_tokens
        })

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      case Req.post(@api_url, body: body, headers: headers, receive_timeout: @timeout_ms) do
        {:ok, %{status: 200, body: response}} ->
          {:ok, response}

        {:ok, %{status: status, body: body}} ->
          Logger.error("Vision API error: #{status} - #{inspect(body)}")
          {:error, {:api_error, status, get_in(body, ["error", "message"]) || body}}

        {:error, reason} ->
          Logger.error("Vision request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  defp process_description_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    {:ok,
     %{
       description: content,
       model: @model,
       input_tokens: usage["prompt_tokens"],
       output_tokens: usage["completion_tokens"],
       cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
     }}
  end

  defp process_description_result(error), do: error

  defp process_ocr_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    # Clean up the response
    text =
      if content == "[no text found]" do
        ""
      else
        String.trim(content || "")
      end

    {:ok,
     %{
       text: text,
       model: @model,
       input_tokens: usage["prompt_tokens"],
       output_tokens: usage["completion_tokens"],
       cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
     }}
  end

  defp process_ocr_result(error), do: error

  defp encode_image(path) do
    path
    |> File.read!()
    |> Base.encode64()
  end

  defp get_mime_type(path) do
    case Path.extname(path) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "image/jpeg"
    end
  end

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "OpenAI API key not configured"
  end

  @doc """
  Estimate cost based on tokens.
  GPT-4o-mini: $0.15/1M input, $0.60/1M output
  """
  @impl Onelist.AssetEnrichment.VisionBehaviour
  def estimate_cost(input_tokens, output_tokens) do
    input_cost = (input_tokens || 0) * 0.00015 / 1000
    output_cost = (output_tokens || 0) * 0.0006 / 1000
    round((input_cost + output_cost) * 100)
  end
end
