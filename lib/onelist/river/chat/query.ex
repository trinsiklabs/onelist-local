defmodule Onelist.River.Chat.Query do
  @moduledoc """
  Direct query execution for River.

  Used for programmatic queries outside of the chat flow.
  """

  alias Onelist.Searcher
  alias Onelist.River.Chat.ResponseGenerator

  require Logger

  @doc """
  Execute a query and return structured results.

  ## Options
    * `:limit` - Max results (default: 10)
    * `:search_type` - Type of search (default: :hybrid)
  """
  def execute(user_id, query_text, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    search_type = Keyword.get(opts, :search_type, :hybrid)

    case Searcher.search(user_id, query_text, limit: limit, search_type: search_type) do
      {:ok, %{results: results}} when is_list(results) ->
        {:ok,
         %{
           query: query_text,
           results: results,
           count: length(results),
           message: format_results(query_text, results)
         }}

      {:ok, _} ->
        {:ok,
         %{
           query: query_text,
           results: [],
           count: 0,
           message: ResponseGenerator.no_results(query_text)
         }}

      {:error, reason} ->
        Logger.error("Query failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp format_results(query, []) do
    ResponseGenerator.no_results(query)
  end

  defp format_results(query, results) do
    ResponseGenerator.query_results(query, results)
  end
end
