defmodule OnelistWeb.Api.V1.SearchController do
  @moduledoc """
  API controller for search operations.

  Provides endpoints for:
  - Hybrid search (semantic + keyword)
  - Semantic-only search
  - Keyword-only search
  - Similar entries discovery
  """
  use OnelistWeb, :controller

  alias Onelist.Searcher

  action_fallback OnelistWeb.Api.V1.FallbackController

  @default_limit 20
  @max_limit 100

  @doc """
  Performs a search across the user's entries.

  POST /api/v1/search

  Body parameters:
  - query: Search query string (required)
  - search_type: "hybrid", "semantic", or "keyword" (default: "hybrid")
  - semantic_weight: Weight for semantic results 0-1 (default: 0.7)
  - keyword_weight: Weight for keyword results 0-1 (default: 0.3)
  - limit: Max results to return (default: 20, max: 100)
  - offset: Pagination offset (default: 0)
  - filters: Object with optional filters
    - entry_types: Array of entry types to filter by
    - tags: Array of tag names to filter by
    - date_range: Object with "from" and "to" ISO8601 dates
  """
  def search(conn, params) do
    user = conn.assigns.current_user
    query = params["query"] || ""

    if String.trim(query) == "" do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        success: false,
        error: %{
          message: "Query parameter is required",
          code: "missing_query"
        }
      })
    else
      opts = [
        search_type: params["search_type"] || "hybrid",
        semantic_weight: parse_float(params["semantic_weight"], 0.7),
        keyword_weight: parse_float(params["keyword_weight"], 0.3),
        limit: parse_limit(params["limit"]),
        offset: parse_int(params["offset"], 0),
        filters: parse_filters(params["filters"])
      ]

      case Searcher.search(user.id, query, opts) do
        {:ok, results} ->
          json(conn, %{
            success: true,
            data: %{
              results: format_results(results.results),
              total: results.total,
              query: results.query,
              search_type: results.search_type,
              weights: Map.get(results, :weights)
            }
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: %{
              message: "Search failed",
              reason: inspect(reason)
            }
          })
      end
    end
  end

  @doc """
  Finds entries similar to a given entry.

  GET /api/v1/entries/:entry_id/similar

  Query parameters:
  - limit: Max results to return (default: 10, max: 50)
  """
  def similar(conn, %{"entry_id" => entry_id} = params) do
    user = conn.assigns.current_user
    limit = min(parse_int(params["limit"], 10), 50)

    # First verify the user owns the entry
    case Onelist.Entries.get_user_entry(user, entry_id) do
      nil ->
        {:error, :not_found}

      _entry ->
        case Searcher.similar_entries(entry_id, limit: limit) do
          {:ok, results} ->
            json(conn, %{
              success: true,
              data: %{
                results: format_results(results),
                entry_id: entry_id,
                total: length(results)
              }
            })

          {:error, :not_embedded} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              success: false,
              error: %{
                message: "Entry has not been embedded yet",
                code: "not_embedded"
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
  end

  # Format results for JSON response
  defp format_results(results) do
    Enum.map(results, fn r ->
      %{
        entry_id: r.entry_id,
        title: r.title,
        entry_type: r.entry_type,
        score: Map.get(r, :combined_score) || r.score,
        semantic_score: Map.get(r, :semantic_score),
        keyword_score: Map.get(r, :keyword_score)
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
    end)
  end

  defp parse_float(nil, default), do: default
  defp parse_float(val, _) when is_float(val), do: val
  defp parse_float(val, _) when is_integer(val), do: val * 1.0

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> default
    end
  end

  defp parse_int(nil, default), do: default
  defp parse_int(val, _) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> default
    end
  end

  defp parse_limit(limit) do
    limit
    |> parse_int(@default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_filters(nil), do: %{}
  defp parse_filters(filters) when is_map(filters), do: filters
  defp parse_filters(_), do: %{}
end
