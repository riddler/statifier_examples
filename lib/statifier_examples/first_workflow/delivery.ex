defmodule StatifierExamples.FirstWorkflow.Delivery do
  @moduledoc """
  Where the first-workflow recipe's two jobs hand their results back: the
  set-aside call's answer and the pickup window's fired timer.

  Both arrive cold. A job knows an execution id and what happened, and
  nothing else: the chart is rebuilt from the one registered under the
  execution's content hash (`StatifierExamples.FirstWorkflow.machine_for/2`),
  and the driver steps the stored position inside the execution's
  serialization strategy.

  ## What is discarded, and what raises

  Every answer is `:delivered` or `{:discarded, reason}`, and a discard
  tells the job not to retry. A discard answers a fact about the
  execution, one no retry changes:

    * the execution has finished, or the stored position no longer holds
      the invocation the answer is for: the driver refuses the event and
      the reason is the execution's stored status;
    * the step exhausted the execution's macrostep budget, which the store
      answers only once the execution's `:failed` record is durable: the
      reason is `:failed`;
    * the store holds no execution under the id: `:execution_not_found`.

  Every other failure is a fact about the environment rather than the
  execution, and raises, so the job is retried while attempts remain, as
  `StatifierOban.Invoke.Delivery` and `StatifierOban.Timer.Delivery` ask.
  The first of them is an execution a migration parked
  (`:needs_migration`): the driver refuses the event whole and consumes
  nothing, and the execution goes on once it is migrated or unparked
  (`StatifierPersistence.Executions.unpark/3`), so a discard would lose
  the answer or the firing it is waiting for. The others are an error
  from the store, such as a position it cannot read, a chart the store
  holds no source for, and any other refusal of the step. A retried
  invoke job runs the set-aside call again, idempotent on the invoke id
  by the handler's contract, and its answer is fed back to the position
  stored then. A job whose attempts run out first is discarded by Oban,
  and the answer with it.
  """

  @behaviour StatifierOban.Invoke.Delivery
  @behaviour StatifierOban.Timer.Delivery

  alias Statifier.Effect.SendDelayed
  alias Statifier.Event
  alias StatifierExamples.FirstWorkflow
  alias StatifierPersistence.Driver

  @doc """
  Feeds the set-aside call's answer back as `done.invoke.<invoke_id>`.
  Raises for a failure that is not a fact about the execution (the
  moduledoc lists the discards).
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver(String.t(), String.t(), term()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, invoke_id, donedata) when is_binary(invoke_id) do
    drive(execution_id, &Driver.done_invocation(&1, execution_id, invoke_id, donedata))
  end

  @doc """
  Feeds a permanently failed call back as
  `error.communication.invoke.<invoke_id>`, with the failure's `:reason`,
  `:attempts` and `:detail`. Raises as `deliver/3` does.
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver_failure(String.t(), String.t(), keyword()) :: :delivered | {:discarded, term()}
  def deliver_failure(execution_id, invoke_id, failure) do
    drive(execution_id, &Driver.failed_invocation(&1, execution_id, invoke_id, failure))
  end

  @doc """
  Feeds a fired timer's event back as an external event. Raises as
  `deliver/3` does, a parked execution included, so the job is retried
  rather than discarded.
  """
  @impl StatifierOban.Timer.Delivery
  @spec deliver(String.t(), SendDelayed.t()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, %SendDelayed{event: event}) do
    drive(execution_id, &Driver.send_event(&1, execution_id, Event.external(event)))
  end

  @spec drive(String.t(), (Driver.t() -> Driver.result())) :: :delivered | {:discarded, term()}
  defp drive(execution_id, door) do
    store = FirstWorkflow.store()

    with {:ok, machine} <- FirstWorkflow.machine_for(store, execution_id),
         {:ok, _execution, _machine_state} <- door.(FirstWorkflow.driver(store, machine)) do
      :delivered
    else
      {:discarded, execution} -> {:discarded, execution.status}
      {:error, reason} -> refused(execution_id, reason)
    end
  end

  # A refusal that is a fact about the execution is discarded; any other
  # raises, so the job is retried (the moduledoc's "What is discarded, and
  # what raises").
  @spec refused(String.t(), term()) :: {:discarded, :execution_not_found | :failed}
  defp refused(_execution_id, :execution_not_found), do: {:discarded, :execution_not_found}

  # The store answers a step that exhausted the execution's macrostep
  # budget only once the execution's `:failed` record is durable, so the
  # execution has finished.
  defp refused(_execution_id, {:budget_exhausted, _payload}), do: {:discarded, :failed}

  defp refused(execution_id, {:needs_migration, _execution}) do
    raise "execution #{execution_id} is parked (:needs_migration); " <>
            "the delivery is retried until it is migrated or unparked"
  end

  defp refused(execution_id, reason) do
    raise "execution #{execution_id} could not be stepped (#{inspect(reason)}); " <>
            "the delivery is retried"
  end
end
