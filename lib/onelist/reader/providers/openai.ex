defmodule Onelist.Reader.Providers.OpenAI do
  @moduledoc """
  OpenAI Chat API for Reader Agent operations.

  Uses GPT-4o-mini for:
  - Atomic memory extraction
  - Reference resolution (pronouns, temporal expressions)
  - Tag suggestion
  - Summary generation

  ## Cost
  GPT-4o-mini: ~$0.15/1M input tokens, ~$0.60/1M output tokens
  """

  @behaviour Onelist.Reader.Behaviours.LLMProviderBehaviour

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @model "gpt-4o-mini"
  @timeout_ms 60_000

  @doc """
  Extract atomic memories from text content.

  Returns a list of extracted memories with:
  - content: The atomic memory statement
  - memory_type: fact, preference, event, observation, or decision
  - confidence: 0.0 to 1.0
  - entities: Extracted people, places, organizations
  - temporal_expression: Original temporal reference if any
  - resolved_time: ISO8601 if temporal expression was resolved
  """
  def extract_memories(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 2000)
    reference_date = Keyword.get(opts, :reference_date, Date.utc_today())

    prompt = """
    Extract atomic memories from the following text. Each memory should be a self-contained fact that could be retrieved later.

    Reference date for temporal resolution: #{Date.to_iso8601(reference_date)}

    For each memory, provide:
    1. content: The complete, self-contained statement (resolve all pronouns to specific names/entities)
    2. memory_type: One of "fact", "preference", "event", "observation", "decision"
    3. confidence: How confident you are in this extraction (0.0-1.0)
    4. entities: Object with keys "people", "places", "organizations" (arrays of strings)
    5. temporal_expression: Original time reference if any (e.g., "yesterday", "next week")
    6. resolved_time: ISO8601 datetime if you can resolve the temporal expression

    Rules:
    - Make each memory self-contained (no pronouns like "he", "she", "it", "they")
    - Resolve relative times ("yesterday" → actual date based on reference date)
    - Extract distinct, non-overlapping facts
    - Prefer specific over vague statements
    - Skip trivial or unimportant details

    Return a JSON array of memory objects. If no meaningful memories can be extracted, return an empty array [].

    Text to analyze:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_memories_result()
  end

  @doc """
  Suggest tags for content based on analysis.

  Returns a list of tag suggestions with:
  - tag: The suggested tag name
  - confidence: 0.0 to 1.0
  - reason: Why this tag is suggested
  """
  def suggest_tags(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 500)
    max_suggestions = Keyword.get(opts, :max_suggestions, 5)
    existing_tags = Keyword.get(opts, :existing_tags, [])

    existing_tags_text =
      if Enum.any?(existing_tags) do
        "Existing tags in the system (prefer these if relevant): #{Enum.join(existing_tags, ", ")}"
      else
        "No existing tags to reference."
      end

    prompt = """
    Suggest up to #{max_suggestions} tags for the following content.

    #{existing_tags_text}

    For each tag suggestion, provide:
    1. tag: The tag name (lowercase, use hyphens for multi-word tags)
    2. confidence: How confident you are (0.0-1.0)
    3. reason: Brief explanation of why this tag fits

    Rules:
    - Tags should be concise (1-3 words)
    - Use lowercase with hyphens (e.g., "machine-learning")
    - Prefer existing tags when they fit
    - Focus on topics, themes, and categories
    - Avoid overly generic tags like "content" or "information"

    Return a JSON array of tag objects. If no good tags can be suggested, return an empty array [].

    Content:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_tags_result()
  end

  @doc """
  Generate a concise summary of content.

  Returns summary text.
  """
  def generate_summary(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 500)
    style = Keyword.get(opts, :style, "concise")

    style_instruction =
      case style do
        "concise" -> "Write a 1-2 sentence summary capturing the main point."
        "detailed" -> "Write a comprehensive summary covering all key points in 3-5 sentences."
        "bullets" -> "Summarize as 3-5 bullet points."
        _ -> "Write a brief summary."
      end

    prompt = """
    #{style_instruction}

    Content:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_summary_result()
  end

  @doc """
  Classify the relationship between two memories.

  Returns one of: "supersedes", "refines", "unrelated"
  """
  def classify_relationship(memory1, memory2, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 100)

    prompt = """
    Classify the relationship between these two memories:

    Memory 1 (newer): #{memory1}
    Memory 2 (older): #{memory2}

    Classify as one of:
    - "supersedes": Memory 1 replaces Memory 2 (newer information makes older obsolete)
    - "refines": Memory 1 adds detail to Memory 2 (elaborates without replacing)
    - "unrelated": No meaningful relationship

    Return only the classification word, nothing else.
    """

    call_api(prompt, api_key, max_tokens)
    |> process_relationship_result()
  end

  defp call_api(prompt, api_key, max_tokens) do
    body =
      Jason.encode!(%{
        model: @model,
        messages: [
          %{
            role: "system",
            content:
              "You are an expert at extracting structured information from text. Always respond with valid JSON when asked for structured output."
          },
          %{
            role: "user",
            content: prompt
          }
        ],
        max_tokens: max_tokens,
        temperature: 0.3,
        response_format: %{type: "json_object"}
      })

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(@api_url, body: body, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: 429, body: body}} ->
        Logger.warning("OpenAI rate limited: #{inspect(body)}")
        {:error, {:rate_limited, get_in(body, ["error", "message"]) || "Rate limited"}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("OpenAI API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, get_in(body, ["error", "message"]) || body}}

      {:error, reason} ->
        Logger.error("OpenAI request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp process_memories_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    case parse_json_response(content) do
      {:ok, data} ->
        memories =
          cond do
            is_list(data) -> data
            is_map(data) && Map.has_key?(data, "memories") -> data["memories"]
            is_map(data) -> [data]
            true -> []
          end

        {:ok,
         %{
           memories: normalize_memories(memories),
           model: @model,
           input_tokens: usage["prompt_tokens"],
           output_tokens: usage["completion_tokens"],
           cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
         }}

      {:error, reason} ->
        Logger.error("Failed to parse memories response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp process_memories_result(error), do: error

  defp process_tags_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    case parse_json_response(content) do
      {:ok, data} ->
        tags =
          cond do
            is_list(data) -> data
            is_map(data) && Map.has_key?(data, "tags") -> data["tags"]
            is_map(data) && Map.has_key?(data, "suggestions") -> data["suggestions"]
            true -> []
          end

        {:ok,
         %{
           suggestions: normalize_tag_suggestions(tags),
           model: @model,
           input_tokens: usage["prompt_tokens"],
           output_tokens: usage["completion_tokens"],
           cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
         }}

      {:error, reason} ->
        Logger.error("Failed to parse tags response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp process_tags_result(error), do: error

  defp process_summary_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    # Try to extract summary from JSON if it was returned as JSON
    summary =
      case parse_json_response(content) do
        {:ok, data} when is_map(data) ->
          data["summary"] || data["text"] || content

        _ ->
          String.trim(content || "")
      end

    {:ok,
     %{
       summary: summary,
       model: @model,
       input_tokens: usage["prompt_tokens"],
       output_tokens: usage["completion_tokens"],
       cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
     }}
  end

  defp process_summary_result(error), do: error

  defp process_relationship_result({:ok, response}) do
    content = get_in(response, ["choices", Access.at(0), "message", "content"])
    usage = response["usage"] || %{}

    relationship =
      content
      |> String.trim()
      |> String.downcase()
      |> case do
        r when r in ["supersedes", "refines", "unrelated"] -> r
        _ -> "unrelated"
      end

    {:ok,
     %{
       relationship: relationship,
       model: @model,
       input_tokens: usage["prompt_tokens"],
       output_tokens: usage["completion_tokens"],
       cost_cents: estimate_cost(usage["prompt_tokens"], usage["completion_tokens"])
     }}
  end

  defp process_relationship_result(error), do: error

  defp parse_json_response(content) when is_binary(content) do
    content
    |> String.trim()
    |> Jason.decode()
  end

  defp parse_json_response(_), do: {:error, :invalid_content}

  defp normalize_memories(memories) when is_list(memories) do
    Enum.map(memories, fn mem ->
      %{
        "content" => mem["content"] || "",
        "memory_type" => normalize_memory_type(mem["memory_type"]),
        "confidence" => normalize_confidence(mem["confidence"]),
        "entities" => normalize_entities(mem["entities"]),
        "temporal_expression" => mem["temporal_expression"],
        "resolved_time" => mem["resolved_time"]
      }
    end)
    |> Enum.filter(fn mem -> String.length(mem["content"]) > 0 end)
  end

  defp normalize_memories(_), do: []

  defp normalize_memory_type(type) when type in ["fact", "preference", "event", "observation", "decision"],
    do: type

  defp normalize_memory_type(_), do: "fact"

  defp normalize_confidence(conf) when is_number(conf) and conf >= 0 and conf <= 1, do: conf
  defp normalize_confidence(conf) when is_number(conf) and conf > 1, do: 1.0
  defp normalize_confidence(_), do: 0.8

  defp normalize_entities(entities) when is_map(entities) do
    %{
      "people" => List.wrap(entities["people"]),
      "places" => List.wrap(entities["places"]),
      "organizations" => List.wrap(entities["organizations"])
    }
  end

  defp normalize_entities(_), do: %{"people" => [], "places" => [], "organizations" => []}

  defp normalize_tag_suggestions(tags) when is_list(tags) do
    Enum.map(tags, fn tag ->
      %{
        "tag" => normalize_tag_name(tag["tag"]),
        "confidence" => normalize_confidence(tag["confidence"]),
        "reason" => tag["reason"] || ""
      }
    end)
    |> Enum.filter(fn tag -> String.length(tag["tag"]) > 0 end)
  end

  defp normalize_tag_suggestions(_), do: []

  defp normalize_tag_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  defp normalize_tag_name(_), do: ""

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "OpenAI API key not configured"
  end

  @doc """
  Estimate cost in cents based on token usage.
  GPT-4o-mini: $0.15/1M input, $0.60/1M output
  """
  def estimate_cost(input_tokens, output_tokens) do
    input_cost = (input_tokens || 0) * 0.00015 / 1000
    output_cost = (output_tokens || 0) * 0.0006 / 1000
    round((input_cost + output_cost) * 100)
  end

  @doc """
  Returns the model name used by this provider.
  """
  def model_name, do: @model
end
