defmodule Onelist.WebCapture.Tiers.Tier1SimpleFetch do
  @moduledoc """
  Tier 1: Simple HTTP fetch with Readability-style content extraction.

  Best for:
  - Static HTML pages
  - Blogs and articles
  - News sites without aggressive anti-bot measures
  - Documentation sites

  Limitations:
  - Cannot execute JavaScript
  - May be blocked by Cloudflare, CAPTCHAs
  - Cannot handle login-protected content
  """

  alias Onelist.WebCapture.Extractors.{Metadata, Readability, Markdown}

  require Logger

  @user_agents [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15"
  ]

  @retry_delays [500, 1_000, 2_000]
  @default_timeout_ms 30_000

  @type capture_result :: %{
          url: String.t(),
          final_url: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content: String.t() | nil,
          html: String.t() | nil,
          markdown: String.t() | nil,
          metadata: map(),
          word_count: non_neg_integer(),
          language: String.t() | nil
        }

  @doc """
  Capture content from a URL using HTTP fetch.

  ## Options

  - `:timeout_ms` - Request timeout (default: 30_000)
  - `:extract_markdown` - Convert to markdown (default: true)
  - `:follow_redirects` - Follow HTTP redirects (default: true)
  - `:max_redirects` - Maximum redirects to follow (default: 5)
  """
  @spec capture(String.t(), keyword()) :: {:ok, capture_result()} | {:error, atom()}
  def capture(url, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    extract_markdown = Keyword.get(opts, :extract_markdown, true)

    with {:ok, response} <- fetch_with_retry(url, timeout_ms),
         {:ok, document} <- parse_html(response.body),
         {:ok, metadata} <- Metadata.extract(document, response.final_url),
         {:ok, content} <- Readability.extract(document) do

      markdown = if extract_markdown do
        case Markdown.from_html(content.html) do
          {:ok, md} -> md
          {:error, _} -> nil
        end
      else
        nil
      end

      {:ok, %{
        url: url,
        final_url: response.final_url,
        title: metadata.title || content.title,
        description: metadata.description,
        author: metadata.author,
        published_at: metadata.published_at,
        site_name: metadata.site_name,
        image_url: metadata.image,
        content: content.text,
        html: content.html,
        markdown: markdown,
        word_count: count_words(content.text),
        language: detect_language(content.text),
        metadata: %{
          og: metadata.og,
          twitter: metadata.twitter,
          canonical_url: metadata.canonical_url
        }
      }}
    end
  end

  # ============================================
  # HTTP FETCHING
  # ============================================

  defp fetch_with_retry(url, timeout_ms, attempt \\ 0) do
    headers = build_headers()

    req_opts = [
      headers: headers,
      redirect: true,
      max_redirects: 5,
      receive_timeout: timeout_ms,
      connect_options: [timeout: timeout_ms]
    ]

    case Req.get(url, req_opts) do
      {:ok, %{status: 200, body: body} = response} ->
        final_url = get_final_url(response, url)
        {:ok, %{body: body, final_url: final_url, status: 200}}

      {:ok, %{status: status}} when status in [403, 429, 503] ->
        if attempt < length(@retry_delays) do
          delay = Enum.at(@retry_delays, attempt)
          Logger.debug("WebCapture: Got #{status}, retrying in #{delay}ms")
          Process.sleep(delay)
          fetch_with_retry(url, timeout_ms, attempt + 1)
        else
          classify_block_error(status)
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: 410}} ->
        {:error, :gone}

      {:ok, %{status: status}} when status >= 400 ->
        {:error, {:http_error, status}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: :nxdomain}} ->
        {:error, :dns_error}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, {:network_error, reason}}

      {:error, reason} ->
        if attempt < length(@retry_delays) do
          delay = Enum.at(@retry_delays, attempt)
          Process.sleep(delay)
          fetch_with_retry(url, timeout_ms, attempt + 1)
        else
          {:error, {:fetch_failed, reason}}
        end
    end
  end

  defp build_headers do
    [
      {"User-Agent", Enum.random(@user_agents)},
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8"},
      {"Accept-Language", "en-US,en;q=0.9"},
      {"Accept-Encoding", "gzip, deflate, br"},
      {"Connection", "keep-alive"},
      {"Upgrade-Insecure-Requests", "1"},
      {"Sec-Fetch-Dest", "document"},
      {"Sec-Fetch-Mode", "navigate"},
      {"Sec-Fetch-Site", "none"},
      {"Sec-Fetch-User", "?1"},
      {"Cache-Control", "max-age=0"}
    ]
  end

  defp get_final_url(%{request: %{url: url}}, _original), do: URI.to_string(url)
  defp get_final_url(_, original), do: original

  defp classify_block_error(403), do: {:error, :blocked}
  defp classify_block_error(429), do: {:error, :rate_limited}
  defp classify_block_error(503), do: {:error, :service_unavailable}
  defp classify_block_error(status), do: {:error, {:http_error, status}}

  # ============================================
  # HTML PARSING
  # ============================================

  defp parse_html(body) when is_binary(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        # Check for signs that JavaScript is required
        if requires_javascript?(document) do
          {:error, :javascript_required}
        else
          {:ok, document}
        end

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_html(_), do: {:error, :invalid_body}

  defp requires_javascript?(document) do
    # Check for common JS-required patterns
    noscript_warning = Floki.find(document, "noscript")
    |> Floki.text()
    |> String.downcase()
    |> String.contains?("javascript")

    # Check if body is mostly empty but has scripts
    body_text = Floki.find(document, "body") |> Floki.text() |> String.trim()
    script_count = Floki.find(document, "script") |> length()

    (noscript_warning and String.length(body_text) < 500) or
      (String.length(body_text) < 200 and script_count > 5)
  end

  # ============================================
  # HELPERS
  # ============================================

  defp count_words(nil), do: 0
  defp count_words(""), do: 0
  defp count_words(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp detect_language(nil), do: nil
  defp detect_language(text) when byte_size(text) < 100, do: nil
  defp detect_language(_text) do
    # Simple heuristic - could be enhanced with a proper library
    # For now, return nil and let downstream processing detect
    nil
  end
end
