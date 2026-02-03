defmodule Onelist.Searcher.Workers.EmbedEntryWorker do
  @moduledoc """
  Oban worker for generating embeddings for a single entry.

  This worker is queued when an entry is created or updated (if auto-embed is enabled).
  It extracts text from the entry's representations, chunks it if needed,
  generates embeddings via the configured provider, and stores them.
  """

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 3,
    priority: 1

  alias Onelist.{Repo, Entries}
  alias Onelist.Searcher
  alias Onelist.Searcher.{Embedding, Chunker}
  alias Onelist.Searcher.Providers.OpenAI

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id} = args}) do
    _priority = Map.get(args, "priority", 0)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting embedding generation for entry #{entry_id}")

    result =
      with {:ok, entry} <- get_entry(entry_id),
           {:ok, text} <- extract_embeddable_text(entry),
           {:ok, chunks} <- chunk_text(text, entry.user_id),
           {:ok, vectors} <- generate_embeddings(chunks),
           {:ok, count} <- store_embeddings(entry, chunks, vectors) do
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "Successfully embedded entry #{entry_id}: #{count} embeddings in #{duration}ms"
        )

        :ok
      end

    case result do
      :ok ->
        :ok

      {:error, :entry_not_found} ->
        Logger.warning("Entry #{entry_id} not found, skipping embedding")
        # Don't retry if entry doesn't exist
        :ok

      {:error, :no_content} ->
        Logger.debug("Entry #{entry_id} has no embeddable content")
        :ok

      {:error, {:rate_limited, _}} ->
        Logger.warning("Rate limited while embedding entry #{entry_id}, will retry")
        {:error, "Rate limited"}

      {:error, reason} ->
        Logger.error("Failed to embed entry #{entry_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_entry(entry_id) do
    case Entries.get_entry(entry_id) do
      nil -> {:error, :entry_not_found}
      entry -> {:ok, Repo.preload(entry, [:representations])}
    end
  end

  defp extract_embeddable_text(entry) do
    # Priority order for text extraction:
    # 1. markdown representation
    # 2. plain_text representation
    # 3. title + entry-level content field

    text =
      cond do
        rep = find_representation(entry.representations, "markdown") ->
          rep.content

        rep = find_representation(entry.representations, "plain_text") ->
          rep.content

        true ->
          # Fallback to title and any direct content
          [entry.title]
          |> Enum.filter(& &1)
          |> Enum.join("\n\n")
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

  defp chunk_text(text, user_id) do
    config = Searcher.get_search_config!(user_id)

    chunks =
      Chunker.chunk(text,
        max_tokens: config.max_chunk_tokens,
        overlap_tokens: config.chunk_overlap_tokens
      )

    {:ok, chunks}
  end

  defp generate_embeddings(chunks) do
    texts = Enum.map(chunks, & &1.text)

    case OpenAI.embed_batch(texts) do
      {:ok, vectors} -> {:ok, vectors}
      {:error, reason} -> {:error, {:embedding_failed, reason}}
    end
  end

  defp store_embeddings(entry, chunks, vectors) do
    now = DateTime.utc_now()

    # Delete existing embeddings for this entry/model
    Embedding
    |> where([e], e.entry_id == ^entry.id and e.model_name == ^OpenAI.model_name())
    |> Repo.delete_all()

    # Prepare embeddings for batch insert
    embeddings =
      chunks
      |> Enum.zip(vectors)
      |> Enum.with_index()
      |> Enum.map(fn {{chunk, vector}, index} ->
        %{
          id: Ecto.UUID.generate(),
          entry_id: entry.id,
          model_name: OpenAI.model_name(),
          model_version: OpenAI.model_version(),
          dimensions: OpenAI.dimensions(),
          vector: Pgvector.new(vector),
          chunk_index: index,
          chunk_text: chunk.text,
          chunk_start_offset: chunk.start_offset,
          chunk_end_offset: chunk.end_offset,
          token_count: chunk.token_count,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(Embedding, embeddings)
    {:ok, count}
  end
end
