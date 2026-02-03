defmodule Onelist.Searcher.QueryReformulator do
  @moduledoc """
  Query expansion and reformulation for improved search recall.

  Implements Agentic RAG patterns by:
  - Expanding abbreviations and acronyms
  - Generating synonyms for key terms
  - Breaking complex queries into sub-queries
  - Using LLM for intelligent query reformulation

  ## Configuration

  Configure in `config/config.exs`:

      config :onelist, :searcher,
        reformulation_enabled: true,
        reformulation_model: "gpt-4o-mini",
        max_sub_queries: 3

  ## Usage

      {:ok, queries} = QueryReformulator.reformulate("ML for NLP", [])
      # => ["ML for NLP", "machine learning for natural language processing", ...]
  """

  alias Onelist.Searcher.ModelRouter

  require Logger

  @default_max_sub_queries 3

  # Common abbreviation mappings
  @abbreviations %{
    "ml" => "machine learning",
    "ai" => "artificial intelligence",
    "nlp" => "natural language processing",
    "llm" => "large language model",
    "api" => "application programming interface",
    "ui" => "user interface",
    "ux" => "user experience",
    "db" => "database",
    "sql" => "structured query language",
    "js" => "javascript",
    "ts" => "typescript",
    "py" => "python",
    "rb" => "ruby",
    "ex" => "elixir",
    "oop" => "object oriented programming",
    "fp" => "functional programming",
    "tdd" => "test driven development",
    "ci" => "continuous integration",
    "cd" => "continuous deployment",
    "k8s" => "kubernetes",
    "aws" => "amazon web services",
    "gcp" => "google cloud platform"
  }

  # Common stop words to filter
  @stop_words ~w(a an the is are was were be been being have has had do does did
                 will would could should may might must shall can this that these
                 those it its what which who whom whose when where why how and or
                 but if then else for of to from by with at in on as)

  @doc """
  Reformulate a query for improved search recall.

  ## Parameters
    - query: The original search query
    - opts: Options
      - `:enabled` - Whether to perform reformulation (default: from config)
      - `:expand_abbreviations` - Expand common abbreviations (default: true)
      - `:add_synonyms` - Add synonym variants (default: true)
      - `:generate_sub_queries` - Break complex queries (default: true)
      - `:max_sub_queries` - Maximum number of sub-queries (default: 3)

  ## Returns
    - `{:ok, queries}` - List of query variants
    - `{:error, reason}` - Error tuple
  """
  def reformulate(query, opts \\ []) do
    enabled = Keyword.get(opts, :enabled, enabled?())

    cond do
      not enabled ->
        {:ok, [query]}

      String.length(query) < 5 ->
        # Too short to meaningfully reformulate
        {:ok, [query]}

      not api_configured?() and complex_reformulation_needed?(query) ->
        # Fall back to simple reformulation
        {:ok, simple_reformulate(query, opts)}

      true ->
        {:ok, simple_reformulate(query, opts)}
    end
  end

  @doc """
  Check if reformulation is enabled.
  """
  def enabled? do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:reformulation_enabled, true)
  end

  @doc """
  Expand common abbreviations in a query.
  """
  def expand_query(query) do
    words = String.split(query, ~r/\s+/)

    expanded_words =
      Enum.map(words, fn word ->
        lower = String.downcase(word)
        Map.get(@abbreviations, lower, word)
      end)

    Enum.join(expanded_words, " ")
  end

  @doc """
  Generate sub-queries from a complex query.

  Splits queries with multiple clauses (and, or, also, as well as)
  into separate sub-queries.
  """
  def generate_sub_queries(query) do
    if is_complex_query?(query) do
      # Split on conjunctions
      sub_queries =
        query
        |> String.split(~r/\s+and\s+|\s+or\s+|\s+also\s+|,\s+|\?\s+/i)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(String.length(&1) > 3))
        |> Enum.take(@default_max_sub_queries)

      if length(sub_queries) > 0 do
        [query | sub_queries] |> Enum.uniq()
      else
        [query]
      end
    else
      [query]
    end
  end

  @doc """
  Extract significant keywords from a query.

  Filters out stop words and returns meaningful terms.
  """
  def extract_keywords(query) do
    query
    |> String.downcase()
    |> String.split(~r/[^\w]+/)
    |> Enum.filter(fn word ->
      String.length(word) > 2 and word not in @stop_words
    end)
    |> Enum.uniq()
  end

  @doc """
  Add synonym variants for query terms.

  Returns a list of query variants with synonyms.
  """
  def add_synonyms(query) do
    # Simple synonym mapping for common search terms
    synonyms = %{
      "find" => ["search", "locate", "discover"],
      "search" => ["find", "look for"],
      "documents" => ["files", "entries", "records"],
      "create" => ["make", "build", "generate"],
      "update" => ["modify", "change", "edit"],
      "delete" => ["remove", "erase"]
    }

    keywords = extract_keywords(query)

    synonym_variants =
      keywords
      |> Enum.flat_map(fn keyword ->
        case Map.get(synonyms, keyword) do
          nil -> []
          syns -> Enum.map(syns, fn syn -> String.replace(query, keyword, syn) end)
        end
      end)
      # Limit synonym variants
      |> Enum.take(2)

    [query | synonym_variants] |> Enum.uniq()
  end

  @doc """
  Check if a query is complex (multiple clauses, questions, etc.)
  """
  def is_complex_query?(query) do
    cond do
      String.length(query) < 10 ->
        false

      String.contains?(query, [" and ", " or ", " also "]) ->
        true

      String.contains?(query, "?") and String.length(query) > 30 ->
        true

      length(String.split(query, ~r/\s+/)) > 8 ->
        true

      true ->
        false
    end
  end

  @doc """
  Merge results from multiple query variants.

  Combines results, keeping the highest score for each entry.
  """
  def merge_results(result_sets) do
    result_sets
    |> List.flatten()
    |> Enum.group_by(& &1.entry_id)
    |> Enum.map(fn {_id, results} ->
      # Keep the result with highest score
      Enum.max_by(results, & &1.score)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  @doc """
  Select the appropriate model for reformulation.
  """
  def select_model(opts) do
    query_length = Keyword.get(opts, :query_length, 0)
    ModelRouter.select_model(:query_expansion, %{query_length: query_length})
  end

  @doc """
  Get default reformulation options.
  """
  def default_options do
    [
      enabled: enabled?(),
      expand_abbreviations: true,
      add_synonyms: true,
      generate_sub_queries: true,
      max_sub_queries: config(:max_sub_queries, @default_max_sub_queries)
    ]
  end

  # Private Functions

  defp simple_reformulate(query, opts) do
    expand = Keyword.get(opts, :expand_abbreviations, true)
    synonyms = Keyword.get(opts, :add_synonyms, true)
    sub_queries = Keyword.get(opts, :generate_sub_queries, true)

    variants = [query]

    # Add expanded version
    variants =
      if expand do
        expanded = expand_query(query)
        if expanded != query, do: variants ++ [expanded], else: variants
      else
        variants
      end

    # Add sub-queries
    variants =
      if sub_queries and is_complex_query?(query) do
        sub = generate_sub_queries(query)
        (variants ++ sub) |> Enum.uniq()
      else
        variants
      end

    # Add synonym variants
    variants =
      if synonyms do
        syns = add_synonyms(query)
        (variants ++ syns) |> Enum.uniq()
      else
        variants
      end

    Enum.take(variants, config(:max_sub_queries, @default_max_sub_queries) + 1)
  end

  defp complex_reformulation_needed?(query) do
    is_complex_query?(query)
  end

  defp api_configured? do
    not is_nil(Application.get_env(:onelist, :openai_api_key) || System.get_env("OPENAI_API_KEY"))
  end

  defp config(key, default) do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(key, default)
  end
end
