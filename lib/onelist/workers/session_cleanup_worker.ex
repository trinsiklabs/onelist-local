defmodule Onelist.Workers.SessionCleanupWorker do
  @moduledoc """
  Background worker for cleaning up expired sessions.
  Will be triggered by a scheduled job.
  """

  use GenServer
  require Logger
  alias Onelist.Sessions

  # 1 hour in milliseconds
  @cleanup_interval 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Schedule first cleanup
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_sessions()
    schedule_cleanup()
    {:noreply, state}
  end

  defp cleanup_sessions do
    Logger.info("Starting session cleanup")

    # Process login attempts first
    cleanup_login_attempts()

    # Then process sessions
    # Batch size for cleanup
    batch_size = 1000

    # Keep cleaning up until we process a batch smaller than the batch size
    cleanup_loop(batch_size)

    Logger.info("Session cleanup completed")
  end

  defp cleanup_loop(batch_size) do
    {count, _} = Sessions.cleanup_expired_sessions(batch_size)

    # Log the cleanup count
    Logger.info("Cleaned up #{count} expired sessions")

    if count >= batch_size do
      # If we hit the batch size, continue cleaning
      cleanup_loop(batch_size)
    end
  end

  defp cleanup_login_attempts do
    # Default retention period: 90 days
    retention_days =
      Application.get_env(:onelist, Onelist.Accounts)[:login_attempt_retention_days] || 90

    # Clean up old login attempts
    {count, _} = Onelist.Accounts.delete_old_login_attempts(retention_days)

    # Log the cleanup count
    Logger.info("Cleaned up #{count} old login attempts (older than #{retention_days} days)")
  end

  defp schedule_cleanup do
    # Schedule next cleanup
    interval =
      Application.get_env(:onelist, Onelist.Sessions)[:cleanup_interval] ||
        @cleanup_interval

    Process.send_after(self(), :cleanup, interval)
  end
end
