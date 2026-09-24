defmodule StatifierExamples.FirstWorkflow do
  @moduledoc """
  The recipe `docs/guides/first-workflow.md` walks, as code: one durable
  workflow from a block document to a finished execution, on this app's
  own database and Oban instance.

  The document is `priv/first_workflow/hold_pickup.json`, a hold on a
  library copy in two steps: the branch sets the copy aside (an
  `<invoke>` of `myapp:set_aside`), then the hold waits out its pickup
  window (a `core.wait`, which compiles to a delayed `<send>`). `run/1`
  takes it through seven steps and checks each one before the next:

    1. `:expressible` - `StatifierBlocks.Plan.expressible/3` against the
       palette the host mounts: every block resolves and sits where the
       editor would let an author put it.
    2. `:published` - `StatifierExamples.Publish.check/2`, the host's
       publish step over every publish-time check the packages ship.
    3. `:registered` - the runtime compile, and
       `StatifierPersistence.Storage.save_chart/3` storing its source under
       the chart's content hash, so a process that never saw the document
       can rebuild the chart from that hash alone.
    4. `:opened` - `StatifierPersistence.Driver.create/3`, which runs
       `StatifierPersistence.Executions.create/4` and dispatches the
       chart's first `<invoke>`. The dispatch answers `:pending` and the
       executor stores an Oban job for the call, so the execution rests
       durably in the middle of it.
    5. `:acted` - the invoke job runs `StatifierExamples.FirstWorkflow.SetAside`
       under the `:invoke_timeout` bound its `StatifierOban.Config` names,
       and `StatifierExamples.FirstWorkflow.Delivery` feeds the answer back
       through `StatifierPersistence.Driver.done_invocation/5`. Entering
       the wait arms the pickup window as a timer job.
    6. `:timer_fired` - the timer job comes due, and the same delivery
       module feeds its event back through
       `StatifierPersistence.Driver.send_event/4`. The execution completes.
    7. `:ended` - the stored record reads `:completed` with an `ended_at`
       stamp, and the input log (`StatifierPersistence.Executions.inputs/2`)
       is the trace: every event that entered the execution, by the door
       it came in through.

  Jobs run wherever Oban runs them. Under the test configuration
  (`testing: :manual`) nothing runs until someone drains a queue, and in
  the dev app the queues run on their own; `run/1` drains both queues on
  every poll, only ever for jobs already due, so the same code finishes in
  either and fires no timer early.

  `run/1` answers `{:ok, lines}`, the lines the mix task prints, or
  `{:error, step, reason}` naming the first step that did not hold.
  """

  alias Statifier.Effect.{Cancel, CancelInvoke, Invoke, SendDelayed}
  alias Statifier.Invoke.Types
  alias StatifierBlocks.{Compiled, Compiler, Decode, Document, Plan}
  alias StatifierExamples.{Charts, Publish}
  alias StatifierExamples.Charts.ExecutionLock
  alias StatifierExamples.FirstWorkflow.{Delivery, NoRoute, SetAside}
  alias StatifierOban.Invoke.Handler
  alias StatifierPersistence.{Driver, Execution, Executions, Storage}

  @document "first_workflow/hold_pickup.json"

  # The one invoke type the document calls, and the only one this recipe
  # registers.
  @set_aside "myapp:set_aside"

  @invoke_queue :statifier_invocations
  @timers_queue :statifier_timers

  # How long one invoke job may run before Oban kills the attempt. The
  # handler answers at once; the bound is here because a host's real
  # call is the one that can hang, and a job with no bound holds its
  # queue slot for as long as it hangs.
  @invoke_timeout 5_000

  # How long `run/1` polls for the two jobs before it names the step that
  # never finished. The pickup window is one second.
  @deadline_ms 15_000
  @poll_ms 50

  @typedoc "The step `run/1` names when it stops; see the moduledoc."
  @type step ::
          :decoded
          | :expressible
          | :published
          | :registered
          | :opened
          | :acted
          | :timer_fired
          | :ended
          | :unexpected

  @doc """
  Runs the recipe once, under a fresh execution id, and answers the lines
  the mix task prints or the first step that did not hold.

  `opts` takes `:execution_id` (default a fresh random id) and
  `:hold` (default a fictional hold) for a caller that wants to name
  either.
  """
  @spec run(keyword()) :: {:ok, [String.t()]} | {:error, step(), term()}
  def run(opts \\ []) do
    execution_id = Keyword.get_lazy(opts, :execution_id, &new_execution_id/0)
    hold = Keyword.get(opts, :hold, default_hold())

    with {:ok, document} <- step(:decoded, decode()),
         :ok <- step(:expressible, Plan.expressible(document, Charts.palette())),
         {:ok, _compiled, _accepts, warnings} <- step(:published, publish(document)),
         {:ok, machine, content_hash} <- step(:registered, register(document)),
         {:ok, opened} <- step(:opened, open(machine, execution_id, hold)),
         {:ok, _acted, %{"shelved" => shelved}} <- step(:acted, await(execution_id, &shelved?/2)),
         {:ok, ended, _datamodel} <- step(:timer_fired, await(execution_id, &terminal?/2)),
         {:ok, inputs} <- step(:ended, ended(ended)) do
      {:ok,
       [
         "first workflow on " <> pins(),
         "expressible  #{document.id} against the host palette",
         "published    every publish-time check passed, #{length(warnings)} warning(s)",
         "registered   chart #{content_hash}",
         "opened       execution #{execution_id}: #{opened.status}, the set-aside call queued",
         "acted        #{@set_aside} answered under a #{@invoke_timeout} ms bound: " <>
           inspect(shelved),
         "timer fired  the pickup window elapsed",
         "ended        #{ended.status} at #{DateTime.to_iso8601(ended.ended_at)}",
         "trace        the input log, oldest first:"
       ] ++ Enum.map(inputs, &trace_line/1)}
    else
      {:error, _step, _reason} = error -> error
      other -> {:error, :unexpected, other}
    end
  end

  @doc """
  The `statifier_oban` configuration the recipe's jobs run under.

  `:invoke_timeout` is the run-time bound on the set-aside call: an
  attempt that runs past it fails with `Oban.TimeoutError` and retries
  while attempts remain, and a last attempt that times out delivers
  `error.communication.invoke.<invoke_id>` with `reason: "run_crashed"`.
  Both deliveries go to `StatifierExamples.FirstWorkflow.Delivery`, which
  steps the stored execution cold.
  """
  @spec config() :: StatifierOban.Config.t()
  def config do
    case StatifierOban.Config.new(
           oban: Oban,
           timers_queue: @timers_queue,
           delivery: Delivery,
           invoke_queue: @invoke_queue,
           invoke_delivery: Delivery,
           invoke_timeout: @invoke_timeout
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  The driver for an execution of `machine`: the dispatch fun that answers
  the set-aside call `:pending`, the executor that stores the jobs, the
  registered invoke type, and this app's serialization strategy.

  Built per call rather than held, because the process that opens an
  execution is not the one that answers it: an Oban job rebuilds it from
  the registered chart (`StatifierExamples.FirstWorkflow.Delivery`).
  """
  @spec driver(Storage.t(), Statifier.Machine.t()) :: Driver.t()
  def driver(%Storage{} = store, machine) do
    Driver.new(store, machine,
      dispatch: &dispatch/3,
      effects: &execute/2,
      invoke_types: Types.new(types: [@set_aside]),
      serialization: {ExecutionLock, ExecutionLock}
    )
  end

  @doc "The store this recipe writes to: this app's own SQLite adapter."
  @spec store() :: Storage.t()
  def store do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    store
  end

  @doc """
  Rebuilds the chart an execution runs on from the chart registered under
  its content hash, which is all a cold delivery has to go on.
  """
  @spec machine_for(Storage.t(), String.t()) :: {:ok, Statifier.Machine.t()} | {:error, term()}
  def machine_for(%Storage{} = store, execution_id) do
    with {:ok, record} <- Storage.fetch_execution(store, execution_id),
         {:ok, chart} <- Storage.fetch_chart(store, record.content_hash) do
      Statifier.compile(chart.chart_blob)
    end
  end

  # ------------------------------------------------------------ the steps

  @spec step(step(), term()) :: term()
  defp step(_step, :ok), do: :ok
  defp step(_step, {:ok, _} = ok), do: ok
  defp step(_step, {:ok, _, _} = ok), do: ok
  defp step(_step, {:ok, _, _, _} = ok), do: ok
  defp step(step, {:no, reasons}), do: {:error, step, reasons}
  defp step(step, {:refused, refusal}), do: {:error, step, refusal}
  defp step(step, {:error, reason}), do: {:error, step, reason}

  @spec decode() :: {:ok, Document.t()} | {:error, term()}
  defp decode do
    :statifier_examples
    |> :code.priv_dir()
    |> Path.join(@document)
    |> File.read!()
    |> Decode.decode()
  end

  # The host state the publish step judges against. This recipe sends
  # nothing through the router and names no child document, so the router
  # configuration registers no route and the two lookups find nothing.
  @spec publish(Document.t()) :: Publish.result()
  defp publish(document) do
    {:ok, router_config} =
      StatifierRouter.Config.new(
        repo: StatifierExamples.Repo,
        delivery: NoRoute,
        send_type: "myapp:route",
        route_adapters: %{}
      )

    Publish.check(document, %{
      palette: Charts.palette(),
      datamodel: nil,
      send_types: %{},
      router_config: router_config,
      accepts_lookup: fn _document -> {:error, :not_published} end,
      document_resolver: fn _document -> {:error, :not_published} end
    })
  end

  # The runtime compile: `terminate: true` so the finished sequence reaches
  # a top-level final and the execution completes, and the registered
  # invoke type so the compiler warns about a call nobody answers. The
  # source is what is registered, under the content hash the execution
  # record will carry.
  @spec register(Document.t()) ::
          {:ok, Statifier.Machine.t(), String.t()} | {:error, term()}
  defp register(document) do
    with {:ok, %Compiled{scxml: scxml}} <-
           Compiler.compile(document, Charts.palette(),
             known_invoke_types: [@set_aside],
             terminate: true
           ),
         {:ok, machine} <- Statifier.compile(scxml),
         :ok <- Storage.save_chart(store(), machine, scxml) do
      {:ok, machine, Statifier.Machine.identity(machine).content_hash}
    end
  end

  @spec open(Statifier.Machine.t(), String.t(), map()) :: {:ok, Execution.t()} | {:error, term()}
  defp open(machine, execution_id, hold) do
    store()
    |> driver(machine)
    |> Driver.create(execution_id, initialize: [datamodel: %{"hold" => hold}])
    |> case do
      {:ok, %Execution{status: :active} = execution, _machine_state} -> {:ok, execution}
      {:ok, %Execution{} = execution, _machine_state} -> {:error, {:not_active, execution}}
      {:discarded, execution} -> {:error, {:discarded, execution}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Polls the stored execution until `done?` holds or the deadline passes,
  # running every job that is already due on each pass. Answers the
  # execution and the datamodel of its stored position.
  @spec await(String.t(), (Execution.t(), map() -> boolean())) ::
          {:ok, Execution.t(), map()} | {:error, term()}
  defp await(execution_id, done?) do
    await(execution_id, done?, System.monotonic_time(:millisecond) + @deadline_ms)
  end

  defp await(execution_id, done?, deadline) do
    drain()

    with {:ok, execution, datamodel} <- read(execution_id) do
      cond do
        done?.(execution, datamodel) ->
          {:ok, execution, datamodel}

        System.monotonic_time(:millisecond) >= deadline ->
          {:error, {:timed_out, execution.status}}

        true ->
          Process.sleep(@poll_ms)
          await(execution_id, done?, deadline)
      end
    end
  end

  # The stored execution and the datamodel of its stored position, which
  # is where the set-aside answer lands (`assign_to: "shelved"`).
  @spec read(String.t()) :: {:ok, Execution.t(), map()} | {:error, term()}
  defp read(execution_id) do
    store = store()

    with {:ok, record} <- Storage.fetch_execution(store, execution_id),
         {:ok, machine} <- machine_for(store, execution_id),
         {:ok, machine_state} <- Storage.load_execution_position(store, execution_id, machine) do
      {:ok, Execution.from_record(record), machine_state.datamodel}
    end
  end

  # Only jobs already due: a timer is never fired early.
  @spec drain() :: :ok
  defp drain do
    for queue <- [@invoke_queue, @timers_queue] do
      Oban.drain_queue(queue: queue, with_scheduled: DateTime.utc_now())
    end

    :ok
  end

  # The set-aside answer has landed, or the execution stopped without it.
  @spec shelved?(Execution.t(), map()) :: boolean()
  defp shelved?(execution, datamodel),
    do: execution.status != :active or is_map(datamodel["shelved"])

  @spec terminal?(Execution.t(), map()) :: boolean()
  defp terminal?(execution, _datamodel), do: execution.status != :active

  @spec ended(Execution.t()) :: {:ok, [Storage.input()]} | {:error, term()}
  defp ended(%Execution{status: :completed} = execution) do
    if Executions.ended?(execution) do
      case Executions.inputs(store(), execution.execution_id) do
        {:ok, inputs} -> {:ok, inputs}
        :not_supported -> {:error, :input_log_not_supported}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:no_ended_at, execution}}
    end
  end

  defp ended(%Execution{} = execution), do: {:error, {:not_completed, execution}}

  # -------------------------------------------------- the two driver funs

  # The set-aside call is started by the executor below and answered
  # later, so the dispatch only says so.
  @spec dispatch(String.t() | nil, term(), Driver.dispatch_context()) ::
          :pending | {:error, keyword()}
  defp dispatch(@set_aside, _params, _context), do: :pending

  defp dispatch(type, _params, _context),
    do: {:error, reason: "unknown_invoke_type", attempts: 1, detail: inspect(type)}

  # Stores a job for each effect that is one, and passes the rest. A job
  # that cannot be stored raises: answering `{:error, _}` here would steer
  # the chart with an infrastructure fact.
  @spec execute(Statifier.Effect.t(), map()) :: :ok
  defp execute({:invoke, %Invoke{type: @set_aside} = invoke}, context) do
    :ok = Handler.perform_start(SetAside, invoke, handler_ctx(context.execution_id))
  end

  defp execute({:cancel_invoke, %CancelInvoke{invoke_id: invoke_id}}, context) do
    :ok = Handler.perform_cancel(SetAside, invoke_id, handler_ctx(context.execution_id))
  end

  defp execute({:send_delayed, %SendDelayed{target: nil} = effect}, context) do
    {:ok, %Oban.Job{}} = StatifierOban.Timer.schedule(config(), context.execution_id, effect)
    :ok
  end

  defp execute({:cancel, %Cancel{} = effect}, context) do
    {:ok, _count} = StatifierOban.Timer.cancel(config(), context.execution_id, effect)
    :ok
  end

  defp execute(_effect, _context), do: :ok

  @spec handler_ctx(String.t()) :: Statifier.Invoke.Handler.ctx()
  defp handler_ctx(execution_id),
    do: %{session_id: execution_id, invoke_types: Types.new(types: []), invoke_handlers: %{}}

  # ----------------------------------------------------------- the output

  @spec trace_line(Storage.input()) :: String.t()
  defp trace_line(%{seq: seq, door: door, event: nil}),
    do: "  #{seq} #{door} (the log was closed here)"

  defp trace_line(%{seq: seq, door: door, event: event}),
    do: "  #{seq} #{door} #{event.name}"

  @spec pins() :: String.t()
  defp pins do
    ~w(statifier statifier_persistence statifier_oban statifier_blocks statifier_router)a
    |> Enum.map_join(", ", fn app -> "#{app} #{Application.spec(app, :vsn)}" end)
  end

  @spec new_execution_id() :: String.t()
  defp new_execution_id,
    do: "first_workflow_" <> (8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))

  @spec default_hold() :: map()
  defp default_hold,
    do: %{"patron" => "p-1042", "copy" => "c-2291", "branch" => "Eastside branch"}
end
