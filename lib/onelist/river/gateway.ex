defmodule Onelist.River.Gateway do
  @moduledoc """
  River Gateway - runs as supervised GenServer within Phoenix.

  Manages River's always-running capabilities without separate daemon.
  Handles message routing, session tracking, and PubSub integration.
  """

  use GenServer

  alias Onelist.River

  require Logger

  # ============================================
  # CLIENT API
  # ============================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Send a message to River and get a response.
  """
  def send_message(user_id, message, opts \\ []) do
    GenServer.call(__MODULE__, {:send_message, user_id, message, opts}, 30_000)
  end

  @doc """
  Get Gateway status.
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # ============================================
  # SERVER CALLBACKS
  # ============================================

  @impl true
  def init(_opts) do
    state = %{
      started_at: DateTime.utc_now(),
      active_sessions: %{},
      message_count: 0
    }

    # Subscribe to incoming messages
    Phoenix.PubSub.subscribe(Onelist.PubSub, "river:incoming")

    Logger.info("River Gateway started")

    {:ok, state}
  end

  @impl true
  def handle_call({:send_message, user_id, message, opts}, _from, state) do
    result = process_message(user_id, message, opts)

    state = %{state | message_count: state.message_count + 1}

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at),
      active_sessions: map_size(state.active_sessions),
      message_count: state.message_count
    }

    {:reply, status, state}
  end

  @impl true
  def handle_info({:river_message, user_id, message}, state) do
    # Process messages from PubSub asynchronously
    Task.Supervisor.start_child(Onelist.TaskSupervisor, fn ->
      process_and_broadcast(user_id, message)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("River Gateway received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================
  # PRIVATE FUNCTIONS
  # ============================================

  defp process_message(user_id, message, opts) do
    case River.chat(user_id, message, opts) do
      {:ok, response} ->
        # Broadcast response
        broadcast_response(user_id, response)
        {:ok, response}

      {:error, reason} = error ->
        Logger.error("River chat error for user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  defp process_and_broadcast(user_id, message) do
    case process_message(user_id, message, []) do
      {:ok, _response} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to process PubSub message: #{inspect(reason)}")
    end
  end

  defp broadcast_response(user_id, response) do
    Phoenix.PubSub.broadcast(
      Onelist.PubSub,
      "river:#{user_id}",
      {:river_response, response}
    )
  end
end
