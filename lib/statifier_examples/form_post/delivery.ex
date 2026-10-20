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

  A step that finishes the execution with the screen's word
  `"screened_out"` in its datamodel also marks the stored application
  screened out, through
  `StatifierExamples.FormPost.CardApplications.Writer.record_screened_out/2`
  under the same library system: the screen's answer reaches the chart,
  and this is where the host's row learns the outcome, so the host's
  retention can age it. The application's id is the one the datamodel
  holds; the write reads no posted value. A screen answer that arrives
  after its bound is discarded before any step, so it never marks the row.

  The write follows the step's commit and is not part of it, so a write
  that fails, or a process that dies, after the step has stored the
  finished execution leaves the row unmarked. The row still reaches
  screened out: the delivery raises (or its job is rescued), the job is
  retried, and the retry finds the execution finished. The step answers
  that as a discard, and before the discard is answered the delivery
  reads the finished execution's stored position and, when it holds the
  screen's word, writes the mark it missed. The answer is the discard it
  always was, `{:discarded, :completed}`. A stored position that is gone
  (`:execution_position_missing`; the host's
  `StatifierExamples.FormPost.PruneJob` clears the position of every
  execution that ended before its cutoff) is a fact about the execution
  that no retry changes, so the discard is answered and the mark, if one
  was missed, cannot be recovered. Any other store error on that read
  raises, so the job is retried again. The mark is written once: a row
  already screened out keeps the stamp of its first mark.

  The write does not join the step's transaction. On this app's SQLite
  the step is serialized by `StatifierExamples.Charts.ExecutionLock`,
  which is released when the step returns; inside an outer transaction
  that is before the commit, and a delivery for the same execution taken
  in between would read the position the commit has not yet replaced.

  ## What is discarded, and what raises

  Every answer is `:delivered` or `{:discarded, reason}`, and a discard
  tells the job not to retry. A discard answers a fact about the
  execution, one no retry changes:

    * the execution has finished: the reason is its stored status,
      `:completed`, `:failed` or `:cancelled`;
    * the step exhausted the execution's macrostep budget, which the store
      answers only once the execution's `:failed` record is durable: the
      reason is `:failed`;
    * the stored position no longer holds the invocation the answer is
      for: the reason is the execution's status, `:active`;
    * the router holds no address row for the execution: `:no_address`;
    * the store holds no execution under the id: `:execution_not_found`.

  Every other failure is a fact about the environment rather than the
  execution, and raises, so the job is retried while attempts remain, as
  `StatifierOban.Invoke.Delivery` and `StatifierOban.Timer.Delivery` ask:
  an execution parked for a migration (`:needs_migration`), which takes
  the answer once it is migrated or unparked; an error from the store,
  such as a position it cannot read; no chart registered under the
  execution's content hash; and any other refusal of the step. A retried
  invoke job runs its handler again, idempotent on the invoke id by the
  handler's contract, and the answer is built again from the position
  stored then. A job whose attempts run out first is discarded by Oban,
  and the answer with it.

  ## The caller's context

  `StatifierOban.Invoke.Worker` calls the widest door a delivery module
  exports, so it calls `deliver/4` and `deliver_failure/4` here, with
  the `caller_context` stored on the job row. Each passes it into the
  answer it builds (`Statifier.Invoke.Answer.done/4`'s and `failed/4`'s
  `caller_context:` option), so the step the answer drives carries it on
  its macrostep telemetry and onto the effects it plans, the next job
  among them. The three-argument doors are the behaviour's required
  ones and deliver with no context.
  """

  @behaviour StatifierOban.Invoke.Delivery
  @behaviour StatifierOban.Timer.Delivery

  import Ecto.Query, only: [from: 2]

  alias Statifier.Effect.SendDelayed
  alias Statifier.Invoke.Answer
  alias Statifier.MachineState
  alias StatifierExamples.{FirstWorkflow, Repo}
  alias StatifierExamples.FormPost.CardApplications.Writer
  alias StatifierExamples.FormPost.{PublishedCharts, Router, Scope, Stepper}
  alias StatifierOban.Invoke.Delivery, as: InvokeDelivery
  alias StatifierOban.Timer.Delivery, as: TimerDelivery
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.Address

  @doc "`deliver/4` with no caller context."
  @impl StatifierOban.Invoke.Delivery
  @spec deliver(String.t(), String.t(), term()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, invoke_id, donedata),
    do: deliver(execution_id, invoke_id, donedata, [])

  @doc """
  Feeds a step's answer back as `done.invoke.<invoke_id>`, carrying the
  `:caller_context` in `opts`. Raises for a failure that is not a fact
  about the execution (the moduledoc lists the discards).
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver(String.t(), String.t(), term(), InvokeDelivery.answer_opts()) ::
          :delivered | {:discarded, term()}
  def deliver(execution_id, invoke_id, donedata, opts) when is_binary(invoke_id) do
    context = [caller_context: Keyword.get(opts, :caller_context)]
    step(execution_id, answer(invoke_id, &Answer.done(&1, invoke_id, donedata, context)))
  end

  @doc "`deliver_failure/4` with no caller context."
  @impl StatifierOban.Invoke.Delivery
  @spec deliver_failure(String.t(), String.t(), keyword()) :: :delivered | {:discarded, term()}
  def deliver_failure(execution_id, invoke_id, failure),
    do: deliver_failure(execution_id, invoke_id, failure, [])

  @doc """
  Feeds a step that failed on its last attempt back as
  `error.communication.invoke.<invoke_id>`, with the failure's `:reason`,
  `:attempts` and `:detail`, carrying the `:caller_context` in `opts`.
  Raises as `deliver/4` does.
  """
  @impl StatifierOban.Invoke.Delivery
  @spec deliver_failure(String.t(), String.t(), keyword(), InvokeDelivery.answer_opts()) ::
          :delivered | {:discarded, term()}
  def deliver_failure(execution_id, invoke_id, failure, opts) do
    context = [caller_context: Keyword.get(opts, :caller_context)]
    step(execution_id, answer(invoke_id, &Answer.failed(&1, invoke_id, failure, context)))
  end

  @doc """
  Feeds a fired deadline back as an external event. Raises as `deliver/4`
  does, a parked execution included, so the job is retried rather than
  discarded.
  """
  @impl StatifierOban.Timer.Delivery
  @spec deliver(String.t(), SendDelayed.t()) :: :delivered | {:discarded, term()}
  def deliver(execution_id, %SendDelayed{} = effect) do
    step(execution_id, TimerDelivery.fired_event(execution_id, effect))
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
        |> record_outcome(scope, store, machine)
        |> stepped(execution_id)
      end)
    else
      {:error, reason} -> refused(execution_id, reason)
    end
  end

  # A step that finished the execution screened out marks the stored
  # application so. The write follows the step's own commit rather than
  # sharing it (the moduledoc says why), so a crash between the two leaves
  # the row "received" and the job is retried. The retry's step is
  # discarded, the execution having finished, and the finished execution's
  # stored position is read for the screen's word, so the retry writes the
  # mark the first attempt missed. The row is never deleted (the host's
  # purge clears its fields and keeps it), so a missing one is a broken
  # invariant and raises, and so does a store error on the read. A pruned
  # position (`:execution_position_missing`) is gone for good, so the
  # discard stands.
  @spec record_outcome(term(), String.t(), Storage.t(), Statifier.Machine.t()) :: term()
  defp record_outcome(
         {:ok, %Execution{status: :completed}, %MachineState{} = state} = stepped,
         scope,
         _store,
         _machine
       ) do
    mark_screened_out(state, scope)
    stepped
  end

  defp record_outcome(
         {:discarded, %Execution{status: :completed, execution_id: execution_id}} = stepped,
         scope,
         store,
         machine
       ) do
    case Storage.load_execution_position(store, execution_id, machine) do
      {:ok, %MachineState{} = state} -> mark_screened_out(state, scope)
      {:error, :execution_position_missing} -> :ok
      {:error, reason} -> unread(execution_id, reason)
    end

    stepped
  end

  defp record_outcome(stepped, _scope, _store, _machine), do: stepped

  @spec mark_screened_out(MachineState.t(), String.t()) :: :ok
  defp mark_screened_out(
         %MachineState{datamodel: %{"screen" => "screened_out", "application_id" => id}},
         scope
       )
       when is_integer(id),
       do: :ok = Writer.record_screened_out(scope, id)

  defp mark_screened_out(%MachineState{}, _scope), do: :ok

  @spec unread(String.t(), term()) :: no_return()
  defp unread(execution_id, reason) do
    raise "the finished execution #{execution_id}'s position could not be read " <>
            "(#{inspect(reason)}); the delivery is retried"
  end

  @spec stepped(term(), String.t()) :: :delivered | {:discarded, term()}
  defp stepped({:ok, %Execution{}, %MachineState{}}, _execution_id), do: :delivered
  defp stepped({:discarded, %Execution{status: status}}, _execution_id), do: {:discarded, status}
  defp stepped({:error, reason}, execution_id), do: refused(execution_id, reason)

  # A refusal that is a fact about the execution is discarded; any other
  # raises, so the job is retried (the moduledoc's "What is discarded, and
  # what raises").
  @spec refused(String.t(), term()) :: {:discarded, :no_address | :execution_not_found | :failed}
  defp refused(_execution_id, reason) when reason in [:no_address, :execution_not_found],
    do: {:discarded, reason}

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
