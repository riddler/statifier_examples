defmodule StatifierExamples.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StatifierExamplesWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:statifier_examples, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StatifierExamples.PubSub},
      # Start a worker by calling: StatifierExamples.Worker.start_link(arg)
      # {StatifierExamples.Worker, arg},
      # Start to serve requests, typically the last entry
      StatifierExamplesWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StatifierExamples.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StatifierExamplesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
