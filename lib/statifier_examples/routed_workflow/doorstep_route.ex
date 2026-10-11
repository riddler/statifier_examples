defmodule StatifierExamples.RoutedWorkflow.DoorstepRoute do
  @moduledoc """
  The routed recipe's one route, `doorstep_notices`: the sink a parcel's
  execution reaches when it finishes, through the router configuration's
  `:on_complete`.

  A route runs inside the delivery's transaction, under the execution's
  serialization, so it may only hand off durably. This one inserts a
  `StatifierExamples.RoutedWorkflow.DoorstepNotice` job on this app's own
  Oban, which writes through the same repo and so commits or rolls back
  with the delivery: a transactional outbox with nothing to add.

  A route owes at-most-once on the key the router hands it, spelled as
  one string by `StatifierExamples.RouterKey.join/1` (the execution id is
  its scope half here). The job is unique on that key, so a redriven
  delivery that hands the same key over again inserts nothing new while
  the job's row is in the jobs table, which this app's Oban pruner keeps
  for seven days after the job finishes (`config/config.exs`).
  """

  @behaviour StatifierRouter.Route

  alias StatifierExamples.RoutedWorkflow.DoorstepNotice
  alias StatifierExamples.RouterKey

  @impl StatifierRouter.Route
  @spec deliver(map(), Statifier.Event.t(), StatifierRouter.Route.idempotency_key()) ::
          :ok | {:error, term()}
  def deliver(%{queue: queue}, %Statifier.Event{} = event, key) do
    %{"execution_id" => event.origin, "event" => event.name, "key" => RouterKey.join(key)}
    |> DoorstepNotice.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
