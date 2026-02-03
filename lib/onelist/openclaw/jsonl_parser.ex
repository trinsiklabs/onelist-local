defmodule Onelist.OpenClaw.JsonlParser do
  @moduledoc """
  Parses OpenClaw JSONL transcript files.

  OpenClaw session files are JSONL (JSON Lines) format where each line
  is a separate JSON object representing a message in the conversation.

  ## File Location

  OpenClaw sessions are stored at:
  ```
  ~/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl
  ```

  ## Message Format

  Each line contains:
  - `role` - "user", "assistant", "system", or "tool"
  - `content` - The message text
  - `timestamp` - ISO8601 timestamp (optional)
  - `tool_calls` - Array of tool invocations (optional)

  ## Examples

      iex> {:ok, messages} = Onelist.OpenClaw.JsonlParser.parse_file("path/to/session.jsonl")
      iex> length(messages)
      42

  """

  @doc """
  Parse a JSONL file into a list of messages.

  Handles malformed lines gracefully by skipping them.
  Returns `{:ok, messages}` or `{:error, reason}`.

  ## Examples

      iex> content = ~s({"role": "user", "content": "Hello"})
      iex> File.write!("/tmp/test.jsonl", content)
      iex> {:ok, messages} = Onelist.OpenClaw.JsonlParser.parse_file("/tmp/test.jsonl")
      iex> hd(messages)["role"]
      "user"

  """
  def parse_file(path) do
    if File.exists?(path) do
      messages =
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.map(&parse_line/1)
        |> Stream.reject(&is_nil/1)
        |> Enum.to_list()

      {:ok, messages}
    else
      {:error, :file_not_found}
    end
  end

  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, message} -> message
      {:error, _} -> nil
    end
  end

  @doc """
  Extract session metadata from a file path.

  Parses the standard OpenClaw path format:
  `~/.openclaw/agents/{agent_id}/sessions/{session_id}.jsonl`

  Returns `{:ok, %{agent_id: ..., session_id: ...}}` or `{:error, :invalid_path_format}`.

  ## Examples

      iex> path = "/home/user/.openclaw/agents/main/sessions/telegram-12345.jsonl"
      iex> {:ok, info} = Onelist.OpenClaw.JsonlParser.extract_session_info(path)
      iex> info.agent_id
      "main"
      iex> info.session_id
      "telegram-12345"

  """
  def extract_session_info(path) do
    # Pattern: .../agents/{agent_id}/sessions/{session_id}.jsonl
    regex = ~r|/agents/([^/]+)/sessions/([^/]+)\.jsonl$|

    case Regex.run(regex, path) do
      [_, agent_id, session_id] ->
        {:ok, %{agent_id: agent_id, session_id: session_id}}

      nil ->
        {:error, :invalid_path_format}
    end
  end

  @doc """
  Get the earliest timestamp from a list of messages.

  Returns `{:ok, timestamp}` where timestamp is the earliest ISO8601 string,
  or `{:ok, nil}` if no messages have timestamps.

  ## Examples

      iex> messages = [%{"timestamp" => "2026-01-30T12:00:00Z"}, %{"timestamp" => "2026-01-30T08:00:00Z"}]
      iex> {:ok, earliest} = Onelist.OpenClaw.JsonlParser.get_earliest_timestamp(messages)
      iex> earliest
      "2026-01-30T08:00:00Z"

  """
  def get_earliest_timestamp(messages) do
    earliest =
      messages
      |> Enum.map(& &1["timestamp"])
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)

    {:ok, earliest}
  end

  @doc """
  Get the latest timestamp from a list of messages.

  Returns `{:ok, timestamp}` where timestamp is the latest ISO8601 string,
  or `{:ok, nil}` if no messages have timestamps.
  """
  def get_latest_timestamp(messages) do
    latest =
      messages
      |> Enum.map(& &1["timestamp"])
      |> Enum.reject(&is_nil/1)
      |> Enum.max(fn -> nil end)

    {:ok, latest}
  end
end
