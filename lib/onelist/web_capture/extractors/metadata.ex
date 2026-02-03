defmodule Onelist.WebCapture.Extractors.Metadata do
  @moduledoc """
  Extracts metadata from HTML documents.

  Supports:
  - Open Graph tags (og:*)
  - Twitter Cards (twitter:*)
  - Standard meta tags (author, description, keywords)
  - Schema.org JSON-LD
  - Canonical URLs
  """

  @type metadata :: %{
          title: String.t() | nil,
          description: String.t() | nil,
          author: String.t() | nil,
          published_at: DateTime.t() | nil,
          site_name: String.t() | nil,
          image: String.t() | nil,
          canonical_url: String.t() | nil,
          og: map(),
          twitter: map(),
          keywords: [String.t()]
        }

  @doc """
  Extract metadata from a Floki document.

  ## Examples

      {:ok, document} = Floki.parse_document(html)
      {:ok, metadata} = Metadata.extract(document, "https://example.com/article")
  """
  @spec extract(Floki.html_tree(), String.t()) :: {:ok, metadata()} | {:error, term()}
  def extract(document, url) do
    og = extract_og_tags(document)
    twitter = extract_twitter_tags(document)

    metadata = %{
      title: extract_title(document, og, twitter),
      description: extract_description(document, og, twitter),
      author: extract_author(document, og),
      published_at: extract_published_at(document),
      site_name: og["site_name"] || extract_domain(url),
      image: make_absolute(og["image"] || twitter["image"], url),
      canonical_url: extract_canonical(document) |> make_absolute(url),
      og: og,
      twitter: twitter,
      keywords: extract_keywords(document)
    }

    {:ok, metadata}
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract just the title from a document.
  """
  @spec extract_title(Floki.html_tree()) :: String.t() | nil
  def extract_title(document) do
    extract_title(document, %{}, %{})
  end

  # ============================================
  # OPEN GRAPH
  # ============================================

  defp extract_og_tags(document) do
    document
    |> Floki.find("meta[property^='og:']")
    |> Enum.reduce(%{}, fn element, acc ->
      property = Floki.attribute(element, "property") |> List.first() || ""
      content = Floki.attribute(element, "content") |> List.first()

      key = String.replace_prefix(property, "og:", "")
      if content && key != "", do: Map.put(acc, key, content), else: acc
    end)
  end

  # ============================================
  # TWITTER CARDS
  # ============================================

  defp extract_twitter_tags(document) do
    document
    |> Floki.find("meta[name^='twitter:'], meta[property^='twitter:']")
    |> Enum.reduce(%{}, fn element, acc ->
      name =
        Floki.attribute(element, "name") |> List.first() ||
          Floki.attribute(element, "property") |> List.first() || ""

      content = Floki.attribute(element, "content") |> List.first()

      key = String.replace_prefix(name, "twitter:", "")
      if content && key != "", do: Map.put(acc, key, content), else: acc
    end)
  end

  # ============================================
  # STANDARD META TAGS
  # ============================================

  defp extract_title(document, og, twitter) do
    og["title"] ||
      twitter["title"] ||
      get_meta_content(document, "title") ||
      get_element_text(document, "title") ||
      get_element_text(document, "h1")
  end

  defp extract_description(document, og, twitter) do
    og["description"] ||
      twitter["description"] ||
      get_meta_content(document, "description")
  end

  defp extract_author(document, og) do
    og["author"] ||
      get_meta_content(document, "author") ||
      get_meta_content(document, "article:author") ||
      extract_author_from_jsonld(document)
  end

  defp extract_published_at(document) do
    [
      get_meta_content(document, "article:published_time"),
      get_meta_content(document, "datePublished"),
      get_meta_content(document, "date"),
      get_meta_content(document, "DC.date"),
      extract_date_from_jsonld(document),
      get_element_attr(document, "time[datetime]", "datetime")
    ]
    |> Enum.find(&(&1 != nil))
    |> parse_datetime()
  end

  defp extract_canonical(document) do
    document
    |> Floki.find("link[rel='canonical']")
    |> List.first()
    |> case do
      nil -> nil
      elem -> Floki.attribute(elem, "href") |> List.first()
    end
  end

  defp extract_keywords(document) do
    case get_meta_content(document, "keywords") do
      nil ->
        []

      keywords ->
        keywords
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  # ============================================
  # JSON-LD EXTRACTION
  # ============================================

  defp extract_author_from_jsonld(document) do
    case parse_jsonld(document) do
      nil ->
        nil

      data ->
        case get_in(data, ["author"]) do
          %{"name" => name} -> name
          name when is_binary(name) -> name
          [%{"name" => name} | _] -> name
          _ -> nil
        end
    end
  end

  defp extract_date_from_jsonld(document) do
    case parse_jsonld(document) do
      nil ->
        nil

      data ->
        data["datePublished"] || data["dateCreated"]
    end
  end

  defp parse_jsonld(document) do
    document
    |> Floki.find("script[type='application/ld+json']")
    |> Enum.find_value(fn script ->
      text = Floki.text(script)

      case Jason.decode(text) do
        {:ok, data} when is_map(data) ->
          # Look for Article or NewsArticle types
          if data["@type"] in ["Article", "NewsArticle", "BlogPosting", "WebPage"] do
            data
          else
            nil
          end

        _ ->
          nil
      end
    end)
  rescue
    _ -> nil
  end

  # ============================================
  # HELPERS
  # ============================================

  defp get_meta_content(document, name) do
    selectors = [
      "meta[name='#{name}']",
      "meta[property='#{name}']",
      "meta[itemprop='#{name}']"
    ]

    Enum.find_value(selectors, fn selector ->
      case Floki.find(document, selector) do
        [] ->
          nil

        [elem | _] ->
          content = Floki.attribute(elem, "content") |> List.first()
          if content && content != "", do: String.trim(content), else: nil
      end
    end)
  end

  defp get_element_text(document, selector) do
    case Floki.find(document, selector) do
      [] ->
        nil

      [elem | _] ->
        text = Floki.text(elem) |> String.trim()
        if text != "", do: text, else: nil
    end
  end

  defp get_element_attr(document, selector, attr) do
    case Floki.find(document, selector) do
      [] ->
        nil

      [elem | _] ->
        Floki.attribute(elem, attr) |> List.first()
    end
  end

  defp extract_domain(url) do
    case URI.parse(url) do
      %{host: nil} -> nil
      %{host: host} -> String.replace(host, ~r/^www\./, "")
    end
  end

  defp make_absolute(nil, _base_url), do: nil

  defp make_absolute(url, base_url) do
    uri = URI.parse(url)

    if uri.scheme do
      url
    else
      base = URI.parse(base_url)
      URI.merge(base, uri) |> URI.to_string()
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    # Try ISO8601 first
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} ->
        dt

      _ ->
        # Try date-only format
        case Date.from_iso8601(str) do
          {:ok, date} ->
            DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

          _ ->
            nil
        end
    end
  end

  defp parse_datetime(_), do: nil
end
