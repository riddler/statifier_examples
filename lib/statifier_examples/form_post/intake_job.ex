defmodule StatifierExamples.FormPost.IntakeJob do
  @moduledoc """
  The job that takes one stored card application into the library's
  workflow, enqueued by `StatifierExamples.FormPost.CardApplications` in
  the transaction that stored the application.

  Its arguments are `%{"application_id" => id}` and nothing else: a job's
  arguments sit in the jobs table, in plain sight of every dashboard and
  dead letter, and the posted values belong in the host's own table only.
  """

  use Oban.Worker, queue: :card_application_intake

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => _id}}) do
    # Handing the application's id to the router's webhook front is the
    # next change; until then the job takes nothing further.
    :ok
  end
end
