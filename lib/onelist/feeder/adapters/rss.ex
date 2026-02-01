defmodule Onelist.Feeder.Adapters.RSS do
  @moduledoc """
  Adapter for RSS/Atom feed subscriptions.

  Supports continuous sync via feed polling. Does not support one-time import
  (feeds are inherently continuous).

  ## Credentials Format

  ```elixir
  %{
    "feed_url" => "https://example.com/feed.xml",
    "basic_auth" => %{"username" => "...", "password" => "..."}  # optional
  }
  ```

  ## Sync Cursor

  ```elixir
  %{
    "last_item_date" => "2024-01-15T10:30:00Z",
    "last_item_guids" => ["guid1", "guid2", ...]  # for dedup
  }
  ```
  """

  use Onelist.Feeder.Adapters.Adapter

  require Logger

  @impl true
  def source_type, do: "rss"

  @impl true
  def supports_continuous_sync?, do: true

  @impl true
  def supports_one_time_import?, do: false

  @impl true
  def validate_credentials(credentials) do
    case Map.get(credentials, "feed_url") do
      nil -> {:error, :missing_feed_url}
      "" -> {:error, :missing_feed_url}
      url when is_binary(url) ->
        if valid_url?(url), do: :ok, else: {:error, :invalid_feed_url}
    end
  end

  @impl true
  def fetch_changes(credentials, cursor, _opts) do
    feed_url = credentials["feed_url"]
    last_guids = cursor["last_item_guids"] || []
    last_date = cursor["last_item_date"]

    case fetch_feed(feed_url, credentials) do
      {:ok, feed} ->
        items =
          feed.entries
          |> filter_new_items(last_guids, last_date)
          |> Enum.map(&parse_item(&1, feed))

        new_cursor = %{
          "last_item_date" => newest_date(items),
          "last_item_guids" => Enum.take(Enum.map(items, & &1[:guid]), 100)
        }

        {:ok, items, new_cursor}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def to_entry(item, user_id) do
    %{
      user_id: user_id,
      title: item[:title] || "Untitled",
      entry_type: determine_entry_type(item),
      source_type: "rss_feed",
      content_created_at: item[:published_at],
      content: item[:content] || item[:summary],
      metadata: source_metadata(item)
    }
  end

  @impl true
  def extract_assets(item) do
    enclosures = item[:enclosures] || []

    Enum.map(enclosures, fn enc ->
      %{
        url: enc[:url],
        mime_type: enc[:type],
        filename: extract_filename(enc[:url]),
        size_bytes: enc[:length]
      }
    end)
  end

  @impl true
  def extract_tags(item) do
    feed_tag = if item[:feed_title], do: ["feed:#{normalize_tag(item[:feed_title])}"], else: []
    categories = item[:categories] || []
    feed_tag ++ Enum.map(categories, &normalize_tag/1)
  end

  @impl true
  def source_metadata(item) do
    %{
      "rss" => %{
        "guid" => item[:guid],
        "link" => item[:link],
        "feed_url" => item[:feed_url],
        "feed_title" => item[:feed_title],
        "author" => item[:author],
        "published_at" => item[:published_at] && DateTime.to_iso8601(item[:published_at])
      }
    }
  end

  @impl true
  def convert_content(item) do
    content = item[:content] || item[:summary] || ""

    # RSS content is typically HTML, convert to markdown
    case Onelist.Feeder.Converters.HTMLConverter.convert(content, []) do
      {:ok, markdown} -> {:ok, markdown}
      {:error, _} -> {:ok, content}  # Fallback to raw content
    end
  end

  # ============================================
  # PRIVATE FUNCTIONS
  # ============================================

  defp valid_url?(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and not is_nil(uri.host)
  end

  # Add feed metadata to each parsed item
  defp parse_item(item, feed) do
    item
    |> Map.put(:feed_url, feed[:url])
    |> Map.put(:feed_title, feed[:title])
  end

  defp fetch_feed(url, credentials) do
    headers = build_headers(credentials)

    case Req.get(url, headers: headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        parse_feed(body, url)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  rescue
    e -> {:error, {:exception, Exception.message(e)}}
  end

  defp build_headers(credentials) do
    base = [
      {"User-Agent", "Onelist/1.0 (Feed Fetcher; +https://onelist.my)"},
      {"Accept", "application/rss+xml, application/atom+xml, application/xml, text/xml"}
    ]

    case credentials["basic_auth"] do
      %{"username" => user, "password" => pass} ->
        auth = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{auth}"} | base]

      _ ->
        base
    end
  end

  defp parse_feed(body, url) do
    # Use a simple XML parser for RSS/Atom
    # In production, you'd use a library like FeederEx or FastRSS
    case parse_rss_or_atom(body) do
      {:ok, feed} ->
        {:ok, Map.put(feed, :url, url)}

      {:error, reason} ->
        {:error, {:parse_failed, reason}}
    end
  end

  # Simplified RSS/Atom parsing - in production use a proper library
  defp parse_rss_or_atom(body) do
    try do
      {:ok, doc} = Floki.parse_document(body)

      cond do
        # RSS 2.0
        Floki.find(doc, "rss channel") != [] ->
          parse_rss_2(doc)

        # Atom
        Floki.find(doc, "feed") != [] ->
          parse_atom(doc)

        # RSS 1.0 (RDF)
        Floki.find(doc, "rdf|RDF") != [] ->
          parse_rss_1(doc)

        true ->
          {:error, :unknown_feed_format}
      end
    rescue
      e -> {:error, {:xml_parse_error, Exception.message(e)}}
    end
  end

  defp parse_rss_2(doc) do
    channel = Floki.find(doc, "rss channel") |> List.first()

    feed = %{
      title: text(channel, "title"),
      description: text(channel, "description"),
      link: text(channel, "link"),
      entries: Floki.find(channel, "item") |> Enum.map(&parse_rss_item/1)
    }

    {:ok, feed}
  end

  defp parse_rss_item(item) do
    %{
      title: text(item, "title"),
      link: text(item, "link"),
      guid: text(item, "guid") || text(item, "link"),
      summary: text(item, "description"),
      content: text(item, "content|encoded") || text(item, "description"),
      author: text(item, "author") || text(item, "dc|creator"),
      published_at: parse_date(text(item, "pubDate")),
      categories: Floki.find(item, "category") |> Enum.map(&Floki.text/1),
      enclosures: parse_enclosures(item)
    }
  end

  defp parse_atom(doc) do
    feed_elem = Floki.find(doc, "feed") |> List.first()

    feed = %{
      title: text(feed_elem, "title"),
      description: text(feed_elem, "subtitle"),
      link: attr(feed_elem, "link[rel=alternate]", "href") || attr(feed_elem, "link", "href"),
      entries: Floki.find(feed_elem, "entry") |> Enum.map(&parse_atom_entry/1)
    }

    {:ok, feed}
  end

  defp parse_atom_entry(entry) do
    %{
      title: text(entry, "title"),
      link: attr(entry, "link[rel=alternate]", "href") || attr(entry, "link", "href"),
      guid: text(entry, "id"),
      summary: text(entry, "summary"),
      content: text(entry, "content") || text(entry, "summary"),
      author: text(entry, "author name"),
      published_at: parse_date(text(entry, "published") || text(entry, "updated")),
      categories: Floki.find(entry, "category") |> Enum.map(&attr_direct(&1, "term")),
      enclosures: []  # Atom uses link[rel=enclosure]
    }
  end

  defp parse_rss_1(doc) do
    # RSS 1.0 / RDF parsing
    channel = Floki.find(doc, "channel") |> List.first()

    feed = %{
      title: text(channel, "title"),
      description: text(channel, "description"),
      link: text(channel, "link"),
      entries: Floki.find(doc, "item") |> Enum.map(&parse_rss_item/1)
    }

    {:ok, feed}
  end

  defp parse_enclosures(item) do
    Floki.find(item, "enclosure")
    |> Enum.map(fn enc ->
      %{
        url: attr_direct(enc, "url"),
        type: attr_direct(enc, "type"),
        length: attr_direct(enc, "length") |> parse_int()
      }
    end)
  end

  defp text(elem, selector) when is_binary(selector) do
    case Floki.find(elem, selector) do
      [] -> nil
      [found | _] -> Floki.text(found) |> String.trim() |> nilify_empty()
    end
  end

  defp attr(elem, selector, attribute) do
    case Floki.find(elem, selector) do
      [] -> nil
      [found | _] -> attr_direct(found, attribute)
    end
  end

  defp attr_direct(elem, attribute) do
    case Floki.attribute(elem, attribute) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil
  defp parse_date(str) when is_binary(str) do
    # Try common date formats
    with {:error, _} <- DateTime.from_iso8601(str),
         {:error, _} <- parse_rfc822(str) do
      nil
    else
      {:ok, dt, _} -> dt
      {:ok, dt} -> dt
    end
  end

  defp parse_rfc822(str) do
    # RFC 822 date format common in RSS
    # Example: "Mon, 15 Jan 2024 10:30:00 GMT"
    case Timex.parse(str, "{RFC822}") do
      {:ok, dt} -> {:ok, DateTime.from_naive!(dt, "Etc/UTC")}
      {:error, _} ->
        # Try without timezone
        case Timex.parse(str, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s}") do
          {:ok, dt} -> {:ok, DateTime.from_naive!(dt, "Etc/UTC")}
          error -> error
        end
    end
  rescue
    _ -> {:error, :invalid_date}
  end

  defp parse_int(nil), do: nil
  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp nilify_empty(""), do: nil
  defp nilify_empty(str), do: str

  defp filter_new_items(items, last_guids, last_date) do
    items
    |> Enum.reject(fn item -> item[:guid] in last_guids end)
    |> Enum.filter(fn item ->
      case {item[:published_at], last_date} do
        {nil, _} -> true
        {_, nil} -> true
        {pub, last} ->
          case DateTime.from_iso8601(last) do
            {:ok, last_dt, _} -> DateTime.compare(pub, last_dt) == :gt
            _ -> true
          end
      end
    end)
  end

  defp newest_date([]), do: nil
  defp newest_date(items) do
    items
    |> Enum.map(& &1[:published_at])
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
    |> case do
      nil -> nil
      dt -> DateTime.to_iso8601(dt)
    end
  end

  defp determine_entry_type(item) do
    enclosures = item[:enclosures] || []

    cond do
      Enum.any?(enclosures, &String.starts_with?(&1[:type] || "", "audio/")) ->
        "podcast"

      Enum.any?(enclosures, &String.starts_with?(&1[:type] || "", "video/")) ->
        "video"

      true ->
        "article"
    end
  end

  defp extract_filename(nil), do: "attachment"
  defp extract_filename(url) when is_binary(url) do
    uri = URI.parse(url)
    Path.basename(uri.path || "attachment")
  end

  defp normalize_tag(nil), do: ""
  defp normalize_tag(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
