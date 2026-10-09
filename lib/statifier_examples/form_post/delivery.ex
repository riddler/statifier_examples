defmodule StatifierExamples.FormPost.Delivery do
  @moduledoc """
  Where a card application's jobs hand their results back: a step's
  answer (`myapp:screen_application`, `myapp:sort_application`,
  `myapp:check_service_area`) and a fired deadline timer.

  Both arrive cold, from a job, outside any door of the router's. A job
  knows an execution id and what happened, and nothing else, so this
  module rebuilds the rest and steps the execution through this app's
  execution door, `StatifierExamples.FormPost.Stepper`, the same door the
  router's creates and steps go through:

    * **the library system** is the scope of the router's address row for
      the execution, the one the intake job routed the application under.
      The step runs inside `StatifierExamples.FormPost.Scope.around_delivery/3`
      with it, as every door the router drives does; without it the
      stepper refuses;
    * **the chart** is the one registered under the execution's content
      hash (`StatifierExamples.FormPost.PublishedCharts.chart/1`), so an
      execution keeps the chart it started on;
    * **the step's options** are the router's executor and its persistence
      options, so a step taken here stores jobs, arms and cancels deadlines
      and sends to the routes exactly as a step the router takes does.

  A step's answer is built from the stored position: the event is
  `Statifier.Invoke.Answer.done/4` (or `failed/4` for a step that failed on
  its last attempt), from the execution's own `_sessionid`, and only while
  the position still holds the invocation. An answer the chart is no
  longer waiting for is discarded: a screen that answers after its
  deadline fired is that case. A fired timer's event is the one
  `StatifierOban.Timer.Delivery.fired_event/2` builds.

  Every answer is `:delivered` or `{:discarded, reason}`. A discard is the
  ordinary answer for an execution that is no longer live, or an answer
  nobody is waiting for, and it tells the job not to retry. A timer that
  fires while the execution is parked for a migration raises instead, so
  `StatifierOban.Timer.Worker` retries it, as
  `StatifierExamples.FirstWorkflow.Delivery` does.
  """

  @behaviour StatifierOban.Invoke.Delivery
  @behaviour StatifierOban.Timer.Delivery

  import Ecto.Query, only: [from: 2]

  alias Statifier.Effect.SendDelayed
  alias Statifier.Invoke.Answer
  alias Statifier.MachineState
  alias StatifierExamples.{FirstWorkflow, Repo}
  alias StatifierExamples.FormPost.{PublishedCharts, Router, Scope, Stepper}
  alias StatifierOban.Timer.Delivery, as: TimerDelivery
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.Address

  @doc "Feeds a step's answer back as `done.invoke.<invoke_id>`."
  @impl StatifierOban.Invoke.Delivery
  @spec deliver(String.t(), String.t(), term()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, invoke_id, donedata) when is_binary(invoke_id) do
    step(execution_id, answer(invoke_id, &Answer.done(&1, invoke_id, donedata)))
  end

  @doc """
  Feeds a step that failed on its last attempt back as
  `error.communication.invoke.<invoke_id>`, with the failure's `:reason`,
  `:attempts` and `:detail`.
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver_failure(String.t(), String.t(), keyword()) :: :delivered | {:discarded, term()}
  def deliver_failure(execution_id, invoke_id, failure) do
    step(execution_id, answer(invoke_id, &Answer.failed(&1, invoke_id, failure)))
  end

  @doc """
  Feeds a fired deadline back as an external event, and raises for a
  parked execution so the job is retried rather than discarded.
  """
  @impl StatifierOban.Timer.Delivery
  @spec deliver(String.t(), SendDelayed.t()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, %SendDelayed{} = effect) do
    case step(execution_id, TimerDelivery.fired_event(execution_id, effect)) do
      {:discarded, {:needs_migration, _execution}} ->
        raise "execution #{execution_id} is parked (:needs_migration); " <>
                "the timer is retried until it is migrated or unparked"

      answer ->
        answer
    end
  end

  # The answer to invocation `invoke_id`, built from the loaded position
  # while it still holds the invocation, and declined otherwise.
  @spec answer(String.t(), (String.t() -> Statifier.Event.t())) ::
          (MachineState.t() -> {:ok, Statifier.Event.t()} | :discard)
  defp answer(invoke_id, build) do
    fn %MachineState{active_invocations: live, datamodel: %{"_sessionid" => session_id}} ->
      if invoke_id in Map.values(live), do: {:ok, build.(session_id)}, else: :discard
    end
  end

  @spec step(String.t(), Statifier.Event.t() | Executions.event_builder()) ::
          :delivered | {:discarded, term()}
  defp step(execution_id, event) do
    store = FirstWorkflow.store()

    with {:ok, scope} <- library_system(execution_id),
         {:ok, record} <- Storage.fetch_execution(store, execution_id),
         {:ok, machine} <- chart(record.content_hash) do
      Scope.around_delivery(scope, :job, fn ->
        store
        |> Stepper.step(execution_id, machine, event, options())
        |> stepped()
      end)
    else
      {:error, reason} -> {:discarded, reason}
    end
  end

  @spec stepped(term()) :: :delivered | {:discarded, term()}
  defp stepped({:ok, %Execution{}, %MachineState{}}), do: :delivered
  defp stepped({:discarded, %Execution{status: status}}), do: {:discarded, status}
  defp stepped({:error, reason}), do: {:discarded, reason}

  # The router's executor beside its persistence options: the invoke types
  # and the send types every step the router takes carries.
  @spec options() :: keyword()
  defp options, do: [executor: &Router.execute/2] ++ Router.config().persistence_options

  @spec chart(String.t()) :: {:ok, Statifier.Machine.t()} | {:error, :chart_not_registered}
  defp chart(content_hash) do
    case PublishedCharts.chart(content_hash) do
      {:ok, machine} -> {:ok, machine}
      :error -> {:error, :chart_not_registered}
    end
  end

  @spec library_system(String.t()) :: {:ok, String.t()} | {:error, :no_address}
  defp library_system(execution_id) do
    query =
      from(a in Config.queryable(Router.config(), Address),
        where: a.execution_id == ^execution_id,
        select: a.scope
      )

    case Repo.one(query) do
      scope when is_binary(scope) -> {:ok, scope}
      nil -> {:error, :no_address}
    end
  end
end
