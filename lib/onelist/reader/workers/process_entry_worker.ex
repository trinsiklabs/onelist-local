defmodule Onelist.Reader.Workers.ProcessEntryWorker do
  @moduledoc """
  Oban worker for processing entries through the Reader Agent.

  This worker:
  1. Gets entry with representations
  2. Extracts markdown/plaintext content
  3. Chunks content using existing Chunker
  4. Extracts atomic memories using LLM
  5. Detects relationships between new and existing memories
  6. Suggests tags
  7. Generates summaries (stored as "summary" representation)
  8. Triggers embeddings for new memories

  Triggered when entries are created or updated (if auto-process is enabled).

  ## Configuration

  The following settings in `reader_settings` control behavior:
  - `extract_memories` (default: true) - Extract atomic memories
  - `detect_relationships` (default: true) - Detect supersedes/refines relationships
  - `auto_suggest_tags` (default: true) - Suggest tags
  - `generate_summaries` (default: true) - Generate AI summaries
  - `summary_style` (default: "concise") - Summary style: "concise", "detailed", or "bullets"

  ## Job Args

  - `entry_id` (required) - The entry to process
  - `skip_memories` (default: false) - Skip memory extraction
  - `skip_relationships` (default: false) - Skip relationship detection
  - `skip_tags` (default: false) - Skip tag suggestions
  - `skip_summary` (default: false) - Skip summary generation
  """

  use Oban.Worker,
    queue: :reader,
    max_attempts: 3,
    priority: 1

  alias Onelist.{Repo, Entries, Tags}
  alias Onelist.Reader
  alias Onelist.Reader.Memory
  alias Onelist.Reader.Extractors.AtomicMemory
  alias Onelist.Reader.Generators.TagSuggester

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id} = args}) do
    _priority = Map.get(args, "priority", 0)
    skip_tags = Map.get(args, "skip_tags", false)
    skip_memories = Map.get(args, "skip_memories", false)
    skip_relationships = Map.get(args, "skip_relationships", false)
    skip_summary = Map.get(args, "skip_summary", false)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting Reader processing for entry #{entry_id}")

    result =
      with {:ok, entry} <- get_entry(entry_id),
           {:ok, text} <- extract_readable_text(entry),
           {:ok, config} <- Reader.get_reader_config(entry.user_id),
           {:ok, memory_result} <- maybe_extract_memories(entry, text, config, skip_memories),
           {:ok, relationship_result} <- maybe_detect_relationships(entry, config, skip_relationships or skip_memories),
           {:ok, tag_result} <- maybe_suggest_tags(entry, text, config, skip_tags),
           {:ok, summary_result} <- maybe_generate_summary(entry, text, config, skip_summary) do
        duration = System.monotonic_time(:millisecond) - start_time
        total_cost = (memory_result[:cost_cents] || 0) + (relationship_result[:cost_cents] || 0) + (tag_result[:cost_cents] || 0) + (summary_result[:cost_cents] || 0)

        Logger.info(
          "Successfully processed entry #{entry_id}: " <>
            "#{memory_result[:count] || 0} memories, " <>
            "#{relationship_result[:supersedes] || 0} supersedes, " <>
            "#{relationship_result[:refines] || 0} refines, " <>
            "#{tag_result[:count] || 0} tag suggestions, " <>
            "summary=#{summary_result[:generated] || false}, " <>
            "#{total_cost} cents, #{duration}ms"
        )

        # Track cost
        if total_cost > 0 do
          Reader.track_cost(entry.user_id, total_cost)
        end

        :ok
      end

    handle_result(result, entry_id)
  end

  defp get_entry(entry_id) do
    case Entries.get_entry(entry_id) do
      nil -> {:error, :entry_not_found}
      entry -> {:ok, Repo.preload(entry, [:representations, :user])}
    end
  end

  defp extract_readable_text(entry) do
    # Priority order for text extraction:
    # 1. markdown representation
    # 2. plaintext representation
    # 3. transcript representation
    # 4. title only

    text =
      cond do
        rep = find_representation(entry.representations, "markdown") ->
          rep.content

        rep = find_representation(entry.representations, "plaintext") ->
          rep.content

        rep = find_representation(entry.representations, "transcript") ->
          rep.content

        true ->
          entry.title
      end

    text = String.trim(text || "")

    if text == "" do
      {:error, :no_content}
    else
      {:ok, text}
    end
  end

  defp find_representation(representations, type) do
    Enum.find(representations, fn rep -> rep.type == type end)
  end

  defp maybe_extract_memories(entry, _text, _config, true = _skip) do
    Logger.debug("Skipping memory extraction for entry #{entry.id}")
    {:ok, %{count: 0, cost_cents: 0}}
  end

  defp maybe_extract_memories(entry, text, config, _skip) do
    settings = config.reader_settings || %{}

    if Map.get(settings, "extract_memories", true) do
      extract_and_store_memories(entry, text, config)
    else
      {:ok, %{count: 0, cost_cents: 0}}
    end
  end

  defp extract_and_store_memories(entry, text, _config) do
    {:ok, result} = AtomicMemory.extract(text, reference_date: Date.utc_today())

    # Log API usage
    Onelist.Usage.log_usage(%{
      provider: "anthropic",
      model: "claude-3-haiku-20240307",
      operation: "memory_extraction",
      input_tokens: 0,  # AtomicMemory aggregates, individual tokens not tracked yet
      output_tokens: 0,
      cost_cents: Decimal.new(to_string(result.total_cost_cents || 0)),
      user_id: entry.user_id,
      entry_id: entry.id,
      metadata: %{chunks_processed: result.chunks_processed || 0}
    })

    # Log any chunk errors but continue with successful memories
    if Enum.any?(result.errors || []) do
      Logger.warning("Some chunks failed during memory extraction for entry #{entry.id}: #{inspect(result.errors)}")
    end

    memories =
      result.memories
      |> Enum.filter(fn mem -> 
        # Filter out memories without content (handle both atom and string keys)
        content = mem[:content] || mem["content"]
        is_binary(content) && String.trim(content) != ""
      end)
      |> Enum.map(fn mem ->
        %{
          content: mem[:content] || mem["content"],
          memory_type: mem[:memory_type] || mem["memory_type"] || "fact",
          confidence: parse_confidence(mem[:confidence] || mem["confidence"]),
          entities: mem[:entities] || mem["entities"] || [],
          temporal_expression: mem[:temporal_expression] || mem["temporal_expression"],
          resolved_time: parse_datetime(mem[:resolved_time] || mem["resolved_time"]),
          source_text: mem[:source_text] || mem["source_text"],
          chunk_index: mem[:chunk_index] || mem["chunk_index"] || 0,
          entry_id: entry.id,
          user_id: entry.user_id
        }
      end)

    # Delete existing memories for this entry (re-processing)
    Memory
    |> where([m], m.entry_id == ^entry.id)
    |> Repo.delete_all()

    # Insert new memories
    now = DateTime.utc_now()

    memory_records =
      Enum.map(memories, fn mem ->
        mem
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} = Repo.insert_all(Memory, memory_records)

    # Queue embedding generation for memories
    if count > 0 do
      enqueue_memory_embeddings(entry.id)
    end

    {:ok, %{count: count, cost_cents: result.total_cost_cents}}
  end

  # ============================================
  # RELATIONSHIP DETECTION
  # ============================================

  defp maybe_detect_relationships(_entry, _config, true = _skip) do
    {:ok, %{supersedes: 0, refines: 0, cost_cents: 0}}
  end

  defp maybe_detect_relationships(entry, config, _skip) do
    settings = config.reader_settings || %{}

    if Map.get(settings, "detect_relationships", true) do
      detect_and_apply_relationships(entry)
    else
      {:ok, %{supersedes: 0, refines: 0, cost_cents: 0}}
    end
  end

  defp detect_and_apply_relationships(entry) do
    # Get newly created memories for this entry (they have embeddings queued but may not have them yet)
    new_memories = Reader.get_memories_for_entry(entry.id)

    if Enum.empty?(new_memories) do
      {:ok, %{supersedes: 0, refines: 0, cost_cents: 0}}
    else
      # Process each new memory
      results =
        Enum.map(new_memories, fn new_memory ->
          detect_relationships_for_memory(new_memory, entry.user_id)
        end)

      # Aggregate results
      total_supersedes = Enum.sum(Enum.map(results, fn r -> r.supersedes end))
      total_refines = Enum.sum(Enum.map(results, fn r -> r.refines end))
      total_cost = Enum.sum(Enum.map(results, fn r -> r.cost_cents end))

      {:ok, %{supersedes: total_supersedes, refines: total_refines, cost_cents: total_cost}}
    end
  end

  defp detect_relationships_for_memory(new_memory, user_id) do
    # Since new memories don't have embeddings yet, we need to generate one for search
    # We'll use the memory content to find similar existing memories
    case generate_query_embedding(new_memory.content) do
      {:ok, embedding} ->
        find_and_classify_relationships(new_memory, user_id, embedding)

      {:error, reason} ->
        Logger.warning("Failed to generate embedding for relationship detection: #{inspect(reason)}")
        %{supersedes: 0, refines: 0, cost_cents: 0}
    end
  end

  defp generate_query_embedding(text) do
    # Use the same embedding provider as EmbedMemoriesWorker
    embedding_provider().embed(text)
  end

  defp find_and_classify_relationships(new_memory, user_id, embedding) do
    # Find similar existing memories (excluding memories from the same entry)
    similar_memories =
      Reader.search_memories(user_id, embedding, limit: 5, min_similarity: 0.8)
      |> Enum.filter(fn %{memory: mem} ->
        mem.entry_id != new_memory.entry_id and is_nil(mem.valid_until)
      end)

    if Enum.empty?(similar_memories) do
      %{supersedes: 0, refines: 0, cost_cents: 0}
    else
      # Classify relationships with high-similarity matches
      classify_and_apply_relationships(new_memory, similar_memories)
    end
  end

  defp classify_and_apply_relationships(new_memory, similar_memories) do
    # Only process the top 3 most similar to limit API calls
    top_similar = Enum.take(similar_memories, 3)

    {supersedes_count, refines_count, total_cost} =
      Enum.reduce(top_similar, {0, 0, 0}, fn %{memory: old_memory, similarity: _sim}, {sup, ref, cost} ->
        case llm_provider().classify_relationship(new_memory.content, old_memory.content) do
          {:ok, result} ->
            case result.relationship do
              "supersedes" ->
                apply_supersedes_relationship(new_memory, old_memory)
                {sup + 1, ref, cost + result.cost_cents}

              "refines" ->
                apply_refines_relationship(new_memory, old_memory)
                {sup, ref + 1, cost + result.cost_cents}

              "unrelated" ->
                {sup, ref, cost + result.cost_cents}
            end

          {:error, reason} ->
            Logger.warning("Failed to classify relationship: #{inspect(reason)}")
            {sup, ref, cost}
        end
      end)

    %{supersedes: supersedes_count, refines: refines_count, cost_cents: total_cost}
  end

  defp apply_supersedes_relationship(new_memory, old_memory) do
    # Mark old memory as superseded
    Reader.supersede_memory(old_memory, new_memory.id)

    # Update new memory with supersedes_id
    Reader.update_memory(new_memory, %{supersedes_id: old_memory.id})

    Logger.debug("Memory #{new_memory.id} supersedes #{old_memory.id}")
  end

  defp apply_refines_relationship(new_memory, old_memory) do
    # Update new memory with refines_id
    Reader.update_memory(new_memory, %{refines_id: old_memory.id})

    Logger.debug("Memory #{new_memory.id} refines #{old_memory.id}")
  end

  defp maybe_suggest_tags(entry, _text, _config, true = _skip) do
    Logger.debug("Skipping tag suggestions for entry #{entry.id}")
    {:ok, %{count: 0, cost_cents: 0}}
  end

  defp maybe_suggest_tags(entry, text, config, _skip) do
    settings = config.reader_settings || %{}

    if Map.get(settings, "auto_suggest_tags", true) do
      suggest_and_store_tags(entry, text, config)
    else
      {:ok, %{count: 0, cost_cents: 0}}
    end
  end

  defp suggest_and_store_tags(entry, text, config) do
    settings = config.reader_settings || %{}
    max_suggestions = Map.get(settings, "max_tag_suggestions", 5)

    # Get existing tags for this user to prefer
    existing_tags = Tags.list_user_tags(entry.user) |> Enum.map(& &1.name)

    case TagSuggester.suggest_and_store(entry.id, text,
           max_suggestions: max_suggestions,
           existing_tags: existing_tags,
           user_id: entry.user_id
         ) do
      {:ok, result} ->
        {:ok, %{count: length(result.suggestions), cost_cents: result.cost_cents}}

      {:error, reason} ->
        Logger.error("Failed to suggest tags for entry #{entry.id}: #{inspect(reason)}")
        {:ok, %{count: 0, cost_cents: 0}}
    end
  end

  defp maybe_generate_summary(entry, _text, _config, true = _skip) do
    Logger.debug("Skipping summary generation for entry #{entry.id}")
    {:ok, %{generated: false, cost_cents: 0}}
  end

  defp maybe_generate_summary(entry, text, config, _skip) do
    settings = config.reader_settings || %{}

    if Map.get(settings, "generate_summaries", true) do
      generate_and_store_summary(entry, text, config)
    else
      {:ok, %{generated: false, cost_cents: 0}}
    end
  end

  defp generate_and_store_summary(entry, text, config) do
    settings = config.reader_settings || %{}
    style = Map.get(settings, "summary_style", "concise")

    case llm_provider().generate_summary(text, style: style) do
      {:ok, result} ->
        # Store or update the summary as a representation
        case upsert_summary_representation(entry, result.summary) do
          {:ok, _representation} ->
            {:ok, %{generated: true, cost_cents: result.cost_cents}}

          {:error, reason} ->
            Logger.error("Failed to store summary for entry #{entry.id}: #{inspect(reason)}")
            {:ok, %{generated: false, cost_cents: result.cost_cents}}
        end

      {:error, reason} ->
        Logger.error("Failed to generate summary for entry #{entry.id}: #{inspect(reason)}")
        {:ok, %{generated: false, cost_cents: 0}}
    end
  end

  defp upsert_summary_representation(entry, summary_text) do
    # Find existing summary representation or create new one
    existing =
      entry.representations
      |> Enum.find(fn rep -> rep.type == "summary" end)

    if existing do
      Entries.update_representation(existing, %{content: summary_text})
    else
      Entries.add_representation(entry, %{type: "summary", content: summary_text})
    end
  end

  defp enqueue_memory_embeddings(entry_id) do
    # Queue embedding generation for the memories
    # This reuses the existing embedding infrastructure
    %{entry_id: entry_id, type: "memories"}
    |> Onelist.Reader.Workers.EmbedMemoriesWorker.new()
    |> Oban.insert()
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp parse_confidence(nil), do: Decimal.new("0.5")
  defp parse_confidence(""), do: Decimal.new("0.5")
  defp parse_confidence(val) when is_number(val), do: Decimal.new(to_string(val))
  defp parse_confidence(val) when is_binary(val) do
    case Decimal.parse(val) do
      {decimal, ""} -> decimal
      _ -> Decimal.new("0.5")
    end
  end
  defp parse_confidence(_), do: Decimal.new("0.5")

  defp handle_result(:ok, _entry_id), do: :ok

  defp handle_result({:error, :entry_not_found}, entry_id) do
    Logger.warning("Entry #{entry_id} not found, skipping processing")
    :ok
  end

  defp handle_result({:error, :no_content}, entry_id) do
    Logger.debug("Entry #{entry_id} has no readable content")
    :ok
  end

  defp handle_result({:error, {:rate_limited, _}}, entry_id) do
    Logger.warning("Rate limited while processing entry #{entry_id}, will retry")
    {:error, "Rate limited"}
  end

  defp handle_result({:error, reason}, entry_id) do
    Logger.error("Failed to process entry #{entry_id}: #{inspect(reason)}")
    {:error, reason}
  end

  # Returns the configured LLM provider module
  defp llm_provider do
    Application.get_env(:onelist, :reader_llm_provider, Onelist.Reader.Providers.Anthropic)
  end

  # Returns the configured embedding provider module
  defp embedding_provider do
    Application.get_env(:onelist, :reader_embedding_provider, Onelist.Searcher.Providers.OpenAI)
  end
end
