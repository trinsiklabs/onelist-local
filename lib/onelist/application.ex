defmodule Onelist.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OnelistWeb.Telemetry,
      Onelist.Repo,
      {DNSCluster, query: Application.get_env(:onelist, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Onelist.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Onelist.Finch},
      # Task supervisor for async operations (e.g., API key touch)
      {Task.Supervisor, name: Onelist.TaskSupervisor},
      # ETS-based cache for frequently accessed data
      Onelist.Cache,
      # Oban for background job processing
      {Oban, Application.fetch_env!(:onelist, Oban)},
      # River Gateway - always-running assistant
      Onelist.River.Gateway,
      # Start to serve requests, typically the last entry
      OnelistWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Onelist.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    OnelistWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
