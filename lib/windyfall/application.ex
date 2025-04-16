defmodule Windyfall.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WindyfallWeb.Telemetry,
      Windyfall.Repo,
      {DNSCluster, query: Application.get_env(:windyfall, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Windyfall.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Windyfall.Finch},
      # Start a worker by calling: Windyfall.Worker.start_link(arg)
      # {Windyfall.Worker, arg},
      # Start to serve requests, typically the last entry
      WindyfallWeb.Endpoint,
      WindyfallWeb.Presence,
      Windyfall.Accounts.Guest,
      Windyfall.Game.GameSessions,
      Windyfall.ReactionCache
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Windyfall.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WindyfallWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
