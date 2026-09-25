defmodule StatifierExamples.RoutedWorkflow.DoorstepNotice do
  @moduledoc """
  The job `StatifierExamples.RoutedWorkflow.DoorstepRoute` hands a finished
  parcel off to: the notice that the parcel reached its doorstep.

  A real host would tell the recipient here. This recipe's notice does
  nothing but finish, which is what the recipe checks: the hand-off
  committed with the delivery that finished the execution, and the job
  ran.
  """

  use Oban.Worker,
    queue: :parcel_notices,
    unique: [keys: [:key], period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"execution_id" => _execution_id, "key" => _key}}), do: :ok
end
