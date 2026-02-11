defmodule Ledgr.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      LedgrWeb.Telemetry,
      Ledgr.Repos.MrMunchMe,
      Ledgr.Repos.Viaxe,
      {DNSCluster, query: Application.get_env(:ledgr, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ledgr.PubSub},
      # Start to serve requests, typically the last entry
      LedgrWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ledgr.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LedgrWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
