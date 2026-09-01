defmodule StatifierExamples.Charts.AsyncCalls.Delivery do
  @moduledoc """
  How a finished invoke job gets its answer back into a durable run.

  `StatifierOban.Invoke.Delivery` is a behaviour for the same reason
  `StatifierOban.Timer.Delivery` is: whether a run is live is the host's
  question. The package's default answers it from `Statifier.Session`'s
  registry and delivers through `Statifier.Session.done_invocation/3`,
  and this app has no session process to look up - its runs live in
  SQLite between steps. So the answer here is the stored run's own
  status and the persisted position's own `active_invocations`, and the
  feed-back is `StatifierPersistence.Driver`'s ADR-0007 re-entry doors.

  Nothing about this module knows a page exists. It is handed a run id, an
  invocation id and a result by an Oban worker, on a node that may have
  started after the invocation did, and everything it needs to rebuild the
  chart it reads back out of storage. That is what "the invocation
  survived a restart" means in code.

  ## Two doors, and the discards they share

  `c:StatifierOban.Invoke.Delivery.deliver/3` carries a completed
  invocation back as `done.invoke.<invoke_id>`;
  `c:StatifierOban.Invoke.Delivery.deliver_failure/3` carries a
  **permanently** failed one back as
  `error.communication.invoke.<invoke_id>` (st-ADR-0068), which is what a
  chart parking failed work transitions on. A transient failure never
  reaches here: the job retries, and only the attempt that exhausts them
  delivers.

  Both discard for the same three reasons, and
  `StatifierExamples.Charts.Durable`'s own `complete_invocation/3` spells
  them: the run is no longer live, the chart can no longer be rebuilt, or
  the invocation is no longer the live one under its state - spec 6.4.3's
  cancellation, which for this app is the abandonment deadline having
  fired while the job was still running. The worker records a discard on
  the job row as a cancellation, so it is visible rather than silent.

  Idempotency under redelivery comes from the same place: a chart that has
  transitioned out of the invoking state has no live invocation to answer,
  so a second delivery finds nothing and discards. That holds for every
  asynchronous call this app makes, because the wizard's company-details
  step leaves its state on the answer - which is the condition
  statifier_persistence's ADR-0007 names in its Consequences, and the
  reason this app's one asynchronous call is that one.
  """

  @behaviour StatifierOban.Invoke.Delivery

  alias StatifierExamples.Charts.Durable

  @doc """
  Reports the invocation named `invoke_id` in the run named `scope`
  complete, with `donedata`.
  """
  @impl StatifierOban.Invoke.Delivery
  def deliver(scope, invoke_id, donedata) when is_binary(scope) and is_binary(invoke_id) do
    Durable.complete_invocation(scope, invoke_id, donedata)
  end

  @doc """
  Reports the invocation named `invoke_id` in the run named `scope`
  permanently failed, with st-ADR-0068's `failure` keyword list.
  """
  @impl StatifierOban.Invoke.Delivery
  def deliver_failure(scope, invoke_id, failure)
      when is_binary(scope) and is_binary(invoke_id) and is_list(failure) do
    Durable.fail_invocation(scope, invoke_id, failure)
  end
end
