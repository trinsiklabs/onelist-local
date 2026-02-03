defmodule Onelist.OpenClaw.Progress do
  @moduledoc """
  CLI progress bar for OpenClaw session imports.

  ## Usage

      # From IEx
      alias Onelist.OpenClaw.{SessionImporter, Progress}

      SessionImporter.import_directory(user, "~/.openclaw",
        progress: &Progress.cli_reporter/3
      )

  ## Custom Reporter

  You can provide your own progress callback:

      my_reporter = fn current, total, context ->
        IO.puts("Processing \#{current}/\#{total}: \#{context[:file_path]}")
      end

      SessionImporter.import_directory(user, path, progress: my_reporter)

  The callback receives:
  - `current` - Current session number (1-indexed)
  - `total` - Total number of sessions
  - `context` - Map with `:file_path`, `:session_id`, `:status` keys
  """

  @bar_width 30

  @doc """
  CLI progress reporter that updates in place.

  Renders a progress bar like:
  ```
  [████████████░░░░░░░░░░░░░░░░░░] (15 of 92) 16% importing cli-042...
  ```
  """
  def cli_reporter(current, total, context) do
    pct = if total > 0, do: current / total, else: 0
    pct_int = round(pct * 100)
    filled = round(pct * @bar_width)
    empty = @bar_width - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)
    count_str = "(#{pad(current, total)} of #{total})"

    label = format_label(context)

    # Clear line and write progress
    IO.write("\r\e[K[#{bar}] #{count_str} #{pct_int}% #{label}")
  end

  @doc """
  Call when import completes to finalize the progress display.
  """
  def finish(total, opts \\ []) do
    failed = Keyword.get(opts, :failed, 0)

    bar = String.duplicate("█", @bar_width)

    message = if failed > 0 do
      "#{total - failed} imported, #{failed} failed"
    else
      "#{total} sessions imported"
    end

    IO.puts("\r\e[K[#{bar}] #{message}.")
  end

  @doc """
  Silent reporter that does nothing. Useful for non-interactive contexts.
  """
  def silent_reporter(_current, _total, _context), do: :ok

  # Pad number to match width of total
  defp pad(n, total) do
    width = total |> Integer.to_string() |> String.length()
    n |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp format_label(%{status: :importing, session_id: session_id}) do
    # Truncate long session IDs
    display_id = truncate(session_id, 30)
    "importing #{display_id}..."
  end

  defp format_label(%{status: :complete, session_id: session_id}) do
    display_id = truncate(session_id, 30)
    "imported #{display_id}"
  end

  defp format_label(%{status: :failed, session_id: session_id}) do
    display_id = truncate(session_id, 30)
    "FAILED #{display_id}"
  end

  defp format_label(_), do: ""

  defp truncate(str, max_len) when byte_size(str) <= max_len, do: str
  defp truncate(str, max_len), do: String.slice(str, 0, max_len - 3) <> "..."
end
