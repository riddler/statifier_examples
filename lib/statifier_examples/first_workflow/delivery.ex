defmodule StatifierExamples.FirstWorkflow.Delivery do
  @moduledoc """
  Where the first-workflow recipe's two jobs hand their results back: the
  set-aside call's answer and the pickup window's fired timer.

  Both arrive cold. A job knows an execution id and what happened, and
  nothing else: the chart is rebuilt from the one registered under the
  execution's content hash (`StatifierExamples.FirstWorkflow.machine_for/2`),
  and the driver steps the stored position inside the execution's
  serialization strategy.

  Every answer is `:delivered` or `{:discarded, reason}`. A discard is the
  ordinary answer for an execution that is no longer live, and it tells the
  job not to retry.
  """

  @behaviour StatifierOban.Invoke.Delivery
  @behaviour StatifierOban.Timer.Delivery

  alias Statifier.Effect.SendDelayed
  alias Statifier.Event
  alias StatifierExamples.FirstWorkflow
  alias StatifierPersistence.Driver

  @doc "Feeds the set-aside call's answer back as `done.invoke.<invoke_id>`."
  @impl StatifierOban.Invoke.Delivery
  @spec deliver(String.t(), String.t(), term()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, invoke_id, donedata) when is_binary(invoke_id) do
    drive(execution_id, &Driver.done_invocation(&1, execution_id, invoke_id, donedata))
  end

  @doc """
  Feeds a permanently failed call back as
  `error.communication.invoke.<invoke_id>`, with the failure's `:reason`,
  `:attempts` and `:detail`.
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver_failure(String.t(), String.t(), keyword()) :: :delivered | {:discarded, term()}
  def deliver_failure(execution_id, invoke_id, failure) do
    drive(execution_id, &Driver.failed_invocation(&1, execution_id, invoke_id, failure))
  end

  @doc "Feeds a fired timer's event back as an external event."
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
      {:error, reason} -> {:discarded, reason}
    end
  end
end
