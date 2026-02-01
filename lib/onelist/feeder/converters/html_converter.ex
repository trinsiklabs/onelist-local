defmodule Onelist.Feeder.Converters.HTMLConverter do
  @moduledoc """
  Converts HTML content to Markdown.

  Handles common HTML elements including:
  - Headings (h1-h6)
  - Paragraphs
  - Lists (ordered and unordered)
  - Links and images
  - Code blocks and inline code
  - Blockquotes
  - Bold, italic, strikethrough

  Also strips unsafe content (script, style tags) and cleans up whitespace.
  """

  @behaviour Onelist.Feeder.Converters.Converter

  @impl true
  def supported_formats, do: ["html", "text/html"]

  @impl true
  def convert(nil, _opts), do: {:error, :nil_content}
  def convert("", _opts), do: {:ok, ""}
  def convert(content, opts) when is_binary(content) do
    try do
      markdown =
        content
        |> sanitize_html()
        |> parse_and_convert(opts)
        |> clean_whitespace()

      {:ok, markdown}
    rescue
      e -> {:error, {:conversion_failed, Exception.message(e)}}
    end
  end
  def convert(_, _opts), do: {:error, :invalid_content_type}

  @impl true
  def extract_embedded_assets(content) when is_binary(content) do
    case Floki.parse_document(content) do
      {:ok, doc} ->
        images = extract_images(doc)
        links = extract_downloadable_links(doc)
        images ++ links

      _ ->
        []
    end
  end
  def extract_embedded_assets(_), do: []

  # ============================================
  # PRIVATE FUNCTIONS
  # ============================================

  defp sanitize_html(html) do
    # Remove dangerous and non-content elements
    html
    |> String.replace(~r/<script[^>]*>.*?<\/script>/is, "")
    |> String.replace(~r/<style[^>]*>.*?<\/style>/is, "")
    |> String.replace(~r/<noscript[^>]*>.*?<\/noscript>/is, "")
    |> String.replace(~r/<!--.*?-->/s, "")
  end

  defp parse_and_convert(html, opts) do
    case Floki.parse_document(html) do
      {:ok, doc} ->
        doc
        |> convert_node(opts)
        |> List.flatten()
        |> Enum.join("")

      {:error, _} ->
        # Fallback: strip all tags
        html |> Floki.text()
    end
  end

  defp convert_node(nodes, opts) when is_list(nodes) do
    Enum.map(nodes, &convert_node(&1, opts))
  end

  defp convert_node(text, _opts) when is_binary(text) do
    text
  end

  defp convert_node({tag, attrs, children}, opts) do
    case String.downcase(to_string(tag)) do
      # Headings
      "h1" -> ["\n\n# ", convert_node(children, opts), "\n\n"]
      "h2" -> ["\n\n## ", convert_node(children, opts), "\n\n"]
      "h3" -> ["\n\n### ", convert_node(children, opts), "\n\n"]
      "h4" -> ["\n\n#### ", convert_node(children, opts), "\n\n"]
      "h5" -> ["\n\n##### ", convert_node(children, opts), "\n\n"]
      "h6" -> ["\n\n###### ", convert_node(children, opts), "\n\n"]

      # Paragraphs and divs
      "p" -> ["\n\n", convert_node(children, opts), "\n\n"]
      "div" -> ["\n", convert_node(children, opts), "\n"]
      "br" -> ["\n"]

      # Text formatting
      "strong" -> ["**", convert_node(children, opts), "**"]
      "b" -> ["**", convert_node(children, opts), "**"]
      "em" -> ["*", convert_node(children, opts), "*"]
      "i" -> ["*", convert_node(children, opts), "*"]
      "s" -> ["~~", convert_node(children, opts), "~~"]
      "del" -> ["~~", convert_node(children, opts), "~~"]
      "strike" -> ["~~", convert_node(children, opts), "~~"]
      "u" -> convert_node(children, opts)  # No markdown equivalent

      # Code
      "code" ->
        content = Floki.text({tag, attrs, children})
        if String.contains?(content, "\n") do
          ["\n```\n", content, "\n```\n"]
        else
          ["`", content, "`"]
        end

      "pre" ->
        code_content = extract_code_content({tag, attrs, children})
        ["\n```\n", code_content, "\n```\n"]

      # Links and images
      "a" ->
        href = get_attr(attrs, "href")
        text = convert_node(children, opts) |> flatten_to_string()
        if href do
          ["[", text, "](", href, ")"]
        else
          [text]
        end

      "img" ->
        src = get_attr(attrs, "src")
        alt = get_attr(attrs, "alt") || ""
        if src do
          ["![", alt, "](", src, ")"]
        else
          []
        end

      # Lists
      "ul" -> ["\n", convert_list_items(children, "-", opts), "\n"]
      "ol" -> ["\n", convert_ordered_list(children, opts), "\n"]
      "li" -> convert_node(children, opts)

      # Blockquote
      "blockquote" ->
        content =
          convert_node(children, opts)
          |> flatten_to_string()
          |> String.split("\n")
          |> Enum.map(&("> " <> &1))
          |> Enum.join("\n")
        ["\n", content, "\n"]

      # Horizontal rule
      "hr" -> ["\n\n---\n\n"]

      # Tables (simplified)
      "table" -> convert_table({tag, attrs, children}, opts)
      "tr" -> convert_node(children, opts)
      "th" -> [" ", convert_node(children, opts), " |"]
      "td" -> [" ", convert_node(children, opts), " |"]

      # Skip these elements entirely
      "script" -> []
      "style" -> []
      "head" -> []
      "meta" -> []
      "link" -> []
      "nav" -> []
      "footer" -> []
      "aside" -> []

      # Default: just process children
      _ -> convert_node(children, opts)
    end
  end

  defp convert_list_items(items, marker, opts) do
    items
    |> Enum.filter(&is_tuple/1)
    |> Enum.filter(fn {tag, _, _} -> String.downcase(to_string(tag)) == "li" end)
    |> Enum.map(fn item ->
      content = convert_node(item, opts) |> flatten_to_string() |> String.trim()
      "#{marker} #{content}\n"
    end)
  end

  defp convert_ordered_list(items, opts) do
    items
    |> Enum.filter(&is_tuple/1)
    |> Enum.filter(fn {tag, _, _} -> String.downcase(to_string(tag)) == "li" end)
    |> Enum.with_index(1)
    |> Enum.map(fn {item, index} ->
      content = convert_node(item, opts) |> flatten_to_string() |> String.trim()
      "#{index}. #{content}\n"
    end)
  end

  defp convert_table({_tag, _attrs, children}, opts) do
    rows =
      children
      |> find_elements("tr")
      |> Enum.map(fn row ->
        cells = find_elements(elem(row, 2), ~w(th td))
        "|" <> Enum.map_join(cells, "", fn cell ->
          content = convert_node(cell, opts) |> flatten_to_string() |> String.trim()
          " #{content} |"
        end)
      end)

    case rows do
      [] -> []
      [header | rest] ->
        # Count columns from header
        col_count = String.split(header, "|") |> length() |> Kernel.-(2)
        separator = "|" <> String.duplicate(" --- |", max(col_count, 1))
        ["\n", header, "\n", separator, "\n", Enum.join(rest, "\n"), "\n"]
    end
  end

  defp find_elements(nodes, tags) when is_list(tags) do
    nodes
    |> Enum.filter(&is_tuple/1)
    |> Enum.filter(fn {tag, _, _} -> String.downcase(to_string(tag)) in tags end)
  end
  defp find_elements(nodes, tag), do: find_elements(nodes, [tag])

  defp extract_code_content({_, _, children}) do
    children
    |> Enum.map(fn
      text when is_binary(text) -> text
      {_tag, _attrs, inner} -> Floki.text({nil, [], inner})
    end)
    |> Enum.join("")
  end

  defp get_attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      _ -> nil
    end
  end

  defp flatten_to_string(list) when is_list(list) do
    list |> List.flatten() |> Enum.join("")
  end
  defp flatten_to_string(str) when is_binary(str), do: str

  defp clean_whitespace(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.trim()
  end

  defp extract_images(doc) do
    Floki.find(doc, "img")
    |> Enum.map(fn {"img", attrs, _} ->
      %{
        url: get_attr(attrs, "src"),
        alt: get_attr(attrs, "alt"),
        type: :image
      }
    end)
    |> Enum.filter(& &1.url)
  end

  defp extract_downloadable_links(doc) do
    Floki.find(doc, "a[href]")
    |> Enum.filter(fn {"a", attrs, _} ->
      href = get_attr(attrs, "href") || ""
      String.match?(href, ~r/\.(pdf|doc|docx|xls|xlsx|ppt|pptx|zip|rar)$/i)
    end)
    |> Enum.map(fn {"a", attrs, children} ->
      %{
        url: get_attr(attrs, "href"),
        text: Floki.text({"a", attrs, children}),
        type: :document
      }
    end)
  end
end
