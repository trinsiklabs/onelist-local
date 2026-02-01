defmodule Onelist.Reader do
  @moduledoc """
  The Reader context for atomic memory extraction and tag suggestion.

  The Reader Agent transforms raw entry content into structured, searchable knowledge by:
  - Extracting atomic memories (facts, preferences, events, observations, decisions)
  - Resolving references (pronouns → names, "yesterday" → dates)
  - Suggesting tags based on content analysis
  - Managing memory relationships (supersedes/refines)

  ## Architecture

  The Reader Agent follows the minimal new tables approach:
  - `memories` table for atomic memories with vectors
  - `search_configs` extended with reader settings
  - `representations` reused for tag suggestions (type "tag_suggestion")

  ## Key Features

  - Atomic memory extraction with entity recognition
  - Temporal expression resolution
  - Tag suggestions with confidence scores
  - Cost tracking per operation
  """

  import Ecto.Query, warn: false
  alias Onelist.Repo
  alias Onelist.Reader.Memory
  alias Onelist.Searcher.SearchConfig

  require Logger

  # ============================================
  # PROCESSING OPERATIONS
  # ============================================

  @doc """
  Enqueue an entry for Reader processing.

  ## Options
    * `:priority` - Job priority (default: 0, higher = processed first)
    * `:skip_tags` - Skip tag suggestion (default: false)
    * `:skip_memories` - Skip memory extraction (default: false)
  """
  def enqueue_processing(entry_id, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0)
    skip_tags = Keyword.get(opts, :skip_tags, false)
    skip_memories = Keyword.get(opts, :skip_memories, false)

    %{
      entry_id: entry_id,
      priority: priority,
      skip_tags: skip_tags,
      skip_memories: skip_memories
    }
    |> Onelist.Reader.Workers.ProcessEntryWorker.new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Process an entry synchronously (for testing or immediate processing).

  This is the synchronous version of the worker's job.
  """
  def process_entry(entry_id, opts \\ []) do
    job = %Oban.Job{
      args: %{
        "entry_id" => entry_id,
        "skip_tags" => Keyword.get(opts, :skip_tags, false),
        "skip_memories" => Keyword.get(opts, :skip_memories, false)
      }
    }

    Onelist.Reader.Workers.ProcessEntryWorker.perform(job)
  end

  # ============================================
  # MEMORY OPERATIONS
  # ============================================

  @doc """
  Get all memories for an entry.

  ## Options
    * `:memory_type` - Filter by memory type
    * `:min_confidence` - Minimum confidence threshold
  """
  def get_memories_for_entry(entry_id, opts \\ []) do
    Memory
    |> where([m], m.entry_id == ^entry_id)
    |> apply_memory_filters(opts)
    |> order_by([m], asc: m.chunk_index, asc: m.inserted_at)
    |> Repo.all()
  end

  @doc """
  Get current (non-superseded) memories for a user.

  ## Options
    * `:memory_type` - Filter by memory type
    * `:min_confidence` - Minimum confidence threshold
    * `:limit` - Maximum number of memories (default: 100)
  """
  def get_current_memories(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Memory
    |> where([m], m.user_id == ^user_id and is_nil(m.valid_until))
    |> apply_memory_filters(opts)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Get a memory by ID.
  """
  def get_memory(id) do
    Repo.get(Memory, id)
  end

  @doc """
  Create a new memory.
  """
  def create_memory(attrs) do
    %Memory{}
    |> Memory.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a memory.
  """
  def update_memory(%Memory{} = memory, attrs) do
    memory
    |> Memory.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a memory.
  """
  def delete_memory(%Memory{} = memory) do
    Repo.delete(memory)
  end

  @doc """
  Mark a memory as superseded.

  Sets valid_until to now and optionally records what superseded it.
  """
  def supersede_memory(%Memory{} = memory, superseded_by_id \\ nil) do
    memory
    |> Memory.mark_superseded(superseded_by_id)
    |> Repo.update()
  end

  @doc """
  Search memories by vector similarity.

  ## Options
    * `:limit` - Maximum results (default: 10)
    * `:min_similarity` - Minimum similarity threshold (default: 0.7)
  """
  def search_memories(user_id, query_vector, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    min_similarity = Keyword.get(opts, :min_similarity, 0.7)

    # Convert to pgvector if needed
    vector =
      case query_vector do
        %Pgvector{} -> query_vector
        list when is_list(list) -> Pgvector.new(list)
      end

    Memory
    |> where([m], m.user_id == ^user_id and is_nil(m.valid_until))
    |> where([m], not is_nil(m.embedding))
    |> order_by([m], fragment("embedding <=> ?", ^vector))
    |> limit(^limit)
    |> select([m], %{memory: m, similarity: fragment("1 - (embedding <=> ?)", ^vector)})
    |> Repo.all()
    |> Enum.filter(fn %{similarity: sim} -> sim >= min_similarity end)
  end

  defp apply_memory_filters(query, opts) do
    query
    |> maybe_filter_memory_type(Keyword.get(opts, :memory_type))
    |> maybe_filter_confidence(Keyword.get(opts, :min_confidence))
  end

  defp maybe_filter_memory_type(query, nil), do: query

  defp maybe_filter_memory_type(query, type) do
    where(query, [m], m.memory_type == ^type)
  end

  defp maybe_filter_confidence(query, nil), do: query

  defp maybe_filter_confidence(query, confidence) do
    where(query, [m], m.confidence >= ^Decimal.new(to_string(confidence)))
  end

  # ============================================
  # TAG SUGGESTION OPERATIONS
  # ============================================

  @doc """
  Get pending tag suggestions for an entry.
  """
  def get_tag_suggestions(entry_id) do
    Onelist.Reader.Generators.TagSuggester.get_pending_suggestions(entry_id)
  end

  @doc """
  Accept a tag suggestion and apply it to the entry.
  """
  def accept_tag_suggestion(entry_id, tag_name) do
    Onelist.Reader.Generators.TagSuggester.accept_suggestion(entry_id, tag_name)
  end

  @doc """
  Reject a tag suggestion.
  """
  def reject_tag_suggestion(entry_id, tag_name) do
    Onelist.Reader.Generators.TagSuggester.reject_suggestion(entry_id, tag_name)
  end

  @doc """
  Accept all pending tag suggestions for an entry.
  """
  def accept_all_tag_suggestions(entry_id) do
    Onelist.Reader.Generators.TagSuggester.accept_all_suggestions(entry_id)
  end

  # ============================================
  # CONFIGURATION
  # ============================================

  @doc """
  Check if Reader auto-processing is enabled for a user on entry create.
  """
  def reader_enabled?(user_id) do
    case get_reader_config(user_id) do
      {:ok, config} -> config.auto_process_on_create
      _ -> default_config()[:auto_process_on_create]
    end
  end

  @doc """
  Check if Reader auto-processing is enabled for a user on entry update.
  """
  def reader_enabled_on_update?(user_id) do
    case get_reader_config(user_id) do
      {:ok, config} -> config.auto_process_on_update
      _ -> default_config()[:auto_process_on_update]
    end
  end

  @doc """
  Get Reader configuration for a user (via SearchConfig).
  """
  def get_reader_config(user_id) do
    case Repo.get_by(SearchConfig, user_id: user_id) do
      nil -> create_default_config(user_id)
      config -> {:ok, config}
    end
  end

  @doc """
  Update Reader configuration for a user.
  """
  def update_reader_config(user_id, attrs) do
    with {:ok, config} <- get_reader_config(user_id) do
      config
      |> SearchConfig.changeset(attrs)
      |> Repo.update()
    end
  end

  defp create_default_config(user_id) do
    %SearchConfig{}
    |> SearchConfig.changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  @doc """
  Returns default Reader settings.
  """
  def default_reader_settings do
    %{
      "extract_memories" => true,
      "resolve_references" => true,
      "detect_relationships" => true,
      "auto_summarize" => true,
      "auto_suggest_tags" => true,
      "max_tag_suggestions" => 5
    }
  end

  defp default_config do
    Application.get_env(:onelist, :reader, [])
    |> Keyword.merge(
      auto_process_on_create: true,
      auto_process_on_update: true,
      extraction_model: "gpt-4o-mini"
    )
  end

  # ============================================
  # COST TRACKING
  # ============================================

  @doc """
  Track Reader processing cost for a user.

  Uses the enrichment budget tracking in SearchConfig.
  """
  def track_cost(user_id, cost_cents) when cost_cents > 0 do
    with {:ok, config} <- get_reader_config(user_id) do
      current_spent = config.spent_enrichment_today_cents || 0

      config
      |> SearchConfig.changeset(%{spent_enrichment_today_cents: current_spent + cost_cents})
      |> Repo.update()
    end
  end

  def track_cost(_user_id, _cost_cents), do: {:ok, nil}

  @doc """
  Check if user has budget remaining for Reader processing.
  """
  def has_budget?(user_id) do
    case get_reader_config(user_id) do
      {:ok, config} ->
        budget = config.daily_enrichment_budget_cents
        spent = config.spent_enrichment_today_cents || 0

        is_nil(budget) or spent < budget

      _ ->
        true
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  @doc """
  Returns the default extraction model.
  """
  def default_model do
    Application.get_env(:onelist, :reader, [])
    |> Keyword.get(:extraction_model, "gpt-4o-mini")
  end

  @doc """
  Count memories for a user.
  """
  def count_memories(user_id, opts \\ []) do
    Memory
    |> where([m], m.user_id == ^user_id)
    |> apply_memory_filters(opts)
    |> Repo.aggregate(:count)
  end

  @doc """
  Count current (non-superseded) memories for a user.
  """
  def count_current_memories(user_id) do
    Memory
    |> where([m], m.user_id == ^user_id and is_nil(m.valid_until))
    |> Repo.aggregate(:count)
  end
end
