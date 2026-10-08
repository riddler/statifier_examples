defmodule UpgradeHost.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    :ok = UpgradeHost.Telemetry.setup()

    children = [
      UpgradeHost.Repo,
      {Oban, Application.fetch_env!(:upgrade_host, Oban)}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: UpgradeHost.Supervisor)
  end
end
