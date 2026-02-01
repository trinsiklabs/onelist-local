defmodule Onelist.Searcher do
  @moduledoc """
  The Searcher context for embedding generation and semantic search.

  Provides functionality for:
  - Generating and storing vector embeddings for entries
  - Performing hybrid search (semantic + keyword)
  - Managing user search configurations
  - Tracking embedding job status
  """

  import Ecto.Query, warn: false
  alias Onelist.Repo
  alias Onelist.Searcher.{Embedding, SearchConfig, EmbeddingJob}

  require Logger

  # ============================================
  # EMBEDDING OPERATIONS
  # ============================================

  @doc """
  Enqueue an entry for embedding generation.
  Called automatically when entries are created/updated if auto-embed is enabled.

  ## Options
    * `:priority` - Job priority (default: 0, higher = processed first)
  """
  def enqueue_embedding(entry_id, opts \\ []) do
    priority = Keyword.get(opts, :priority, 0)

    %{entry_id: entry_id, priority: priority}
    |> Onelist.Searcher.Workers.EmbedEntryWorker.new(priority: priority)
    |> Oban.insert()
  end

  @doc """
  Enqueue multiple entries for batch embedding.
  """
  def enqueue_batch_embedding(entry_ids, opts \\ []) when is_list(entry_ids) do
    %{entry_ids: entry_ids}
    |> Onelist.Searcher.Workers.BatchEmbedWorker.new(Keyword.merge([queue: :embeddings_batch], opts))
    |> Oban.insert()
  end

  @doc """
  Get embeddings for an entry. Returns empty list if not yet embedded.

  ## Options
    * `:model_name` - Filter by model name (default: current default model)
  """
  def get_embeddings(entry_id, opts \\ []) do
    model_name = Keyword.get(opts, :model_name, default_model())

    Embedding
    |> where([e], e.entry_id == ^entry_id and e.model_name == ^model_name)
    |> order_by([e], e.chunk_index)
    |> Repo.all()
  end

  @doc """
  Get a single embedding by ID.
  """
  def get_embedding(id) do
    Repo.get(Embedding, id)
  end

  @doc """
  Check if entry has been embedded with current model.
  """
  def embedded?(entry_id) do
    Embedding
    |> where([e], e.entry_id == ^entry_id and e.model_name == ^default_model())
    |> Repo.exists?()
  end

  @doc """
  Delete all embeddings for an entry.
  """
  def delete_embeddings(entry_id) do
    {count, _} =
      Embedding
      |> where([e], e.entry_id == ^entry_id)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  Insert embeddings for an entry (batch insert).
  """
  def insert_embeddings(embeddings) when is_list(embeddings) do
    Repo.insert_all(Embedding, embeddings, on_conflict: :nothing)
  end

  # ============================================
  # SEARCH CONFIGURATION
  # ============================================

  @doc """
  Get or create search config for user.
  """
  def get_search_config(user_id) do
    case Repo.get_by(SearchConfig, user_id: user_id) do
      nil -> create_default_config(user_id)
      config -> {:ok, config}
    end
  end

  @doc """
  Get search config for user, raising if not found.
  """
  def get_search_config!(user_id) do
    case get_search_config(user_id) do
      {:ok, config} -> config
      {:error, reason} -> raise "Failed to get search config: #{inspect(reason)}"
    end
  end

  @doc """
  Update search configuration.
  """
  def update_search_config(user_id, attrs) do
    with {:ok, config} <- get_search_config(user_id) do
      config
      |> SearchConfig.update_changeset(attrs)
      |> Repo.update()
    end
  end

  defp create_default_config(user_id) do
    %SearchConfig{}
    |> SearchConfig.changeset(%{user_id: user_id})
    |> Repo.insert()
  end

  # ============================================
  # EMBEDDING JOBS
  # ============================================

  @doc """
  Create an embedding job record for tracking.
  """
  def create_embedding_job(entry_id, opts \\ []) do
    entry_id
    |> EmbeddingJob.create_changeset(opts)
    |> Repo.insert()
  end

  @doc """
  Get embedding job by ID.
  """
  def get_embedding_job(id) do
    Repo.get(EmbeddingJob, id)
  end

  @doc """
  Get latest embedding job for an entry.
  """
  def get_latest_embedding_job(entry_id) do
    EmbeddingJob
    |> where([j], j.entry_id == ^entry_id)
    |> order_by([j], desc: j.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Update embedding job status.
  """
  def update_embedding_job(job, attrs) do
    job
    |> EmbeddingJob.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Mark embedding job as processing.
  """
  def mark_job_processing(job) do
    job
    |> EmbeddingJob.mark_processing()
    |> Repo.update()
  end

  @doc """
  Mark embedding job as completed.
  """
  def mark_job_completed(job) do
    job
    |> EmbeddingJob.mark_completed()
    |> Repo.update()
  end

  @doc """
  Mark embedding job as failed.
  """
  def mark_job_failed(job, error_message) do
    job
    |> EmbeddingJob.mark_failed(error_message)
    |> Repo.update()
  end

  # ============================================
  # SEARCH OPERATIONS (Delegated to HybridSearch/TwoLayerSearch)
  # ============================================

  @doc """
  Perform search combining semantic and keyword matching.

  ## Options
    * `:search_type` - Search strategy to use:
      - `"hybrid"` - Semantic + keyword fusion (default)
      - `"semantic"` - Vector similarity only
      - `"keyword"` - Full-text search only
      - `"atomic"` - Atomic memories search (high precision)
      - `"memory_hybrid"` - Atomic memories + chunks combined
    * `:semantic_weight` - Weight for semantic results (default: 0.7)
    * `:keyword_weight` - Weight for keyword results (default: 0.3)
    * `:limit` - Max results (default: 20)
    * `:offset` - Pagination offset (default: 0)
    * `:filters` - Map of filters (entry_types, tags, date_range, etc.)

  ## Atomic/Memory Search Options (when using "atomic" or "memory_hybrid")
    * `:include_source_chunks` - Inject original context (default: true)
    * `:current_only` - Only non-superseded memories (default: true)
    * `:memory_weight` - Weight for memory results in hybrid (default: 0.6)
    * `:chunk_weight` - Weight for chunk results in hybrid (default: 0.4)
  """
  def search(user_id, query, opts \\ []) do
    search_type = Keyword.get(opts, :search_type, "hybrid")

    case search_type do
      "semantic" ->
        Onelist.Searcher.Search.semantic_search(user_id, query, opts)

      "keyword" ->
        Onelist.Searcher.Search.keyword_search(user_id, query, opts)

      "hybrid" ->
        Onelist.Searcher.HybridSearch.search(user_id, query, opts)

      "atomic" ->
        Onelist.Searcher.TwoLayerSearch.search(user_id, query, Keyword.put(opts, :search_mode, :atomic))

      "memory_hybrid" ->
        Onelist.Searcher.TwoLayerSearch.search(user_id, query, Keyword.put(opts, :search_mode, :hybrid))

      # Support atom versions
      :semantic ->
        Onelist.Searcher.Search.semantic_search(user_id, query, opts)

      :keyword ->
        Onelist.Searcher.Search.keyword_search(user_id, query, opts)

      :hybrid ->
        Onelist.Searcher.HybridSearch.search(user_id, query, opts)

      :atomic ->
        Onelist.Searcher.TwoLayerSearch.search(user_id, query, Keyword.put(opts, :search_mode, :atomic))

      :memory_hybrid ->
        Onelist.Searcher.TwoLayerSearch.search(user_id, query, Keyword.put(opts, :search_mode, :hybrid))

      _ ->
        {:error, {:invalid_search_type, search_type}}
    end
  end

  @doc """
  Perform atomic memory search (convenience wrapper).

  Searches extracted memories with high precision and returns
  results with source context injected.

  ## Options
    * `:include_source_chunks` - Inject original context (default: true)
    * `:current_only` - Only non-superseded memories (default: true)
    * `:limit` - Max results (default: 20)
    * `:filters` - Map with memory_types, min_confidence, etc.
  """
  def memory_search(user_id, query, opts \\ []) do
    Onelist.Searcher.TwoLayerSearch.search(user_id, query, Keyword.put(opts, :search_mode, :atomic))
  end

  @doc """
  Find entries similar to a given entry.

  ## Options
    * `:limit` - Max results (default: 10)
    * `:exclude` - List of entry IDs to exclude
  """
  def similar_entries(entry_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    exclude = Keyword.get(opts, :exclude, [])

    case get_embeddings(entry_id) do
      [] ->
        {:error, :not_embedded}

      embeddings ->
        # Use the first chunk's embedding for similarity
        embedding = hd(embeddings)
        Onelist.Searcher.Search.find_similar(embedding.vector, limit, exclude: [entry_id | exclude])
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  @doc """
  Returns the default embedding model name.
  """
  def default_model do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:embedding_model, "text-embedding-3-small")
  end

  @doc """
  Returns the default embedding dimensions.
  """
  def default_dimensions do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:embedding_dimensions, 1536)
  end

  @doc """
  Check if auto-embedding is enabled for user on create.
  """
  def auto_embed_on_create?(user_id) do
    case get_search_config(user_id) do
      {:ok, config} -> config.auto_embed_on_create
      _ -> Application.get_env(:onelist, :searcher, []) |> Keyword.get(:auto_embed_on_create, true)
    end
  end

  @doc """
  Check if auto-embedding is enabled for user on update.
  """
  def auto_embed_on_update?(user_id) do
    case get_search_config(user_id) do
      {:ok, config} -> config.auto_embed_on_update
      _ -> Application.get_env(:onelist, :searcher, []) |> Keyword.get(:auto_embed_on_update, true)
    end
  end
end
