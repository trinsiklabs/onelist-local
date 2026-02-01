defmodule Onelist.Reader.Extractors.AtomicMemory do
  @moduledoc """
  Extracts atomic memories from text content.

  Atomic memories are self-contained pieces of knowledge that:
  - Have all references resolved (no pronouns)
  - Include temporal context when present
  - Are classified by type (fact, preference, event, observation, decision)
  - Include extracted entities (people, places, organizations)
  """

  alias Onelist.Searcher.Chunker

  require Logger

  @default_max_chunk_tokens 300
  @default_overlap_tokens 30

  @doc """
  Extract atomic memories from text content.

  ## Options
    * `:max_chunk_tokens` - Maximum tokens per chunk (default: 300)
    * `:overlap_tokens` - Token overlap between chunks (default: 30)
    * `:reference_date` - Date for resolving temporal expressions (default: today)

  Returns `{:ok, memories}` or `{:error, reason}`
  """
  def extract(text, opts \\ []) do
    max_chunk_tokens = Keyword.get(opts, :max_chunk_tokens, @default_max_chunk_tokens)
    overlap_tokens = Keyword.get(opts, :overlap_tokens, @default_overlap_tokens)
    reference_date = Keyword.get(opts, :reference_date, Date.utc_today())

    text = String.trim(text || "")

    if text == "" do
      {:ok, %{memories: [], total_cost_cents: 0, chunks_processed: 0}}
    else
      chunks =
        Chunker.chunk(text,
          max_tokens: max_chunk_tokens,
          overlap_tokens: overlap_tokens
        )

      extract_from_chunks(chunks, reference_date)
    end
  end

  @doc """
  Extract memories from pre-chunked content.

  Useful when chunks have already been generated for embedding.
  """
  def extract_from_chunks(chunks, reference_date \\ Date.utc_today())

  def extract_from_chunks([], _reference_date) do
    {:ok, %{memories: [], total_cost_cents: 0, chunks_processed: 0}}
  end

  def extract_from_chunks(chunks, reference_date) do
    results =
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        extract_from_chunk(chunk, index, reference_date)
      end)

    {memories, costs, errors} =
      Enum.reduce(results, {[], 0, []}, fn
        {:ok, %{memories: mems, cost_cents: cost}}, {all_mems, total_cost, errs} ->
          {all_mems ++ mems, total_cost + cost, errs}

        {:error, reason}, {all_mems, total_cost, errs} ->
          {all_mems, total_cost, [reason | errs]}
      end)

    if Enum.any?(errors) do
      Logger.warning("Some chunks failed to process: #{inspect(errors)}")
    end

    # Deduplicate memories that might overlap due to chunk overlap
    deduped_memories = deduplicate_memories(memories)

    {:ok,
     %{
       memories: deduped_memories,
       total_cost_cents: costs,
       chunks_processed: length(chunks),
       errors: errors
     }}
  end

  defp extract_from_chunk(chunk, chunk_index, reference_date) do
    text = if is_binary(chunk), do: chunk, else: chunk.text

    case llm_provider().extract_memories(text, reference_date: reference_date) do
      {:ok, result} ->
        memories =
          Enum.map(result.memories, fn mem ->
            mem
            |> Map.put(:chunk_index, chunk_index)
            |> Map.put(:source_text, String.slice(text, 0, 500))
          end)

        {:ok, %{memories: memories, cost_cents: result.cost_cents}}

      {:error, reason} ->
        {:error, {:chunk_failed, chunk_index, reason}}
    end
  end

  @doc """
  Deduplicate memories that have very similar content.

  Uses simple string similarity to detect duplicates that may arise
  from overlapping chunks.
  """
  def deduplicate_memories(memories) do
    memories
    |> Enum.reduce([], fn memory, acc ->
      if duplicate?(memory, acc) do
        acc
      else
        [memory | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp duplicate?(memory, existing) do
    Enum.any?(existing, fn existing_mem ->
      similar?(memory["content"], existing_mem["content"])
    end)
  end

  @doc """
  Check if two strings are similar enough to be considered duplicates.

  Uses Jaro-Winkler similarity with a threshold of 0.9.
  """
  def similar?(str1, str2) when is_binary(str1) and is_binary(str2) do
    # Normalize strings for comparison
    norm1 = normalize_for_comparison(str1)
    norm2 = normalize_for_comparison(str2)

    # If one is contained in the other, they're similar
    if String.contains?(norm1, norm2) or String.contains?(norm2, norm1) do
      true
    else
      # Use Jaro-Winkler similarity
      jaro_winkler_similarity(norm1, norm2) > 0.9
    end
  end

  def similar?(_, _), do: false

  defp normalize_for_comparison(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Simple Jaro-Winkler similarity implementation
  defp jaro_winkler_similarity(s1, s2) do
    if s1 == s2 do
      1.0
    else
      jaro = jaro_similarity(s1, s2)
      prefix_length = common_prefix_length(s1, s2, 4)
      jaro + prefix_length * 0.1 * (1 - jaro)
    end
  end

  defp jaro_similarity(s1, s2) do
    len1 = String.length(s1)
    len2 = String.length(s2)

    if len1 == 0 or len2 == 0 do
      0.0
    else
      match_distance = max(div(max(len1, len2), 2) - 1, 0)

      s1_chars = String.graphemes(s1)
      s2_chars = String.graphemes(s2)

      {matches, transpositions} = find_matches_and_transpositions(s1_chars, s2_chars, match_distance)

      if matches == 0 do
        0.0
      else
        (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3
      end
    end
  end

  defp find_matches_and_transpositions(s1_chars, s2_chars, match_distance) do
    len2 = length(s2_chars)
    s2_matched = List.duplicate(false, len2)

    {s1_matches, s2_matched} =
      s1_chars
      |> Enum.with_index()
      |> Enum.reduce({[], s2_matched}, fn {c1, i}, {matches, matched} ->
        start = max(0, i - match_distance)
        stop = min(i + match_distance + 1, len2)

        find_match(c1, s2_chars, start, stop, i, matches, matched)
      end)

    s2_matches =
      s2_chars
      |> Enum.with_index()
      |> Enum.filter(fn {_, i} -> Enum.at(s2_matched, i) end)
      |> Enum.map(fn {c, _} -> c end)

    transpositions =
      s1_matches
      |> Enum.zip(s2_matches)
      |> Enum.count(fn {a, b} -> a != b end)

    {length(s1_matches), transpositions}
  end

  defp find_match(c1, s2_chars, start, stop, _i, matches, matched) do
    case Enum.find_index(start..(stop - 1), fn j ->
           not Enum.at(matched, j) and Enum.at(s2_chars, j) == c1
         end) do
      nil ->
        {matches, matched}

      idx ->
        j = start + idx
        {matches ++ [c1], List.replace_at(matched, j, true)}
    end
  end

  defp common_prefix_length(s1, s2, max_length) do
    s1
    |> String.graphemes()
    |> Enum.zip(String.graphemes(s2))
    |> Enum.take(max_length)
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end

  @doc """
  Merge entities from multiple memories into a single entities map.
  """
  def merge_entities(memories) do
    Enum.reduce(memories, %{"people" => [], "places" => [], "organizations" => []}, fn mem, acc ->
      entities = mem["entities"] || %{}

      %{
        "people" => Enum.uniq(acc["people"] ++ List.wrap(entities["people"])),
        "places" => Enum.uniq(acc["places"] ++ List.wrap(entities["places"])),
        "organizations" => Enum.uniq(acc["organizations"] ++ List.wrap(entities["organizations"]))
      }
    end)
  end

  # Returns the configured LLM provider module
  defp llm_provider do
    Application.get_env(:onelist, :reader_llm_provider, Onelist.Reader.Providers.Anthropic)
  end
end
