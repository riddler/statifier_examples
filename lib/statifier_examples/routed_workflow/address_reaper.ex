defmodule StatifierExamples.RoutedWorkflow.AddressReaper do
  @moduledoc """
  The router's address reaper, on this app's scheduler: an Oban job that
  sweeps the address table with `StatifierRouter.Addresses.reap/3`,
  stamping the rows whose execution has finished and deleting those
  finished longer ago than their binding's dedupe horizon.
  `config/config.exs` schedules it hourly through `Oban.Plugins.Cron`.

  One call examines a bounded number of rows and answers a cursor, so the
  job calls again from that cursor until it reaches the end of the table.
  The horizon of a row is read from the bindings handed to the reap, and
  those are the bindings the recipe routes with.
  """

  use Oban.Worker, queue: :router_maintenance

  alias StatifierExamples.RoutedWorkflow
  alias StatifierRouter.Addresses

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    config = RoutedWorkflow.config()
    sweep(config, [])
  end

  @spec sweep(StatifierRouter.Config.t(), keyword()) :: :ok | {:error, term()}
  defp sweep(config, opts) do
    case Addresses.reap(config, config.bindings, opts) do
      {:ok, %{next: nil}} -> :ok
      {:ok, %{next: next}} -> sweep(config, after: next)
      {:error, reason} -> {:error, reason}
    end
  end
end
