defmodule Onelist.Searcher.Search do
  @moduledoc """
  Individual search implementations (semantic and keyword).

  This module provides the building blocks for hybrid search:
  - Semantic search using pgvector cosine similarity
  - Keyword search using PostgreSQL full-text search
  """

  import Ecto.Query, warn: false
  alias Onelist.Repo
  alias Onelist.Entries.Entry
  alias Onelist.Searcher.{Embedding}
  alias Onelist.Searcher.Providers.OpenAI

  require Logger

  @doc """
  Perform semantic search using vector similarity.

  ## Options
    * `:limit` - Max results (default: 20)
    * `:offset` - Pagination offset (default: 0)
    * `:filters` - Map of filters (entry_types, tags, date_range)
  """
  def semantic_search(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.get(opts, :filters, %{})

    with {:ok, query_vector} <- embed_query(query) do
      results = do_semantic_search(user_id, query_vector, filters, limit, offset)

      {:ok, %{
        results: results,
        total: length(results),
        query: query,
        search_type: "semantic"
      }}
    end
  end

  @doc """
  Perform keyword search using PostgreSQL full-text search.

  ## Options
    * `:limit` - Max results (default: 20)
    * `:offset` - Pagination offset (default: 0)
    * `:filters` - Map of filters (entry_types, tags, date_range)
  """
  def keyword_search(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    filters = Keyword.get(opts, :filters, %{})

    results = do_keyword_search(user_id, query, filters, limit, offset)

    {:ok, %{
      results: results,
      total: length(results),
      query: query,
      search_type: "keyword"
    }}
  end

  @doc """
  Find entries similar to a given vector.

  ## Options
    * `:exclude` - List of entry IDs to exclude from results
  """
  def find_similar(query_vector, limit, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])

    base_query =
      from e in Entry,
        join: emb in Embedding, on: emb.entry_id == e.id,
        where: emb.model_name == ^OpenAI.model_name(),
        where: e.id not in ^exclude,
        select: %{
          entry_id: e.id,
          title: e.title,
          entry_type: e.entry_type,
          score: fragment(
            "1 - (? <=> ?)",
            emb.vector,
            ^Pgvector.new(query_vector)
          )
        },
        order_by: [asc: fragment("? <=> ?", emb.vector, ^Pgvector.new(query_vector))],
        limit: ^limit

    results = Repo.all(base_query)
    {:ok, results}
  end

  # Internal semantic search implementation
  def do_semantic_search(user_id, query_vector, filters, limit, offset) do
    base_query =
      from e in Entry,
        join: emb in Embedding, on: emb.entry_id == e.id,
        where: e.user_id == ^user_id,
        where: emb.model_name == ^OpenAI.model_name(),
        select: %{
          entry_id: e.id,
          title: e.title,
          entry_type: e.entry_type,
          score: fragment(
            "1 - (? <=> ?)",
            emb.vector,
            ^Pgvector.new(query_vector)
          )
        },
        order_by: [asc: fragment("? <=> ?", emb.vector, ^Pgvector.new(query_vector))],
        limit: ^limit,
        offset: ^offset

    query = apply_filters(base_query, filters)
    Repo.all(query)
  end

  # Internal keyword search implementation
  def do_keyword_search(user_id, query, filters, limit, offset) do
    tsquery = to_tsquery(query)

    # Skip search if query results in empty tsquery
    if tsquery == "" do
      []
    else
      base_query =
        from e in Entry,
          where: e.user_id == ^user_id,
          where: fragment(
            "to_tsvector('english', coalesce(?, '')) @@ to_tsquery('english', ?)",
            e.title,
            ^tsquery
          ),
          select: %{
            entry_id: e.id,
            title: e.title,
            entry_type: e.entry_type,
            score: fragment(
              "ts_rank(to_tsvector('english', coalesce(?, '')), to_tsquery('english', ?))",
              e.title,
              ^tsquery
            )
          },
          order_by: [desc: fragment(
            "ts_rank(to_tsvector('english', coalesce(?, '')), to_tsquery('english', ?))",
            e.title,
            ^tsquery
          )],
          limit: ^limit,
          offset: ^offset

      query = apply_filters(base_query, filters)
      Repo.all(query)
    end
  end

  @doc """
  Generate embedding for a search query.
  """
  def embed_query(query) do
    OpenAI.embed(query)
  end

  # Convert user query to PostgreSQL tsquery format
  defp to_tsquery(query) do
    query
    |> String.split(~r/\s+/)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.map(&sanitize_tsquery_term/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" & ")
  end

  # Sanitize individual terms for tsquery
  defp sanitize_tsquery_term(term) do
    term
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.downcase()
  end

  # Apply filters to the query
  defp apply_filters(query, filters) do
    query
    |> maybe_filter_entry_types(filters["entry_types"] || filters[:entry_types])
    |> maybe_filter_tags(filters["tags"] || filters[:tags])
    |> maybe_filter_date_range(filters["date_range"] || filters[:date_range])
  end

  defp maybe_filter_entry_types(query, nil), do: query
  defp maybe_filter_entry_types(query, []), do: query
  defp maybe_filter_entry_types(query, types) when is_list(types) do
    where(query, [e], e.entry_type in ^types)
  end

  defp maybe_filter_tags(query, nil), do: query
  defp maybe_filter_tags(query, []), do: query
  defp maybe_filter_tags(query, tags) when is_list(tags) do
    from e in query,
      join: et in "entry_tags", on: et.entry_id == e.id,
      join: t in "tags", on: t.id == et.tag_id,
      where: t.name in ^tags,
      distinct: true
  end

  defp maybe_filter_date_range(query, nil), do: query
  defp maybe_filter_date_range(query, %{"from" => from, "to" => to}) do
    where(query, [e], e.inserted_at >= ^from and e.inserted_at <= ^to)
  end
  defp maybe_filter_date_range(query, %{from: from, to: to}) do
    where(query, [e], e.inserted_at >= ^from and e.inserted_at <= ^to)
  end
  defp maybe_filter_date_range(query, _), do: query
end
