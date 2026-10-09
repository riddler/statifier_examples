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
  those are `bindings/0`: the routed recipe's and the card application
  recipe's, the two recipes whose rows share this table. A row whose
  document no handed binding names has a horizon of zero, so leaving one
  recipe's bindings out would delete its rows as soon as their execution
  finished.
  """

  use Oban.Worker, queue: :router_maintenance

  alias StatifierExamples.FormPost
  alias StatifierExamples.RoutedWorkflow
  alias StatifierRouter.Addresses

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    sweep(RoutedWorkflow.config(), bindings(), [])
  end

  @doc """
  The bindings whose horizons the reap reads: every binding of each
  recipe that routes on this app's router tables.
  """
  @spec bindings() :: [StatifierRouter.Binding.t()]
  def bindings, do: RoutedWorkflow.config().bindings ++ FormPost.Router.config().bindings

  @spec sweep(StatifierRouter.Config.t(), [StatifierRouter.Binding.t()], keyword()) ::
          :ok | {:error, term()}
  defp sweep(config, bindings, opts) do
    case Addresses.reap(config, bindings, opts) do
      {:ok, %{next: nil}} -> :ok
      {:ok, %{next: next}} -> sweep(config, bindings, after: next)
      {:error, reason} -> {:error, reason}
    end
  end
end
