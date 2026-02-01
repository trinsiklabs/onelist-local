defmodule Onelist.AssetEnrichment.Extractors.ActionItemExtractor do
  @moduledoc """
  Extract action items from transcribed text using LLM.

  Identifies specific, actionable tasks from meeting transcripts
  and other text content.
  """

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-4o-mini"

  @system_prompt """
  You are an expert at identifying action items from meeting transcripts.
  Extract specific, actionable tasks with clear ownership when mentioned.
  Be conservative - only extract clear action items, not general discussion.
  Focus on commitments, tasks, and follow-ups.
  """

  @doc """
  Extract action items from transcript text.

  ## Arguments
    * `text` - The transcript text
    * `segments` - Optional list of segments with timestamps

  ## Returns
    * `{:ok, items}` - List of extracted action items
    * `{:error, reason}` - Error details
  """
  def extract(text, segments \\ [])

  def extract(nil, _segments), do: {:ok, []}
  def extract("", _segments), do: {:ok, []}

  def extract(text, segments) when is_binary(text) do
    # Skip very short texts
    if String.length(text) < 50 do
      {:ok, []}
    else
      do_extract(text, segments)
    end
  end

  defp do_extract(text, segments) do
    prompt = """
    Extract action items from this transcript. Only include clear, specific tasks.

    Transcript:
    #{text}

    Return JSON:
    {
      "action_items": [
        {
          "text": "Clear action description (imperative form, e.g., 'Review the budget report')",
          "owner": "Person name who should do this, or null if unclear",
          "deadline": "Mentioned deadline or timeframe, or null",
          "confidence": "high|medium|low",
          "source_quote": "Brief relevant quote from transcript (max 100 chars)"
        }
      ]
    }

    If no clear action items are found, return: {"action_items": []}
    """

    case call_llm(prompt) do
      {:ok, %{"action_items" => items}} when is_list(items) ->
        parsed =
          Enum.map(items, fn item ->
            {start_time, end_time} = find_timestamp(item["source_quote"], segments)

            %{
              text: item["text"],
              owner: item["owner"],
              deadline: item["deadline"],
              confidence: confidence_to_float(item["confidence"]),
              source_quote: item["source_quote"],
              start_time: start_time,
              end_time: end_time
            }
          end)

        {:ok, parsed}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp call_llm(prompt) do
    api_key = get_api_key()

    body =
      Jason.encode!(%{
        model: @model,
        messages: [
          %{role: "system", content: @system_prompt},
          %{role: "user", content: prompt}
        ],
        response_format: %{type: "json_object"},
        temperature: 0.1,
        max_tokens: 2000
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(@api_url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response}} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"])

        case Jason.decode(content) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, :invalid_json_response}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.error("LLM API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, get_in(body, ["error", "message"]) || body}}

      {:error, reason} ->
        Logger.error("LLM request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp find_timestamp(nil, _), do: {nil, nil}
  defp find_timestamp("", _), do: {nil, nil}

  defp find_timestamp(quote, segments) when is_list(segments) and length(segments) > 0 do
    quote_lower = String.downcase(quote || "")
    # Take first 30 chars for fuzzy matching
    quote_prefix = String.slice(quote_lower, 0..29)

    segment =
      Enum.find(segments, fn seg ->
        seg_text = String.downcase(seg["text"] || "")
        String.contains?(seg_text, quote_prefix)
      end)

    case segment do
      %{"start" => start, "end" => end_time} when is_number(start) and is_number(end_time) ->
        {trunc(start), trunc(end_time)}

      _ ->
        {nil, nil}
    end
  end

  defp find_timestamp(_, _), do: {nil, nil}

  defp confidence_to_float("high"), do: 0.9
  defp confidence_to_float("medium"), do: 0.7
  defp confidence_to_float("low"), do: 0.5
  defp confidence_to_float(_), do: 0.7

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "OpenAI API key not configured"
  end
end
