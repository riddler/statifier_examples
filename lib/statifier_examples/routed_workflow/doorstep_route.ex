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

  A route owes at-most-once on the key the router hands it. The job is
  unique on that key, so a redriven delivery that hands the same key over
  again inserts nothing new.
  """

  @behaviour StatifierRouter.Route

  alias StatifierExamples.RoutedWorkflow.DoorstepNotice

  @impl StatifierRouter.Route
  @spec deliver(map(), Statifier.Event.t(), StatifierRouter.Route.idempotency_key()) ::
          :ok | {:error, term()}
  def deliver(%{queue: queue}, %Statifier.Event{} = event, key) do
    %{"execution_id" => event.origin, "event" => event.name, "key" => idempotency(key)}
    |> DoorstepNotice.new(queue: queue)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # The router's key as one string: the scope half (the execution id here),
  # where in the step the hand-off sat, and the ordinal, which the
  # completion hook never carries.
  @spec idempotency(StatifierRouter.Route.idempotency_key()) :: String.t()
  defp idempotency({scope, position, ordinal}) do
    Enum.join(
      [scope, position.macrostep, position.microstep, position.round, ordinal || "-"],
      ":"
    )
  end
end
