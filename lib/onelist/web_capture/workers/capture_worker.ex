defmodule Onelist.WebCapture.Workers.CaptureWorker do
  @moduledoc """
  Oban worker for asynchronous web content capture.

  Processes capture jobs and optionally creates entries in the user's library.

  ## Job Args

  Required:
  - `user_id` - The user requesting the capture
  - `url` - The URL to capture

  Optional:
  - `tier` - Force specific tier (:auto, :simple_fetch, :intelligent_browser)
  - `callback_url` - URL to POST results to when complete
  - `tags` - Tags to apply to created entry
  - `extract_markdown` - Convert to markdown (default: true)
  - `timeout_ms` - Request timeout in milliseconds
  - `create_entry` - Whether to create an entry (default: false)
  - `entry_opts` - Options for entry creation

  ## Example

      %{
        user_id: "abc123",
        url: "https://example.com/article",
        tier: :auto,
        tags: ["reading-list"],
        create_entry: true
      }
      |> CaptureWorker.new()
      |> Oban.insert()
  """

  use Oban.Worker,
    queue: :capture,
    max_attempts: 3,
    unique: [period: 300, fields: [:args, :queue], keys: [:user_id, :url]]

  alias Onelist.WebCapture
  alias Onelist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: args}) do
    user_id = args["user_id"]
    url = args["url"]

    Logger.info("WebCapture: Starting capture job #{job_id} for #{url}")

    opts = build_capture_opts(args)
    start_time = System.monotonic_time(:millisecond)

    case WebCapture.do_capture(url, opts) do
      {:ok, result} ->
        capture_time_ms = System.monotonic_time(:millisecond) - start_time

        final_result = Map.merge(result, %{
          user_id: user_id,
          capture_time_ms: capture_time_ms,
          job_id: job_id
        })

        # Store result in job meta
        update_job_meta(job_id, %{
          status: "completed",
          result: serialize_result(final_result),
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

        # Optionally create entry
        if args["create_entry"] do
          create_entry_from_capture(user_id, final_result, args)
        end

        # Optionally notify callback URL
        if args["callback_url"] do
          notify_callback(args["callback_url"], final_result)
        end

        Logger.info("WebCapture: Completed job #{job_id} in #{capture_time_ms}ms")
        :ok

      {:error, reason} ->
        error_msg = format_error(reason)

        update_job_meta(job_id, %{
          status: "failed",
          error: error_msg,
          failed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

        Logger.warning("WebCapture: Job #{job_id} failed: #{error_msg}")

        # Return error to trigger Oban retry
        {:error, reason}
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  defp build_capture_opts(args) do
    [
      tier: parse_tier(args["tier"]),
      extract_markdown: Map.get(args, "extract_markdown", true),
      timeout_ms: Map.get(args, "timeout_ms", 30_000)
    ]
  end

  defp parse_tier("simple_fetch"), do: :simple_fetch
  defp parse_tier("intelligent_browser"), do: :intelligent_browser
  defp parse_tier(:simple_fetch), do: :simple_fetch
  defp parse_tier(:intelligent_browser), do: :intelligent_browser
  defp parse_tier(_), do: :auto

  defp update_job_meta(nil, _new_meta), do: :ok

  defp update_job_meta(job_id, new_meta) do
    import Ecto.Query

    from(j in Oban.Job, where: j.id == ^job_id)
    |> Repo.update_all(set: [meta: new_meta])
  end

  defp serialize_result(result) do
    result
    |> Map.take([
      :url, :final_url, :title, :description, :author,
      :site_name, :image_url, :word_count, :language,
      :tier_used, :capture_time_ms
    ])
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp create_entry_from_capture(user_id, result, args) do
    tags = args["tags"] || []

    entry_attrs = %{
      user_id: user_id,
      title: result.title || result.final_url,
      content: result.markdown || result.content,
      entry_type: "article",
      source_type: "web_capture",
      metadata: %{
        "capture" => %{
          "url" => result.url,
          "final_url" => result.final_url,
          "tier_used" => to_string(result.tier_used),
          "capture_time_ms" => result.capture_time_ms,
          "site_name" => result.site_name,
          "author" => result.author,
          "word_count" => result.word_count,
          "language" => result.language
        }
      }
    }

    # Use the Entries context to create the entry
    case Onelist.Entries.create_entry(entry_attrs) do
      {:ok, entry} ->
        # Apply tags
        if tags != [] do
          Onelist.Tags.apply_tags(entry.id, tags, user_id)
        end

        Logger.info("WebCapture: Created entry #{entry.id} from capture")
        {:ok, entry}

      {:error, changeset} ->
        Logger.warning("WebCapture: Failed to create entry: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  rescue
    e ->
      Logger.error("WebCapture: Error creating entry: #{Exception.message(e)}")
      {:error, e}
  end

  defp notify_callback(callback_url, result) do
    payload = %{
      status: "completed",
      result: serialize_result(result)
    }

    case Req.post(callback_url, json: payload, receive_timeout: 10_000) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.debug("WebCapture: Callback notification sent successfully")
        :ok

      {:ok, %{status: status}} ->
        Logger.warning("WebCapture: Callback returned status #{status}")
        :ok

      {:error, reason} ->
        Logger.warning("WebCapture: Failed to notify callback: #{inspect(reason)}")
        :ok
    end
  rescue
    e ->
      Logger.warning("WebCapture: Callback error: #{Exception.message(e)}")
      :ok
  end

  defp format_error({:tier1_failed, reason}), do: "Tier 1 failed: #{format_error(reason)}"
  defp format_error({:capture_failed, tier, reason}), do: "#{tier} failed: #{format_error(reason)}"
  defp format_error(:blocked), do: "Site blocked automated access"
  defp format_error(:rate_limited), do: "Rate limited by site"
  defp format_error(:timeout), do: "Request timed out"
  defp format_error(:not_found), do: "URL not found (404)"
  defp format_error(:gone), do: "URL no longer exists (410)"
  defp format_error(:javascript_required), do: "Site requires JavaScript"
  defp format_error(:no_content_found), do: "Could not extract content"
  defp format_error({:http_error, status}), do: "HTTP error: #{status}"
  defp format_error({:network_error, reason}), do: "Network error: #{inspect(reason)}"
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason), do: inspect(reason)
end
