defmodule Onelist.OpenClaw.ProgressTest do
  @moduledoc """
  Tests for OpenClaw import progress reporter.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Onelist.OpenClaw.Progress

  describe "cli_reporter/3" do
    test "renders progress bar with percentage" do
      output =
        capture_io(fn ->
          Progress.cli_reporter(5, 10, %{status: :importing, session_id: "test-session"})
        end)

      assert output =~ "█"
      assert output =~ "░"
      assert output =~ "(05 of 10)"
      assert output =~ "50%"
      assert output =~ "importing test-session"
    end

    test "renders 0% at start" do
      output =
        capture_io(fn ->
          Progress.cli_reporter(0, 10, %{status: :importing, session_id: "first"})
        end)

      assert output =~ "0%"
    end

    test "renders 100% at end" do
      output =
        capture_io(fn ->
          Progress.cli_reporter(10, 10, %{status: :complete, session_id: "last"})
        end)

      assert output =~ "100%"
      assert output =~ "imported last"
    end

    test "shows failed status" do
      output =
        capture_io(fn ->
          Progress.cli_reporter(3, 10, %{status: :failed, session_id: "broken"})
        end)

      assert output =~ "FAILED broken"
    end

    test "truncates long session IDs" do
      long_id = String.duplicate("a", 50)

      output =
        capture_io(fn ->
          Progress.cli_reporter(1, 1, %{status: :importing, session_id: long_id})
        end)

      # Should be truncated with ...
      assert output =~ "..."
      refute output =~ long_id
    end

    test "pads numbers consistently" do
      output1 =
        capture_io(fn ->
          Progress.cli_reporter(1, 100, %{status: :importing, session_id: "s"})
        end)

      output2 =
        capture_io(fn ->
          Progress.cli_reporter(99, 100, %{status: :importing, session_id: "s"})
        end)

      assert output1 =~ "(001 of 100)"
      assert output2 =~ "(099 of 100)"
    end
  end

  describe "finish/2" do
    test "renders completion message" do
      output = capture_io(fn -> Progress.finish(42) end)

      assert output =~ "42 sessions imported"
      assert output =~ String.duplicate("█", 30)
    end

    test "shows failed count if any" do
      output = capture_io(fn -> Progress.finish(10, failed: 2) end)

      assert output =~ "8 imported, 2 failed"
    end
  end

  describe "silent_reporter/3" do
    test "returns :ok without output" do
      output =
        capture_io(fn ->
          result = Progress.silent_reporter(1, 10, %{status: :importing, session_id: "s"})
          assert result == :ok
        end)

      assert output == ""
    end
  end
end
