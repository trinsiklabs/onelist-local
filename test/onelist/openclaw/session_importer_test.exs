defmodule Onelist.OpenClaw.SessionImporterTest do
  @moduledoc """
  Tests for OpenClaw session importer.
  """
  use Onelist.DataCase, async: false

  alias Onelist.OpenClaw.SessionImporter
  alias Onelist.OpenClaw.JsonlParser
  alias Onelist.Entries.Entry
  alias Onelist.Repo

  @fixtures_path "test/fixtures/openclaw_import"

  setup do
    # Create fixtures directory structure
    sessions_path = Path.join(@fixtures_path, "agents/main/sessions")
    File.mkdir_p!(sessions_path)

    user = insert_user()

    on_exit(fn -> File.rm_rf!(@fixtures_path) end)

    {:ok, user: user, sessions_path: sessions_path}
  end

  describe "list_sessions/2" do
    test "lists all session files in directory", %{sessions_path: sessions_path} do
      # Create test session files
      File.write!(
        Path.join(sessions_path, "session1.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session2.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session3.jsonl"),
        session_content("2026-01-30T09:00:00Z")
      )

      {:ok, sessions} = SessionImporter.list_sessions(@fixtures_path)

      assert length(sessions) == 3
    end

    test "returns sessions sorted by earliest timestamp", %{sessions_path: sessions_path} do
      # Create files with different timestamps (out of order)
      File.write!(
        Path.join(sessions_path, "session_c.jsonl"),
        session_content("2026-01-30T15:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session_a.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session_b.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      {:ok, sessions} = SessionImporter.list_sessions(@fixtures_path)

      # Should be sorted chronologically
      timestamps = Enum.map(sessions, & &1.earliest_timestamp)

      assert timestamps == [
               "2026-01-30T08:00:00Z",
               "2026-01-30T10:00:00Z",
               "2026-01-30T15:00:00Z"
             ]
    end

    test "filters by agent_id", %{sessions_path: sessions_path} do
      # Create another agent's sessions
      other_agent_path = Path.join(@fixtures_path, "agents/other-agent/sessions")
      File.mkdir_p!(other_agent_path)

      File.write!(
        Path.join(sessions_path, "session1.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(other_agent_path, "session2.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      {:ok, main_sessions} = SessionImporter.list_sessions(@fixtures_path, agent_id: "main")

      {:ok, other_sessions} =
        SessionImporter.list_sessions(@fixtures_path, agent_id: "other-agent")

      assert length(main_sessions) == 1
      assert length(other_sessions) == 1
    end

    test "filters by :after option", %{sessions_path: sessions_path} do
      File.write!(Path.join(sessions_path, "old.jsonl"), session_content("2026-01-15T08:00:00Z"))
      File.write!(Path.join(sessions_path, "new.jsonl"), session_content("2026-01-30T10:00:00Z"))

      {:ok, sessions} =
        SessionImporter.list_sessions(@fixtures_path, after: ~U[2026-01-20 00:00:00Z])

      assert length(sessions) == 1
      assert hd(sessions).earliest_timestamp == "2026-01-30T10:00:00Z"
    end

    test "filters by :before option", %{sessions_path: sessions_path} do
      File.write!(Path.join(sessions_path, "old.jsonl"), session_content("2026-01-15T08:00:00Z"))
      File.write!(Path.join(sessions_path, "new.jsonl"), session_content("2026-01-30T10:00:00Z"))

      {:ok, sessions} =
        SessionImporter.list_sessions(@fixtures_path, before: ~U[2026-01-20 00:00:00Z])

      assert length(sessions) == 1
      assert hd(sessions).earliest_timestamp == "2026-01-15T08:00:00Z"
    end

    test "handles empty directory" do
      empty_path = Path.join(@fixtures_path, "empty_agents/main/sessions")
      File.mkdir_p!(empty_path)

      {:ok, sessions} = SessionImporter.list_sessions(Path.join(@fixtures_path, "empty_agents"))

      assert sessions == []
    end

    test "returns error for non-existent directory" do
      {:error, :directory_not_found} = SessionImporter.list_sessions("/nonexistent/path")
    end
  end

  describe "import_session_file/3" do
    test "imports a single session file", %{user: user, sessions_path: sessions_path} do
      path = Path.join(sessions_path, "test_session.jsonl")
      File.write!(path, session_content("2026-01-30T10:00:00Z"))

      {:ok, result} = SessionImporter.import_session_file(user, path)

      assert result.entry_id != nil
      assert result.message_count == 2

      # Verify entry was created
      entry = Repo.get!(Entry, result.entry_id)
      assert entry.entry_type == "chat_log"
      assert entry.source_type == "openclaw_import"
      assert entry.metadata["session_id"] != nil
    end

    test "preserves original timestamps", %{user: user, sessions_path: sessions_path} do
      path = Path.join(sessions_path, "timestamps.jsonl")
      File.write!(path, session_content("2026-01-15T08:30:00Z"))

      {:ok, result} = SessionImporter.import_session_file(user, path)

      entry = Repo.get!(Entry, result.entry_id)
      assert entry.metadata["started_at"] == "2026-01-15T08:30:00Z"
      assert entry.metadata["imported_at"] != nil
    end

    test "records source file in metadata", %{user: user, sessions_path: sessions_path} do
      path = Path.join(sessions_path, "source_test.jsonl")
      File.write!(path, session_content("2026-01-30T10:00:00Z"))

      {:ok, result} = SessionImporter.import_session_file(user, path)

      entry = Repo.get!(Entry, result.entry_id)
      assert entry.metadata["source_file"] == path
    end

    test "handles file not found", %{user: user} do
      {:error, :file_not_found} = SessionImporter.import_session_file(user, "/nonexistent.jsonl")
    end

    test "is idempotent - same session_id doesn't create duplicate", %{
      user: user,
      sessions_path: sessions_path
    } do
      path = Path.join(sessions_path, "idempotent.jsonl")
      File.write!(path, session_content("2026-01-30T10:00:00Z"))

      {:ok, result1} = SessionImporter.import_session_file(user, path)
      {:ok, result2} = SessionImporter.import_session_file(user, path)

      # Should return same entry
      assert result1.entry_id == result2.entry_id

      # Only one entry should exist
      count =
        Entry
        |> where([e], e.user_id == ^user.id and e.entry_type == "chat_log")
        |> Repo.aggregate(:count)

      assert count == 1
    end
  end

  describe "import_directory/3" do
    test "imports all sessions in chronological order", %{
      user: user,
      sessions_path: sessions_path
    } do
      # Create sessions out of order
      File.write!(
        Path.join(sessions_path, "session_c.jsonl"),
        session_content("2026-01-30T15:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session_a.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session_b.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      {:ok, result} = SessionImporter.import_directory(user, @fixtures_path)

      assert result.imported_count == 3
      assert result.failed_count == 0
    end

    test "dry_run returns count without importing", %{user: user, sessions_path: sessions_path} do
      File.write!(
        Path.join(sessions_path, "session1.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session2.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      {:ok, result} = SessionImporter.import_directory(user, @fixtures_path, dry_run: true)

      assert result.would_import == 2
      assert result.dry_run == true

      # Verify nothing was actually imported
      count =
        Entry
        |> where([e], e.user_id == ^user.id and e.entry_type == "chat_log")
        |> Repo.aggregate(:count)

      assert count == 0
    end

    test "respects :after filter", %{user: user, sessions_path: sessions_path} do
      File.write!(Path.join(sessions_path, "old.jsonl"), session_content("2026-01-15T08:00:00Z"))
      File.write!(Path.join(sessions_path, "new.jsonl"), session_content("2026-01-30T10:00:00Z"))

      {:ok, result} =
        SessionImporter.import_directory(user, @fixtures_path, after: ~U[2026-01-20 00:00:00Z])

      assert result.imported_count == 1
    end

    test "handles empty directory", %{user: user} do
      empty_path = Path.join(@fixtures_path, "empty_dir/agents/main/sessions")
      File.mkdir_p!(empty_path)

      {:ok, result} =
        SessionImporter.import_directory(user, Path.join(@fixtures_path, "empty_dir"))

      assert result.imported_count == 0
    end

    test "calls progress callback during import", %{user: user, sessions_path: sessions_path} do
      # Create test sessions
      File.write!(
        Path.join(sessions_path, "session_a.jsonl"),
        session_content("2026-01-30T08:00:00Z")
      )

      File.write!(
        Path.join(sessions_path, "session_b.jsonl"),
        session_content("2026-01-30T10:00:00Z")
      )

      # Track progress calls
      test_pid = self()

      progress_fn = fn current, total, context ->
        send(test_pid, {:progress, current, total, context})
      end

      {:ok, _result} =
        SessionImporter.import_directory(user, @fixtures_path, progress: progress_fn)

      # Should receive progress calls for each session
      # Session 1: importing then complete
      assert_receive {:progress, 1, 2, %{status: :importing, session_id: "session_a"}}
      assert_receive {:progress, 1, 2, %{status: :complete, session_id: "session_a"}}

      # Session 2: importing then complete
      assert_receive {:progress, 2, 2, %{status: :importing, session_id: "session_b"}}
      assert_receive {:progress, 2, 2, %{status: :complete, session_id: "session_b"}}
    end
  end

  # Helper functions

  defp insert_user do
    %Onelist.Accounts.User{
      id: Ecto.UUID.generate(),
      email: "test-#{System.unique_integer()}@example.com",
      trusted_memory_mode: false
    }
    |> Repo.insert!()
  end

  defp session_content(timestamp) do
    """
    {"role": "user", "content": "Hello", "timestamp": "#{timestamp}"}
    {"role": "assistant", "content": "Hi there!", "timestamp": "#{advance_timestamp(timestamp, 5)}"}
    """
  end

  defp advance_timestamp(timestamp, seconds) do
    {:ok, dt, _} = DateTime.from_iso8601(timestamp)
    DateTime.add(dt, seconds, :second) |> DateTime.to_iso8601()
  end
end
