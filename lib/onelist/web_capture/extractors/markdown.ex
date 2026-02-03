defmodule Onelist.WebCapture.Extractors.Markdown do
  @moduledoc """
  Converts HTML content to Markdown.

  Uses a pure Elixir implementation with support for:
  - Headers (h1-h6)
  - Paragraphs
  - Lists (ordered and unordered)
  - Links and images
  - Bold, italic, code
  - Blockquotes
  - Code blocks
  - Tables (basic)
  """

  @doc """
  Convert HTML string to Markdown.

  ## Examples

      {:ok, markdown} = Markdown.from_html("<h1>Hello</h1><p>World</p>")
      # => "# Hello\n\nWorld"
  """
  @spec from_html(String.t()) :: {:ok, String.t()} | {:error, term()}
  def from_html(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        markdown =
          document
          |> convert_tree()
          |> normalize_output()

        {:ok, markdown}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  rescue
    e -> {:error, {:conversion_failed, Exception.message(e)}}
  end

  def from_html(_), do: {:error, :invalid_input}

  @doc """
  Convert a Floki document tree to Markdown.
  """
  @spec from_document(Floki.html_tree()) :: {:ok, String.t()} | {:error, term()}
  def from_document(document) do
    markdown =
      document
      |> convert_tree()
      |> normalize_output()

    {:ok, markdown}
  rescue
    e -> {:error, {:conversion_failed, Exception.message(e)}}
  end

  # ============================================
  # TREE CONVERSION
  # ============================================

  defp convert_tree(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&convert_node/1)
    |> Enum.join("")
  end

  defp convert_tree(node), do: convert_node(node)

  defp convert_node(text) when is_binary(text) do
    # Preserve text but escape markdown special chars in inline context
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("*", "\\*")
    |> String.replace("_", "\\_")
    |> String.replace("`", "\\`")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
  end

  defp convert_node({:comment, _}), do: ""

  defp convert_node({"script", _, _}), do: ""
  defp convert_node({"style", _, _}), do: ""
  defp convert_node({"noscript", _, _}), do: ""

  # Headers
  defp convert_node({"h1", _, children}) do
    "# #{convert_inline(children)}\n\n"
  end

  defp convert_node({"h2", _, children}) do
    "## #{convert_inline(children)}\n\n"
  end

  defp convert_node({"h3", _, children}) do
    "### #{convert_inline(children)}\n\n"
  end

  defp convert_node({"h4", _, children}) do
    "#### #{convert_inline(children)}\n\n"
  end

  defp convert_node({"h5", _, children}) do
    "##### #{convert_inline(children)}\n\n"
  end

  defp convert_node({"h6", _, children}) do
    "###### #{convert_inline(children)}\n\n"
  end

  # Paragraph
  defp convert_node({"p", _, children}) do
    content = convert_inline(children) |> String.trim()
    if content != "", do: "#{content}\n\n", else: ""
  end

  # Line break
  defp convert_node({"br", _, _}), do: "  \n"

  # Horizontal rule
  defp convert_node({"hr", _, _}), do: "\n---\n\n"

  # Bold
  defp convert_node({"strong", _, children}), do: "**#{convert_inline(children)}**"
  defp convert_node({"b", _, children}), do: "**#{convert_inline(children)}**"

  # Italic
  defp convert_node({"em", _, children}), do: "*#{convert_inline(children)}*"
  defp convert_node({"i", _, children}), do: "*#{convert_inline(children)}*"

  # Code inline
  defp convert_node({"code", _, children}) do
    code = children |> get_text() |> String.trim()
    "`#{code}`"
  end

  # Code block
  defp convert_node({"pre", _, children}) do
    code = extract_code_content(children)
    lang = extract_code_language(children)
    "\n```#{lang}\n#{code}\n```\n\n"
  end

  # Links
  defp convert_node({"a", attrs, children}) do
    href = get_attr(attrs, "href") || ""
    title = get_attr(attrs, "title")
    text = convert_inline(children)

    if title do
      "[#{text}](#{href} \"#{title}\")"
    else
      "[#{text}](#{href})"
    end
  end

  # Images
  defp convert_node({"img", attrs, _}) do
    src = get_attr(attrs, "src") || ""
    alt = get_attr(attrs, "alt") || ""
    title = get_attr(attrs, "title")

    if title do
      "![#{alt}](#{src} \"#{title}\")"
    else
      "![#{alt}](#{src})"
    end
  end

  # Unordered list
  defp convert_node({"ul", _, children}) do
    items =
      children
      |> Enum.filter(fn
        {"li", _, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {"li", _, content} ->
        text = convert_inline(content) |> String.trim()
        "- #{text}"
      end)
      |> Enum.join("\n")

    "\n#{items}\n\n"
  end

  # Ordered list
  defp convert_node({"ol", _, children}) do
    items =
      children
      |> Enum.filter(fn
        {"li", _, _} -> true
        _ -> false
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{"li", _, content}, idx} ->
        text = convert_inline(content) |> String.trim()
        "#{idx}. #{text}"
      end)
      |> Enum.join("\n")

    "\n#{items}\n\n"
  end

  # Blockquote
  defp convert_node({"blockquote", _, children}) do
    content =
      convert_tree(children)
      |> String.split("\n")
      |> Enum.map(fn line ->
        if String.trim(line) == "", do: ">", else: "> #{line}"
      end)
      |> Enum.join("\n")

    "\n#{content}\n\n"
  end

  # Table
  defp convert_node({"table", _, children}) do
    rows = find_table_rows(children)

    case rows do
      [] ->
        ""

      [header | body] ->
        header_cells = extract_cells(header)
        header_row = "| #{Enum.join(header_cells, " | ")} |"
        separator = "| #{header_cells |> Enum.map(fn _ -> "---" end) |> Enum.join(" | ")} |"

        body_rows =
          body
          |> Enum.map(fn row ->
            cells = extract_cells(row)
            "| #{Enum.join(cells, " | ")} |"
          end)
          |> Enum.join("\n")

        "\n#{header_row}\n#{separator}\n#{body_rows}\n\n"
    end
  end

  # Div, section, article - pass through
  defp convert_node({tag, _, children}) when tag in ~w(div section article main aside nav) do
    convert_tree(children)
  end

  # Span - inline pass through
  defp convert_node({"span", _, children}), do: convert_inline(children)

  # Figure with figcaption
  defp convert_node({"figure", _, children}) do
    img =
      Enum.find_value(children, fn
        {"img", _, _} = node -> convert_node(node)
        _ -> nil
      end)

    caption =
      Enum.find_value(children, fn
        {"figcaption", _, content} -> convert_inline(content)
        _ -> nil
      end)

    if img do
      if caption do
        "#{img}\n*#{caption}*\n\n"
      else
        "#{img}\n\n"
      end
    else
      convert_tree(children)
    end
  end

  # Default: process children
  defp convert_node({_tag, _attrs, children}) do
    convert_tree(children)
  end

  defp convert_node(_), do: ""

  # ============================================
  # INLINE CONVERSION
  # ============================================

  defp convert_inline(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&convert_inline_node/1)
    |> Enum.join("")
  end

  defp convert_inline(node), do: convert_inline_node(node)

  defp convert_inline_node(text) when is_binary(text), do: text
  defp convert_inline_node({"strong", _, children}), do: "**#{convert_inline(children)}**"
  defp convert_inline_node({"b", _, children}), do: "**#{convert_inline(children)}**"
  defp convert_inline_node({"em", _, children}), do: "*#{convert_inline(children)}*"
  defp convert_inline_node({"i", _, children}), do: "*#{convert_inline(children)}*"
  defp convert_inline_node({"code", _, children}), do: "`#{get_text(children)}`"

  defp convert_inline_node({"a", attrs, children}) do
    href = get_attr(attrs, "href") || ""
    title = get_attr(attrs, "title")
    text = convert_inline(children)

    if title do
      "[#{text}](#{href} \"#{title}\")"
    else
      "[#{text}](#{href})"
    end
  end

  defp convert_inline_node({"br", _, _}), do: "  \n"
  defp convert_inline_node({"span", _, children}), do: convert_inline(children)
  defp convert_inline_node({_tag, _, children}), do: convert_inline(children)
  defp convert_inline_node(_), do: ""

  # ============================================
  # HELPERS
  # ============================================

  defp get_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, value} -> value
      _ -> nil
    end)
  end

  defp get_text(nodes) when is_list(nodes) do
    nodes
    |> Enum.map(&get_text/1)
    |> Enum.join("")
  end

  defp get_text(text) when is_binary(text), do: text
  defp get_text({_tag, _attrs, children}), do: get_text(children)
  defp get_text(_), do: ""

  defp extract_code_content(children) do
    case children do
      [{"code", _, code_children}] -> get_text(code_children)
      _ -> get_text(children)
    end
    |> String.trim()
  end

  defp extract_code_language(children) do
    case children do
      [{"code", attrs, _}] ->
        class = get_attr(attrs, "class") || ""

        case Regex.run(~r/language-(\w+)/, class) do
          [_, lang] -> lang
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp find_table_rows(children) do
    tbody =
      Enum.find_value(children, fn
        {"tbody", _, rows} -> rows
        _ -> nil
      end)

    thead =
      Enum.find_value(children, fn
        {"thead", _, rows} -> rows
        _ -> nil
      end)

    all_rows = (thead || []) ++ (tbody || children)

    all_rows
    |> Enum.filter(fn
      {"tr", _, _} -> true
      _ -> false
    end)
  end

  defp extract_cells({"tr", _, children}) do
    children
    |> Enum.filter(fn
      {"td", _, _} -> true
      {"th", _, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {_tag, _, content} ->
      convert_inline(content) |> String.trim() |> String.replace("|", "\\|")
    end)
  end

  defp normalize_output(markdown) do
    markdown
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end
end
