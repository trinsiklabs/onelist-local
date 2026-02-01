defmodule Onelist.WebCapture.Tiers.Tier2IntelligentBrowser do
  @moduledoc """
  Tier 2: Intelligent browser-based capture using Playwright.

  Best for:
  - JavaScript-heavy sites (SPAs)
  - Sites with soft anti-bot measures
  - Dynamic content that requires interaction
  - Login-protected content (with session cookies)

  **NOTE**: This tier requires a running browser service.
  Configure via `:browser_use_url` in config.

  ## Setup

  The browser service can be run as a sidecar container:

      # docker-compose.yml
      browser_use:
        image: mcr.microsoft.com/playwright:v1.40.0-focal
        ports:
          - "8000:8000"

  Configure the URL:

      config :onelist, :browser_use_url, "http://localhost:8000"
  """

  alias Onelist.WebCapture.Extractors.{Metadata, Markdown}

  require Logger

  @default_timeout_ms 35_000

  @type capture_result :: %{
          url: String.t(),
          final_url: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content: String.t() | nil,
          html: String.t() | nil,
          markdown: String.t() | nil,
          metadata: map(),
          screenshots: [String.t()]
        }

  @doc """
  Capture content from a URL using browser automation.

  ## Options

  - `:timeout_ms` - Request timeout (default: 35_000)
  - `:extract_markdown` - Convert to markdown (default: true)
  - `:wait_for_selector` - CSS selector to wait for before capture
  - `:take_screenshot` - Whether to capture screenshots (default: false)
  """
  @spec capture(String.t(), keyword()) :: {:ok, capture_result()} | {:error, atom()}
  def capture(url, opts \\ []) do
    service_url = get_service_url()

    if is_nil(service_url) do
      {:error, :browser_service_not_configured}
    else
      do_capture(url, service_url, opts)
    end
  end

  @doc """
  Check if the browser service is available and healthy.
  """
  @spec available?() :: boolean()
  def available? do
    case get_service_url() do
      nil -> false
      url -> health_check(url)
    end
  end

  # ============================================
  # CAPTURE IMPLEMENTATION
  # ============================================

  defp do_capture(url, service_url, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    extract_markdown = Keyword.get(opts, :extract_markdown, true)

    body = %{
      url: url,
      extract_content: true,
      wait_for_selector: Keyword.get(opts, :wait_for_selector),
      take_screenshot: Keyword.get(opts, :take_screenshot, false),
      timeout_ms: timeout_ms
    }

    case Req.post("#{service_url}/capture", json: body, receive_timeout: timeout_ms + 5_000) do
      {:ok, %{status: 200, body: response}} when is_map(response) ->
        build_result(url, response, extract_markdown)

      {:ok, %{status: 408}} ->
        {:error, :timeout}

      {:ok, %{status: 403}} ->
        {:error, :blocked}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      {:ok, %{status: status, body: body}} ->
        error_detail = if is_map(body), do: body["detail"], else: inspect(body)
        Logger.warning("Browser capture failed with status #{status}: #{error_detail}")
        {:error, {:browser_error, status, error_detail}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %Req.TransportError{reason: :econnrefused}} ->
        {:error, :browser_service_unavailable}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp build_result(original_url, response, extract_markdown) do
    html = response["html"] || response["content"]

    markdown = if extract_markdown and html do
      case Markdown.from_html(html) do
        {:ok, md} -> md
        {:error, _} -> nil
      end
    else
      nil
    end

    # Try to extract metadata from the HTML if available
    metadata = if html do
      case Floki.parse_document(html) do
        {:ok, doc} ->
          case Metadata.extract(doc, response["final_url"] || original_url) do
            {:ok, meta} -> meta
            {:error, _} -> %{}
          end
        _ -> %{}
      end
    else
      %{}
    end

    {:ok, %{
      url: original_url,
      final_url: response["final_url"] || original_url,
      title: response["title"] || metadata[:title],
      description: metadata[:description],
      content: response["text"] || response["extracted_content"],
      html: html,
      markdown: markdown,
      metadata: metadata,
      screenshots: response["screenshots"] || []
    }}
  end

  # ============================================
  # HELPERS
  # ============================================

  defp get_service_url do
    Application.get_env(:onelist, :browser_use_url)
  end

  defp health_check(url) do
    case Req.get("#{url}/health", receive_timeout: 3_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
