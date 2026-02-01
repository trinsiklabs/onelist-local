defmodule OnelistWeb.Helpers.Markdown do
  @moduledoc """
  Safe Markdown rendering with HTML sanitization and caching.

  Uses ETS-based caching to avoid re-rendering the same content repeatedly.
  Cache keys are based on content hashes, with a default TTL of 1 hour.
  """

  alias Onelist.Cache

  @cache_ttl :timer.hours(1)

  @doc """
  Converts Markdown text to sanitized HTML with caching.

  Returns an empty string for nil or empty input.
  Sanitizes the output to prevent XSS attacks.
  Results are cached based on content hash.

  ## Options

    * `:cache` - Whether to use caching (default: true)
  """
  @spec to_html(String.t() | nil, keyword()) :: String.t()
  def to_html(markdown, opts \\ [])

  def to_html(nil, _opts), do: ""
  def to_html("", _opts), do: ""

  def to_html(markdown, opts) when is_binary(markdown) do
    use_cache = Keyword.get(opts, :cache, true)

    if use_cache do
      cache_key = {:markdown, :erlang.phash2(markdown)}

      Cache.fetch(cache_key, @cache_ttl, fn ->
        render_uncached(markdown)
      end)
    else
      render_uncached(markdown)
    end
  end

  @doc """
  Renders markdown without caching.

  Useful when you know the content is unique or when testing.
  """
  @spec render_uncached(String.t()) :: String.t()
  def render_uncached(markdown) when is_binary(markdown) do
    markdown
    |> Earmark.as_html!(breaks: true, smartypants: false)
    |> HtmlSanitizeEx.markdown_html()
  end

  @doc """
  Invalidates the cache entry for specific content.
  """
  @spec invalidate(String.t()) :: :ok
  def invalidate(markdown) when is_binary(markdown) do
    cache_key = {:markdown, :erlang.phash2(markdown)}
    Cache.delete(cache_key)
  end
end
