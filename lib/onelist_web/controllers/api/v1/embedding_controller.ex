defmodule OnelistWeb.Api.V1.EmbeddingController do
  @moduledoc """
  API controller for embedding management.

  Provides endpoints for:
  - Checking embedding status for entries
  - Manually triggering embedding generation
  - Managing search configuration
  """
  use OnelistWeb, :controller

  alias Onelist.Searcher
  alias Onelist.Entries

  action_fallback OnelistWeb.Api.V1.FallbackController

  @doc """
  Gets embedding status for an entry.

  GET /api/v1/embeddings/:entry_id
  """
  def show(conn, %{"entry_id" => entry_id}) do
    user = conn.assigns.current_user

    # Verify user owns the entry
    case Entries.get_user_entry(user, entry_id) do
      nil ->
        {:error, :not_found}

      _entry ->
        embeddings = Searcher.get_embeddings(entry_id)

        if Enum.empty?(embeddings) do
          json(conn, %{
            success: true,
            data: %{
              embedded: false,
              entry_id: entry_id
            }
          })
        else
          first = hd(embeddings)

          json(conn, %{
            success: true,
            data: %{
              embedded: true,
              entry_id: entry_id,
              model: first.model_name,
              model_version: first.model_version,
              chunks: length(embeddings),
              dimensions: first.dimensions,
              embedded_at: first.inserted_at
            }
          })
        end
    end
  end

  @doc """
  Manually triggers embedding generation for one or more entries.

  POST /api/v1/embeddings

  Body parameters:
  - entry_ids: Array of entry IDs to embed (required)
  - priority: Job priority (optional, default: 0)
  """
  def create(conn, %{"entry_ids" => entry_ids}) when is_list(entry_ids) do
    user = conn.assigns.current_user
    priority = Map.get(conn.body_params, "priority", 0)

    # Filter to only entries owned by the user
    valid_entry_ids =
      entry_ids
      |> Enum.filter(fn id ->
        case Entries.get_user_entry(user, id) do
          nil -> false
          _ -> true
        end
      end)

    if Enum.empty?(valid_entry_ids) do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        success: false,
        error: %{
          message: "No valid entry IDs provided",
          code: "no_valid_entries"
        }
      })
    else
      # Enqueue individual jobs for each entry
      results =
        Enum.map(valid_entry_ids, fn entry_id ->
          case Searcher.enqueue_embedding(entry_id, priority: priority) do
            {:ok, job} -> {:ok, entry_id, job.id}
            {:error, reason} -> {:error, entry_id, reason}
          end
        end)

      successes = Enum.count(results, fn r -> match?({:ok, _, _}, r) end)
      failures = Enum.count(results, fn r -> match?({:error, _, _}, r) end)

      json(conn, %{
        success: true,
        data: %{
          message: "Embedding jobs enqueued",
          entry_count: successes,
          failed_count: failures,
          entry_ids: valid_entry_ids
        }
      })
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      success: false,
      error: %{
        message: "entry_ids array is required",
        code: "missing_entry_ids"
      }
    })
  end

  @doc """
  Gets the user's search configuration.

  GET /api/v1/embeddings/config
  """
  def config(conn, _params) do
    user = conn.assigns.current_user

    case Searcher.get_search_config(user.id) do
      {:ok, config} ->
        json(conn, %{
          success: true,
          data: %{
            embedding_model: config.embedding_model,
            embedding_dimensions: config.embedding_dimensions,
            default_search_type: config.default_search_type,
            semantic_weight: config.semantic_weight,
            keyword_weight: config.keyword_weight,
            auto_embed_on_create: config.auto_embed_on_create,
            auto_embed_on_update: config.auto_embed_on_update,
            max_chunk_tokens: config.max_chunk_tokens,
            chunk_overlap_tokens: config.chunk_overlap_tokens,
            daily_embedding_limit: config.daily_embedding_limit,
            embeddings_today: config.embeddings_today
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: %{message: inspect(reason)}
        })
    end
  end

  @doc """
  Updates the user's search configuration.

  PATCH /api/v1/embeddings/config

  Body parameters (all optional):
  - default_search_type: "hybrid", "semantic", or "keyword"
  - semantic_weight: 0.0 to 1.0
  - keyword_weight: 0.0 to 1.0
  - auto_embed_on_create: boolean
  - auto_embed_on_update: boolean
  - max_chunk_tokens: positive integer
  - chunk_overlap_tokens: non-negative integer
  """
  def update_config(conn, params) do
    user = conn.assigns.current_user

    # Filter to only allowed params
    allowed_params =
      params
      |> Map.take([
        "default_search_type",
        "semantic_weight",
        "keyword_weight",
        "auto_embed_on_create",
        "auto_embed_on_update",
        "max_chunk_tokens",
        "chunk_overlap_tokens"
      ])
      |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Searcher.update_search_config(user.id, allowed_params) do
      {:ok, config} ->
        json(conn, %{
          success: true,
          data: %{
            embedding_model: config.embedding_model,
            default_search_type: config.default_search_type,
            semantic_weight: config.semantic_weight,
            keyword_weight: config.keyword_weight,
            auto_embed_on_create: config.auto_embed_on_create,
            auto_embed_on_update: config.auto_embed_on_update,
            max_chunk_tokens: config.max_chunk_tokens,
            chunk_overlap_tokens: config.chunk_overlap_tokens
          }
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: %{
            message: "Validation failed",
            details: format_changeset_errors(changeset)
          }
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: %{message: inspect(reason)}
        })
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
