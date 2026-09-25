defmodule StatifierExamples.RoutedWorkflow.DedupeReaper do
  @moduledoc """
  The router's dedupe reaper, on this app's scheduler: an Oban job that
  deletes every dedupe row whose horizon has passed
  (`StatifierRouter.Dedupe.reap/2`). `config/config.exs` schedules it
  hourly through `Oban.Plugins.Cron`.

  An expired row already counts as absent when a delivery claims its
  message, so this only reclaims space; a host that never ran it would
  still route correctly.
  """

  use Oban.Worker, queue: :router_maintenance

  alias StatifierExamples.RoutedWorkflow

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _count} = StatifierRouter.Dedupe.reap(RoutedWorkflow.config(), DateTime.utc_now())
    :ok
  end
end
