defmodule Onelist.WebCapture do
  @moduledoc """
  Web Content Capture system for Onelist.

  Provides a tiered capture strategy for extracting content from web URLs:

  - **Tier 1 (Simple Fetch)**: Basic HTTP fetch with Readability extraction
    Best for: Static sites, articles, blogs
    
  - **Tier 2 (Intelligent Browser)**: Playwright-based for JS-heavy sites
    Best for: SPAs, dynamic content, soft-protected sites

  ## Usage

      # Capture a URL (auto-selects tier)
      {:ok, job} = Onelist.WebCapture.capture_url(user_id, "https://example.com/article")
      
      # Check capture status
      {:ok, status} = Onelist.WebCapture.get_status(job_id)

      # Force specific tier
      {:ok, job} = Onelist.WebCapture.capture_url(user_id, url, tier: :simple_fetch)

  ## Options

  - `:tier` - Force a specific tier (`:simple_fetch`, `:intelligent_browser`, `:auto`)
  - `:async` - Whether to process asynchronously via Oban (default: true)
  - `:callback_url` - URL to POST results to when complete
  - `:tags` - List of tags to apply to the created entry
  - `:extract_markdown` - Convert content to markdown (default: true)
  - `:timeout_ms` - Request timeout in milliseconds (default: 30_000)
  """

  alias Onelist.WebCapture.TierSelector
  alias Onelist.WebCapture.Tiers.{Tier1SimpleFetch, Tier2IntelligentBrowser}
  alias Onelist.WebCapture.Workers.CaptureWorker
  alias Onelist.Repo

  require Logger

  @type capture_opts :: [
          tier: :auto | :simple_fetch | :intelligent_browser,
          async: boolean(),
          callback_url: String.t() | nil,
          tags: [String.t()],
          extract_markdown: boolean(),
          timeout_ms: non_neg_integer()
        ]

  @type capture_result :: %{
          url: String.t(),
          final_url: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          content: String.t() | nil,
          markdown: String.t() | nil,
          metadata: map(),
          tier_used: atom(),
          capture_time_ms: non_neg_integer()
        }

  @type status :: :pending | :processing | :completed | :failed

  @default_timeout_ms 30_000

  # ============================================
  # PUBLIC API
  # ============================================

  @doc """
  Capture content from a URL.

  By default, this queues an Oban job for async processing.
  Use `async: false` for synchronous capture (useful for testing or previews).

  ## Examples

      # Async capture (default)
      {:ok, %{job_id: job_id}} = WebCapture.capture_url(user_id, url)

      # Sync capture
      {:ok, result} = WebCapture.capture_url(user_id, url, async: false)

      # With options
      {:ok, job} = WebCapture.capture_url(user_id, url, 
        tier: :simple_fetch,
        tags: ["research", "save-for-later"]
      )
  """
  @spec capture_url(String.t(), String.t(), capture_opts()) ::
          {:ok, map()} | {:error, term()}
  def capture_url(user_id, url, opts \\ []) do
    with :ok <- validate_url(url) do
      if Keyword.get(opts, :async, true) do
        queue_capture(user_id, url, opts)
      else
        capture_sync(user_id, url, opts)
      end
    end
  end

  @doc """
  Get the status of a capture job.

  Returns the current status and any results if completed.

  ## Examples

      {:ok, %{status: :completed, result: result}} = WebCapture.get_status(job_id)
      {:ok, %{status: :pending}} = WebCapture.get_status(job_id)
  """
  @spec get_status(String.t() | integer()) :: {:ok, map()} | {:error, :not_found}
  def get_status(job_id) do
    case Repo.get(Oban.Job, job_id) do
      nil ->
        {:error, :not_found}

      job ->
        status = parse_job_status(job)
        result = if status == :completed, do: job.meta["result"], else: nil

        {:ok,
         %{
           status: status,
           result: result,
           error: job.meta["error"],
           attempts: job.attempt,
           inserted_at: job.inserted_at,
           completed_at: job.completed_at
         }}
    end
  end

  @doc """
  Preview content from a URL without creating an entry.

  Always runs synchronously. Useful for showing users what will be captured.
  """
  @spec preview(String.t(), keyword()) :: {:ok, capture_result()} | {:error, term()}
  def preview(url, opts \\ []) do
    with :ok <- validate_url(url) do
      do_capture(url, Keyword.put(opts, :preview_only, true))
    end
  end

  @doc """
  Cancel a pending capture job.
  """
  @spec cancel(String.t() | integer()) :: :ok | {:error, :not_found | :already_processed}
  def cancel(job_id) do
    case Repo.get(Oban.Job, job_id) do
      nil ->
        {:error, :not_found}

      %{state: state} when state in ["available", "scheduled", "retryable"] ->
        Oban.cancel_job(job_id)
        :ok

      _ ->
        {:error, :already_processed}
    end
  end

  # ============================================
  # INTERNAL FUNCTIONS
  # ============================================

  defp queue_capture(user_id, url, opts) do
    job_args = %{
      user_id: user_id,
      url: url,
      tier: Keyword.get(opts, :tier, :auto),
      callback_url: Keyword.get(opts, :callback_url),
      tags: Keyword.get(opts, :tags, []),
      extract_markdown: Keyword.get(opts, :extract_markdown, true),
      timeout_ms: Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    }

    case CaptureWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        {:ok, %{job_id: job.id, status: :pending}}

      {:error, reason} ->
        {:error, {:queue_failed, reason}}
    end
  end

  defp capture_sync(user_id, url, opts) do
    start_time = System.monotonic_time(:millisecond)

    case do_capture(url, opts) do
      {:ok, result} ->
        capture_time_ms = System.monotonic_time(:millisecond) - start_time

        result_with_meta =
          Map.merge(result, %{
            user_id: user_id,
            capture_time_ms: capture_time_ms
          })

        {:ok, result_with_meta}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  def do_capture(url, opts) do
    tier = Keyword.get(opts, :tier, :auto)
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    extract_markdown = Keyword.get(opts, :extract_markdown, true)

    selected_tier = if tier == :auto, do: TierSelector.select(url), else: tier

    capture_with_fallback(url, selected_tier, timeout_ms, extract_markdown, opts)
  end

  defp capture_with_fallback(url, tier, timeout_ms, extract_markdown, opts) do
    Logger.debug("WebCapture: Attempting capture with tier #{tier} for #{url}")

    result =
      case tier do
        :simple_fetch ->
          Tier1SimpleFetch.capture(url,
            timeout_ms: timeout_ms,
            extract_markdown: extract_markdown
          )

        :intelligent_browser ->
          Tier2IntelligentBrowser.capture(url,
            timeout_ms: timeout_ms,
            extract_markdown: extract_markdown
          )
      end

    case result do
      {:ok, content} ->
        {:ok, Map.put(content, :tier_used, tier)}

      {:error, reason} when tier == :simple_fetch ->
        # Escalate to tier 2 if tier 1 failed
        if should_escalate?(reason) and TierSelector.tier_available?(:intelligent_browser) do
          Logger.info(
            "WebCapture: Escalating from tier 1 to tier 2 for #{url} due to #{inspect(reason)}"
          )

          capture_with_fallback(url, :intelligent_browser, timeout_ms, extract_markdown, opts)
        else
          {:error, {:tier1_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:capture_failed, tier, reason}}
    end
  end

  defp should_escalate?(reason) do
    reason in [
      :blocked,
      :javascript_required,
      :captcha_detected,
      :soft_blocked,
      :timeout
    ]
  end

  defp validate_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, :invalid_scheme}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :invalid_host}

      true ->
        :ok
    end
  end

  defp parse_job_status(%{state: "completed"}), do: :completed
  defp parse_job_status(%{state: "discarded"}), do: :failed
  defp parse_job_status(%{state: "cancelled"}), do: :cancelled
  defp parse_job_status(%{state: "executing"}), do: :processing
  defp parse_job_status(_), do: :pending
end
