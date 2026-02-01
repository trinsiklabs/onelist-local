defmodule Onelist.Cache do
  @moduledoc """
  Simple ETS-based cache for frequently accessed data.

  Provides a key-value cache with automatic TTL-based expiration.
  Used for caching rendered markdown, user data, and other
  frequently accessed content.

  ## Usage

      # Store a value with default TTL (15 minutes)
      Onelist.Cache.put(:my_key, "my value")

      # Store with custom TTL (in milliseconds)
      Onelist.Cache.put(:my_key, "my value", :timer.hours(1))

      # Retrieve a value
      case Onelist.Cache.get(:my_key) do
        {:ok, value} -> value
        :miss -> # cache miss
      end

      # Fetch with fallback function
      value = Onelist.Cache.fetch(:my_key, fn -> expensive_computation() end)
  """

  use GenServer

  @table_name :onelist_cache
  @default_ttl :timer.minutes(15)
  @cleanup_interval :timer.minutes(5)

  # Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves a value from the cache.

  Returns `{:ok, value}` if found and not expired, `:miss` otherwise.
  """
  @spec get(term()) :: {:ok, term()} | :miss
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, value}
        else
          delete(key)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc """
  Stores a value in the cache with an optional TTL.

  ## Options

    * `ttl` - Time to live in milliseconds (default: 15 minutes)
  """
  @spec put(term(), term(), non_neg_integer()) :: :ok
  def put(key, value, ttl \\ @default_ttl) do
    expires_at = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  end

  @doc """
  Deletes a key from the cache.
  """
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Fetches a value from cache, computing it if not present.

  If the key is not in the cache (or expired), calls the provided
  function to compute the value, stores it, and returns it.

  ## Example

      value = Onelist.Cache.fetch({:markdown, hash}, fn ->
        render_markdown(content)
      end)
  """
  @spec fetch(term(), non_neg_integer(), (-> term())) :: term()
  def fetch(key, ttl \\ @default_ttl, fun) when is_function(fun, 0) do
    case get(key) do
      {:ok, value} ->
        value

      :miss ->
        value = fun.()
        put(key, value, ttl)
        value
    end
  end

  @doc """
  Clears all entries from the cache.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Returns the number of entries in the cache (including expired).
  """
  @spec size() :: non_neg_integer()
  def size do
    :ets.info(@table_name, :size)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired do
    now = DateTime.utc_now()

    :ets.foldl(
      fn {key, _value, expires_at}, acc ->
        if DateTime.compare(now, expires_at) != :lt do
          :ets.delete(@table_name, key)
        end

        acc
      end,
      nil,
      @table_name
    )
  end
end
