defmodule Onelist.Searcher.RateLimiter do
  @moduledoc """
  ETS-based rate limiter for Searcher operations.

  Provides per-user, per-operation rate limiting with configurable
  limits and time windows.

  ## Configuration

  Configure limits in `config/config.exs`:

      config :onelist, :searcher,
        rate_limit_enabled: true,
        rate_limits: %{
          search: {100, :per_minute},
          embed: {50, :per_hour},
          similarity_check: {200, :per_minute},
          rerank: {50, :per_minute}
        }

  ## Usage

      # Check if operation is allowed
      case RateLimiter.check_limit(user_id, :search) do
        {:ok, remaining} -> perform_search()
        {:error, :rate_limited, retry_after} -> return_429(retry_after)
      end

      # Or use the wrapper function
      RateLimiter.with_rate_limit(user_id, :search, fn ->
        perform_search()
      end)
  """

  use GenServer

  require Logger

  @default_limits %{
    search: {100, :per_minute},
    embed: {50, :per_hour},
    similarity_check: {200, :per_minute},
    rerank: {50, :per_minute}
  }

  @table_name :searcher_rate_limits

  # Client API

  @doc """
  Starts the rate limiter GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Check if a request is within rate limits.

  ## Parameters
    - user_id: The user making the request
    - operation: The operation type (:search, :embed, :similarity_check, :rerank)

  ## Returns
    - `{:ok, remaining}` - Request allowed, remaining requests in window
    - `{:error, :rate_limited, retry_after_seconds}` - Rate limit exceeded
  """
  def check_limit(user_id, operation) do
    if enabled?() do
      do_check_limit(user_id, operation)
    else
      {:ok, :unlimited}
    end
  end

  @doc """
  Get remaining requests for a user/operation without consuming.
  """
  def get_remaining(user_id, operation) do
    {limit, window} = get_limit_config(operation)
    key = make_key(user_id, operation)
    window_ms = window_to_ms(window)

    case :ets.lookup(@table_name, key) do
      [] ->
        limit

      [{^key, count, start_time}] ->
        now = System.monotonic_time(:millisecond)

        if now - start_time >= window_ms do
          # Window expired, full limit available
          limit
        else
          max(0, limit - count)
        end
    end
  end

  @doc """
  Reset the rate limit for a user/operation.
  """
  def reset_limit(user_id, operation) do
    key = make_key(user_id, operation)
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Get configured limits for all operations.
  """
  def get_limits do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:rate_limits, @default_limits)
  end

  @doc """
  Check if rate limiting is enabled.
  """
  def enabled? do
    Application.get_env(:onelist, :searcher, [])
    |> Keyword.get(:rate_limit_enabled, true)
  end

  @doc """
  Execute a function if within rate limits.

  ## Parameters
    - user_id: The user making the request
    - operation: The operation type
    - func: Function to execute if allowed

  ## Returns
    - Result of the function if allowed
    - `{:error, :rate_limited, retry_after}` if rate limited
  """
  def with_rate_limit(user_id, operation, func) when is_function(func, 0) do
    case check_limit(user_id, operation) do
      {:ok, _remaining} ->
        func.()

      {:error, :rate_limited, _retry_after} = error ->
        error
    end
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table for rate limit tracking
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Schedule periodic cleanup
    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp do_check_limit(user_id, operation) do
    {limit, window} = get_limit_config(operation)
    key = make_key(user_id, operation)
    now = System.monotonic_time(:millisecond)
    window_ms = window_to_ms(window)

    case :ets.lookup(@table_name, key) do
      [] ->
        # First request in window
        :ets.insert(@table_name, {key, 1, now})
        {:ok, limit - 1}

      [{^key, count, start_time}] ->
        if now - start_time >= window_ms do
          # Window expired, reset counter
          :ets.insert(@table_name, {key, 1, now})
          {:ok, limit - 1}
        else
          if count >= limit do
            # Rate limited
            retry_after = div(window_ms - (now - start_time), 1000) + 1
            {:error, :rate_limited, max(1, retry_after)}
          else
            # Increment counter
            :ets.update_counter(@table_name, key, {2, 1})
            {:ok, limit - count - 1}
          end
        end
    end
  end

  defp get_limit_config(operation) do
    limits = get_limits()
    Map.get(limits, operation, {100, :per_minute})
  end

  defp make_key(user_id, operation) do
    {user_id, operation}
  end

  defp window_to_ms(:per_minute), do: 60_000
  defp window_to_ms(:per_hour), do: 3_600_000
  defp window_to_ms(:per_day), do: 86_400_000

  defp schedule_cleanup do
    # Clean up every 5 minutes
    Process.send_after(self(), :cleanup, 5 * 60 * 1000)
  end

  defp cleanup_expired_entries do
    now = System.monotonic_time(:millisecond)
    max_window_ms = 3_600_000  # 1 hour - longest possible window

    # Delete entries older than the longest window
    :ets.select_delete(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:<, {:-, now, :"$3"}, max_window_ms}], [true]}
    ])
  rescue
    _ -> :ok
  end
end
