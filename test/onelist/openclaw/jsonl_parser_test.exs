defmodule Onelist.OpenClaw.JsonlParserTest do
  @moduledoc """
  Tests for OpenClaw JSONL transcript parser.
  """
  use ExUnit.Case, async: true

  alias Onelist.OpenClaw.JsonlParser

  @fixtures_path "test/fixtures/openclaw"

  setup do
    # Ensure fixtures directory exists
    File.mkdir_p!(@fixtures_path)
    on_exit(fn -> File.rm_rf!(@fixtures_path) end)
    :ok
  end

  describe "parse_file/1" do
    test "parses valid JSONL file with multiple messages" do
      path = Path.join(@fixtures_path, "valid_session.jsonl")

      content = """
      {"role": "user", "content": "Hello", "timestamp": "2026-01-30T10:00:00Z"}
      {"role": "assistant", "content": "Hi there!", "timestamp": "2026-01-30T10:00:05Z"}
      {"role": "user", "content": "How are you?", "timestamp": "2026-01-30T10:00:10Z"}
      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      assert length(messages) == 3
      assert Enum.at(messages, 0)["role"] == "user"
      assert Enum.at(messages, 0)["content"] == "Hello"
      assert Enum.at(messages, 1)["role"] == "assistant"
      assert Enum.at(messages, 2)["content"] == "How are you?"
    end

    test "handles malformed lines gracefully" do
      path = Path.join(@fixtures_path, "malformed_session.jsonl")

      content = """
      {"role": "user", "content": "Valid line", "timestamp": "2026-01-30T10:00:00Z"}
      this is not valid json
      {"role": "assistant", "content": "Another valid", "timestamp": "2026-01-30T10:00:05Z"}
      {incomplete json
      {"role": "user", "content": "Final valid", "timestamp": "2026-01-30T10:00:10Z"}
      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      # Should only get the 3 valid messages
      assert length(messages) == 3
      assert Enum.at(messages, 0)["content"] == "Valid line"
      assert Enum.at(messages, 1)["content"] == "Another valid"
      assert Enum.at(messages, 2)["content"] == "Final valid"
    end

    test "extracts timestamps correctly" do
      path = Path.join(@fixtures_path, "timestamps.jsonl")

      content = """
      {"role": "user", "content": "First", "timestamp": "2026-01-30T08:00:00Z"}
      {"role": "assistant", "content": "Second", "timestamp": "2026-01-30T12:30:45Z"}
      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      assert Enum.at(messages, 0)["timestamp"] == "2026-01-30T08:00:00Z"
      assert Enum.at(messages, 1)["timestamp"] == "2026-01-30T12:30:45Z"
    end

    test "handles missing timestamps" do
      path = Path.join(@fixtures_path, "no_timestamps.jsonl")

      content = """
      {"role": "user", "content": "No timestamp here"}
      {"role": "assistant", "content": "Me neither"}
      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      assert length(messages) == 2
      assert Enum.at(messages, 0)["timestamp"] == nil
      assert Enum.at(messages, 1)["timestamp"] == nil
    end

    test "handles empty file" do
      path = Path.join(@fixtures_path, "empty.jsonl")
      File.write!(path, "")

      {:ok, messages} = JsonlParser.parse_file(path)

      assert messages == []
    end

    test "handles file with only whitespace/empty lines" do
      path = Path.join(@fixtures_path, "whitespace.jsonl")

      content = """

      {"role": "user", "content": "Message", "timestamp": "2026-01-30T10:00:00Z"}

      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      assert length(messages) == 1
    end

    test "returns error for non-existent file" do
      {:error, reason} = JsonlParser.parse_file("/nonexistent/path.jsonl")
      assert reason == :file_not_found
    end

    test "preserves tool_calls in messages" do
      path = Path.join(@fixtures_path, "with_tools.jsonl")

      content = """
      {"role": "assistant", "content": "Let me search", "timestamp": "2026-01-30T10:00:00Z", "tool_calls": [{"name": "search", "args": {"q": "test"}}]}
      """

      File.write!(path, content)

      {:ok, messages} = JsonlParser.parse_file(path)

      assert length(messages) == 1

      assert Enum.at(messages, 0)["tool_calls"] == [
               %{"name" => "search", "args" => %{"q" => "test"}}
             ]
    end
  end

  describe "extract_session_info/1" do
    test "extracts agent_id and session_id from standard path" do
      path = "/home/user/.openclaw/agents/main/sessions/telegram-12345.jsonl"

      {:ok, info} = JsonlParser.extract_session_info(path)

      assert info.agent_id == "main"
      assert info.session_id == "telegram-12345"
    end

    test "extracts info from nested agent path" do
      path = "/root/.openclaw/agents/my-agent/sessions/cli-local.jsonl"

      {:ok, info} = JsonlParser.extract_session_info(path)

      assert info.agent_id == "my-agent"
      assert info.session_id == "cli-local"
    end

    test "handles paths with unusual characters" do
      path = "/data/.openclaw/agents/agent_v2/sessions/session_2026-01-30_10-00.jsonl"

      {:ok, info} = JsonlParser.extract_session_info(path)

      assert info.agent_id == "agent_v2"
      assert info.session_id == "session_2026-01-30_10-00"
    end

    test "returns error for non-standard path" do
      path = "/some/random/path/file.jsonl"

      {:error, :invalid_path_format} = JsonlParser.extract_session_info(path)
    end
  end

  describe "get_earliest_timestamp/1" do
    test "returns earliest timestamp from messages" do
      messages = [
        %{"timestamp" => "2026-01-30T12:00:00Z"},
        %{"timestamp" => "2026-01-30T08:00:00Z"},
        %{"timestamp" => "2026-01-30T15:00:00Z"}
      ]

      {:ok, earliest} = JsonlParser.get_earliest_timestamp(messages)

      assert earliest == "2026-01-30T08:00:00Z"
    end

    test "handles messages without timestamps" do
      messages = [
        %{"content" => "no timestamp"},
        %{"timestamp" => "2026-01-30T10:00:00Z"},
        %{"content" => "also no timestamp"}
      ]

      {:ok, earliest} = JsonlParser.get_earliest_timestamp(messages)

      assert earliest == "2026-01-30T10:00:00Z"
    end

    test "returns nil for empty list" do
      {:ok, earliest} = JsonlParser.get_earliest_timestamp([])
      assert earliest == nil
    end

    test "returns nil when no messages have timestamps" do
      messages = [
        %{"content" => "no timestamp"},
        %{"content" => "also none"}
      ]

      {:ok, earliest} = JsonlParser.get_earliest_timestamp(messages)

      assert earliest == nil
    end
  end
end
