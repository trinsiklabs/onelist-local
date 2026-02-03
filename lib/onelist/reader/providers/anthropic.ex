defmodule Onelist.Reader.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude API for Reader Agent operations.

  Uses Claude for:
  - Atomic memory extraction
  - Reference resolution (pronouns, temporal expressions)
  - Tag suggestion
  - Summary generation

  ## Cost
  Claude 3.5 Haiku: ~$0.25/1M input tokens, ~$1.25/1M output tokens
  Claude 3.5 Sonnet: ~$3/1M input tokens, ~$15/1M output tokens
  """

  @behaviour Onelist.Reader.Behaviours.LLMProviderBehaviour

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  # Fast and cheap for extraction
  @model "claude-3-haiku-20240307"
  @timeout_ms 60_000
  @api_version "2023-06-01"

  @doc """
  Extract atomic memories from text content.
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

    Return ONLY a JSON array of memory objects. If no meaningful memories can be extracted, return an empty array [].

    Text to analyze:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_memories_result()
  end

  @doc """
  Suggest tags for content based on analysis.
  """
  def suggest_tags(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 500)
    max_suggestions = Keyword.get(opts, :max_suggestions, 5)
    existing_tags = Keyword.get(opts, :existing_tags, [])

    existing_tags_text =
      if existing_tags != [] do
        "\n\nExisting tags in the system (prefer reusing these when appropriate):\n#{Enum.join(existing_tags, ", ")}"
      else
        ""
      end

    prompt = """
    Analyze the following text and suggest up to #{max_suggestions} tags that would help categorize and find this content later.
    #{existing_tags_text}

    For each tag suggestion, provide:
    1. tag: The tag name (lowercase, use hyphens for multi-word tags)
    2. confidence: How appropriate this tag is (0.0-1.0)
    3. reason: Brief explanation of why this tag fits

    Return ONLY a JSON array of tag suggestion objects.

    Text to analyze:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_tags_result()
  end

  @doc """
  Generate a concise summary of the content.
  """
  def generate_summary(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 300)
    max_length = Keyword.get(opts, :max_length, 200)

    prompt = """
    Summarize the following text in #{max_length} characters or less. 
    Focus on the key information, main points, or memorable details.
    Return only the summary text, no JSON wrapper.

    Text to summarize:
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

  @doc """
  Resolve references in text (pronouns, temporal expressions, etc).
  """
  def resolve_references(text, opts \\ []) do
    api_key = get_api_key()
    max_tokens = Keyword.get(opts, :max_tokens, 1500)
    reference_date = Keyword.get(opts, :reference_date, Date.utc_today())
    context = Keyword.get(opts, :context, %{})

    context_text =
      if context != %{} do
        "\n\nContext from earlier in the document or related entries:\n#{Jason.encode!(context)}"
      else
        ""
      end

    prompt = """
    Resolve all references in the following text to make it self-contained.
    #{context_text}

    Reference date: #{Date.to_iso8601(reference_date)}

    Tasks:
    1. Replace pronouns (he, she, it, they, etc.) with the specific names/entities they refer to
    2. Resolve relative time expressions ("yesterday", "next week", "in 3 days") to specific dates
    3. Resolve demonstratives ("this project", "that meeting") to specific names when possible
    4. Keep the text natural and readable

    Return ONLY a JSON object with:
    - resolved_text: The text with all references resolved
    - resolutions: Array of {original, resolved, type} objects showing what was changed

    Text to resolve:
    #{text}
    """

    call_api(prompt, api_key, max_tokens)
    |> process_resolution_result()
  end

  # Private functions

  defp call_api(prompt, api_key, max_tokens) do
    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @api_version}
    ]

    body =
      Jason.encode!(%{
        model: @model,
        max_tokens: max_tokens,
        messages: [
          %{role: "user", content: prompt}
        ]
      })

    case Req.post(@api_url, body: body, headers: headers, receive_timeout: @timeout_ms) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 429, body: body}} ->
        Logger.warning("Anthropic rate limited: #{inspect(body)}")
        {:error, {:rate_limited, get_in(body, ["error", "message"]) || "Rate limited"}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Anthropic API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, get_in(body, ["error", "message"]) || body}}

      {:error, reason} ->
        Logger.error("Anthropic request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp process_memories_result({:ok, response}) do
    content = get_in(response, ["content", Access.at(0), "text"])
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
           input_tokens: usage["input_tokens"],
           output_tokens: usage["output_tokens"],
           cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
         }}

      {:error, reason} ->
        Logger.error("Failed to parse memories response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp process_memories_result(error), do: error

  defp process_tags_result({:ok, response}) do
    content = get_in(response, ["content", Access.at(0), "text"])
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
           input_tokens: usage["input_tokens"],
           output_tokens: usage["output_tokens"],
           cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
         }}

      {:error, reason} ->
        Logger.error("Failed to parse tags response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp process_tags_result(error), do: error

  defp process_summary_result({:ok, response}) do
    content = get_in(response, ["content", Access.at(0), "text"])
    usage = response["usage"] || %{}

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
       input_tokens: usage["input_tokens"],
       output_tokens: usage["output_tokens"],
       cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
     }}
  end

  defp process_summary_result(error), do: error

  defp process_relationship_result({:ok, response}) do
    content = get_in(response, ["content", Access.at(0), "text"])
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
       input_tokens: usage["input_tokens"],
       output_tokens: usage["output_tokens"],
       cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
     }}
  end

  defp process_relationship_result(error), do: error

  defp process_resolution_result({:ok, response}) do
    content = get_in(response, ["content", Access.at(0), "text"])
    usage = response["usage"] || %{}

    case parse_json_response(content) do
      {:ok, data} when is_map(data) ->
        {:ok,
         %{
           resolved_text: data["resolved_text"] || content,
           resolutions: data["resolutions"] || [],
           model: @model,
           input_tokens: usage["input_tokens"],
           output_tokens: usage["output_tokens"],
           cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
         }}

      {:ok, _} ->
        {:ok,
         %{
           resolved_text: content,
           resolutions: [],
           model: @model,
           input_tokens: usage["input_tokens"],
           output_tokens: usage["output_tokens"],
           cost_cents: estimate_cost(usage["input_tokens"], usage["output_tokens"])
         }}

      {:error, reason} ->
        Logger.error("Failed to parse resolution response: #{inspect(reason)}")
        {:error, {:parse_error, reason}}
    end
  end

  defp process_resolution_result(error), do: error

  defp parse_json_response(nil), do: {:error, :empty_response}

  defp parse_json_response(content) when is_binary(content) do
    # Try to extract JSON from the response (Claude sometimes wraps in markdown)
    json_content =
      content
      |> String.trim()
      |> extract_json_block()

    case Jason.decode(json_content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp extract_json_block(content) do
    # Try to extract JSON from markdown code blocks
    case Regex.run(~r/```(?:json)?\s*([\s\S]*?)```/m, content) do
      [_, json] -> String.trim(json)
      _ -> content
    end
  end

  defp normalize_memories(memories) when is_list(memories) do
    Enum.map(memories, fn memory ->
      %{
        content: memory["content"] || "",
        memory_type: normalize_memory_type(memory["memory_type"]),
        confidence: normalize_confidence(memory["confidence"]),
        entities: normalize_entities(memory["entities"]),
        temporal_expression: memory["temporal_expression"],
        resolved_time: memory["resolved_time"]
      }
    end)
    |> Enum.filter(fn m -> m.content != "" end)
  end

  defp normalize_memories(_), do: []

  defp normalize_memory_type(type) when type in ~w(fact preference event observation decision),
    do: type

  defp normalize_memory_type(_), do: "fact"

  defp normalize_confidence(conf) when is_number(conf), do: max(0.0, min(1.0, conf))
  defp normalize_confidence(_), do: 0.5

  defp normalize_entities(nil), do: %{people: [], places: [], organizations: []}

  defp normalize_entities(entities) when is_map(entities) do
    %{
      people: List.wrap(entities["people"] || []),
      places: List.wrap(entities["places"] || []),
      organizations: List.wrap(entities["organizations"] || [])
    }
  end

  defp normalize_entities(_), do: %{people: [], places: [], organizations: []}

  defp normalize_tag_suggestions(tags) when is_list(tags) do
    Enum.map(tags, fn tag ->
      %{
        tag: normalize_tag_name(tag["tag"] || tag["name"] || ""),
        confidence: normalize_confidence(tag["confidence"]),
        reason: tag["reason"] || ""
      }
    end)
    |> Enum.filter(fn t -> t.tag != "" end)
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

  # Claude 3.5 Haiku pricing (per 1M tokens)
  @input_cost_per_million 0.25
  @output_cost_per_million 1.25

  defp estimate_cost(input_tokens, output_tokens) do
    input = (input_tokens || 0) / 1_000_000 * @input_cost_per_million
    output = (output_tokens || 0) / 1_000_000 * @output_cost_per_million
    # Return cents
    Float.round((input + output) * 100, 4)
  end

  defp get_api_key do
    case Application.get_env(:onelist, :anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY") do
      nil ->
        raise """
        Anthropic API key not configured.

        Set the ANTHROPIC_API_KEY environment variable or configure it in your application:

            config :onelist, :anthropic_api_key, "sk-ant-..."

        """

      key ->
        key
    end
  end
end
