defmodule Onelist.WebCapture.Extractors.Readability do
  @moduledoc """
  Readability-style content extraction.

  Extracts the main content from web pages by:
  1. Removing boilerplate (nav, header, footer, ads, etc.)
  2. Scoring content blocks by text density
  3. Selecting the highest-scoring content area

  Based on Mozilla's Readability.js algorithm.
  """

  @type content :: %{
          title: String.t() | nil,
          text: String.t(),
          html: String.t(),
          excerpt: String.t() | nil
        }

  # Elements to remove completely
  @noise_elements ~w(
    script style noscript iframe form input button
    nav header footer aside
    [role="navigation"] [role="banner"] [role="contentinfo"]
    .sidebar .navigation .nav .menu .footer .header
    .comments .comment .advertisement .ad .ads .promo
    .social-share .share-buttons .related-posts
    .newsletter .subscribe
  )

  # Elements likely to contain main content
  @content_selectors [
    "article",
    "[role='main']",
    "main",
    ".post-content",
    ".article-content",
    ".entry-content",
    ".content",
    ".post",
    ".article",
    "#content",
    "#article",
    "#main"
  ]

  # Negative score indicators in class/id
  @negative_patterns ~r/comment|footer|header|nav|sidebar|widget|ad|advertisement|promo|related|share|social|menu/i

  # Positive score indicators in class/id
  @positive_patterns ~r/article|content|entry|main|post|text|body|story|blog/i

  @doc """
  Extract main content from a Floki document.

  ## Examples

      {:ok, document} = Floki.parse_document(html)
      {:ok, content} = Readability.extract(document)
  """
  @spec extract(Floki.html_tree()) :: {:ok, content()} | {:error, term()}
  def extract(document) do
    # First, try to find content using semantic selectors
    content_element = find_content_element(document)

    # Clean up the document
    cleaned = clean_document(content_element || document)

    # Score and select best content block if no semantic element found
    best_block =
      if content_element do
        content_element
      else
        score_and_select(cleaned)
      end

    if best_block do
      text = extract_text(best_block)
      html = Floki.raw_html(best_block)
      title = extract_title(document)

      {:ok,
       %{
         title: title,
         text: text,
         html: html,
         excerpt: String.slice(text, 0, 200) |> String.trim()
       }}
    else
      {:error, :no_content_found}
    end
  rescue
    e -> {:error, {:extraction_failed, Exception.message(e)}}
  end

  @doc """
  Extract just the text content from a document.
  """
  @spec extract_text(Floki.html_tree()) :: String.t()
  def extract_text(document) do
    document
    |> Floki.text(sep: "\n\n")
    |> normalize_whitespace()
  end

  # ============================================
  # CONTENT DETECTION
  # ============================================

  defp find_content_element(document) do
    @content_selectors
    |> Enum.find_value(fn selector ->
      case Floki.find(document, selector) do
        [elem | _] ->
          # Verify it has enough content
          text = Floki.text(elem)
          if String.length(text) > 200, do: elem, else: nil

        [] ->
          nil
      end
    end)
  end

  defp score_and_select(document) do
    # Find all paragraph-containing elements
    candidates =
      document
      |> Floki.find("div, section, article, main")
      |> Enum.map(fn elem -> {elem, score_element(elem)} end)
      |> Enum.filter(fn {_elem, score} -> score > 0 end)
      |> Enum.sort_by(fn {_elem, score} -> score end, :desc)

    case candidates do
      [{elem, _score} | _] ->
        elem

      [] ->
        # Fallback: return body content
        case Floki.find(document, "body") do
          [body | _] -> body
          [] -> nil
        end
    end
  end

  defp score_element(element) do
    base_score = 0

    # Score based on paragraph count and text length
    paragraphs = Floki.find(element, "p")
    para_count = length(paragraphs)
    text = Floki.text(element)
    text_length = String.length(text)

    # Calculate text density
    html_length = max(String.length(Floki.raw_html(element)), 1)
    text_density = text_length / html_length

    base_score = base_score + para_count * 3
    base_score = base_score + min(div(text_length, 100), 30)
    base_score = base_score + round(text_density * 10)

    # Score based on class/id
    class_id = get_class_id(element)

    base_score =
      if Regex.match?(@positive_patterns, class_id) do
        base_score + 25
      else
        base_score
      end

    base_score =
      if Regex.match?(@negative_patterns, class_id) do
        base_score - 50
      else
        base_score
      end

    # Bonus for links ratio (low link density = good)
    links = Floki.find(element, "a")
    link_text = links |> Enum.map(&Floki.text/1) |> Enum.join("")
    link_density = String.length(link_text) / max(text_length, 1)

    base_score =
      if link_density < 0.3 do
        base_score + 10
      else
        base_score - round(link_density * 20)
      end

    base_score
  end

  # ============================================
  # DOCUMENT CLEANING
  # ============================================

  defp clean_document(document) do
    # Remove noise elements
    @noise_elements
    |> Enum.reduce(document, fn selector, doc ->
      Floki.filter_out(doc, selector)
    end)
  end

  # ============================================
  # HELPERS
  # ============================================

  defp extract_title(document) do
    # Try multiple sources for title
    [
      fn doc -> get_element_text(doc, "h1.entry-title") end,
      fn doc -> get_element_text(doc, "h1.post-title") end,
      fn doc -> get_element_text(doc, "article h1") end,
      fn doc -> get_element_text(doc, "h1") end,
      fn doc -> get_element_text(doc, "title") end
    ]
    |> Enum.find_value(fn f -> f.(document) end)
  end

  defp get_element_text(document, selector) do
    case Floki.find(document, selector) do
      [elem | _] ->
        text = Floki.text(elem) |> String.trim()
        if text != "", do: text, else: nil

      [] ->
        nil
    end
  end

  defp get_class_id(element) do
    {_tag, attrs, _children} = element

    class =
      attrs
      |> Enum.find_value("", fn
        {"class", val} -> val
        _ -> nil
      end)

    id =
      attrs
      |> Enum.find_value("", fn
        {"id", val} -> val
        _ -> nil
      end)

    "#{class} #{id}"
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.replace(~r/[ \t]+/, " ")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n")
    |> String.trim()
  end
end
