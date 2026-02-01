defmodule Onelist.Reader.Workers.EmbedMemoriesWorker do
  @moduledoc """
  Oban worker for generating embeddings for extracted memories.

  This worker generates vector embeddings for memory content so that
  memories can be retrieved via semantic search.
  """

  use Oban.Worker,
    queue: :embeddings,
    max_attempts: 3,
    priority: 2

  alias Onelist.Repo
  alias Onelist.Reader.Memory

  import Ecto.Query

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"entry_id" => entry_id}}) do
    start_time = System.monotonic_time(:millisecond)

    Logger.info("Starting memory embedding for entry #{entry_id}")

    result =
      with {:ok, memories} <- get_memories_without_embeddings(entry_id),
           {:ok, count} <- generate_and_store_embeddings(memories) do
        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info(
          "Successfully embedded #{count} memories for entry #{entry_id} in #{duration}ms"
        )

        :ok
      end

    handle_result(result, entry_id)
  end

  defp get_memories_without_embeddings(entry_id) do
    memories =
      Memory
      |> where([m], m.entry_id == ^entry_id and is_nil(m.embedding))
      |> Repo.all()

    if Enum.empty?(memories) do
      {:ok, []}
    else
      {:ok, memories}
    end
  end

  defp generate_and_store_embeddings([]) do
    {:ok, 0}
  end

  defp generate_and_store_embeddings(memories) do
    # Extract content for embedding
    texts = Enum.map(memories, & &1.content)

    case embedding_provider().embed_batch(texts) do
      {:ok, vectors} ->
        # Update each memory with its embedding
        memories
        |> Enum.zip(vectors)
        |> Enum.each(fn {memory, vector} ->
          memory
          |> Memory.embedding_changeset(Pgvector.new(vector))
          |> Repo.update()
        end)

        {:ok, length(memories)}

      {:error, reason} ->
        {:error, {:embedding_failed, reason}}
    end
  end

  defp handle_result(:ok, _entry_id), do: :ok

  defp handle_result({:error, {:embedding_failed, reason}}, entry_id) do
    Logger.error("Failed to embed memories for entry #{entry_id}: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_result({:error, reason}, entry_id) do
    Logger.error("Memory embedding failed for entry #{entry_id}: #{inspect(reason)}")
    {:error, reason}
  end

  # Returns the configured embedding provider module
  defp embedding_provider do
    Application.get_env(:onelist, :reader_embedding_provider, Onelist.Searcher.Providers.OpenAI)
  end
end
