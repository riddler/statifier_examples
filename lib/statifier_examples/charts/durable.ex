defmodule StatifierExamples.Charts.Durable do
  @moduledoc """
  One durable run of one compiled document, driven through
  `StatifierPersistence.Runs`: load, step, execute effects, persist -
  every step, with no live process holding the chart between steps.

  This is the restart demo `statifier_persistence` was built for,
  delivered in the app that embeds it. `README.md`'s "Durable runs"
  section walks it with a `kill -9`.

  ## What is durable and what is not

  Durable: the chart's position after every step, the run's status, and
  the account `myapp:provision` writes. Those live in SQLite and a killed
  server finds all three exactly where it left them.

  Not durable: the *feed*. Rows are derived from the effects a step
  returns, and effects are not stored - so a resumed run opens with one
  row saying it was picked up, the marks the loaded position implies, and
  then narrates everything that happens from there. Storing the narration
  would be a second write path for something the position already implies,
  and this app would rather show the seam than paper over it.

  ## The drive loop

  `StatifierPersistence.Runs` hands every non-lifecycle effect to an
  executor and then persists. This app's executor does two things and
  neither of them is "step the run": it records the effect for the feed,
  and it notes the `<invoke>`s it saw. Stepping happens *after* the
  stepper's tail has returned, in `drive/2` below, and that ordering is
  forced rather than stylistic - the tail runs inside
  `StatifierExamples.Charts.RunLock`'s exclusion for this run id, and a
  step issued from inside it would ask for a lock its own caller is
  holding.

  So one press of an event button is: step, drain what the executor saw,
  perform each call the chart made, step again with each answer, repeat
  until the chart asks for nothing more. `Statifier.Session` runs the same
  loop; the difference is that every turn of it here leaves a row in
  `statifier_runs` that survives the process.

  The executor communicates through the driving process' own mailbox. It
  is called synchronously, inside `Runs.create/4` and `Runs.step/5`, in
  this very process, so a message tagged with the run id and drained with
  a zero timeout is an ordered buffer that needs no second process and
  cannot outlive the turn that filled it.

  ## The effects the executor performs

  For the trace effects, answering `:ok` is the whole truth - they are
  observations. Two are not: a `<send delay=...>` and the `<cancel>` the
  compiler emits to take it back down are handed to
  `StatifierExamples.Charts.Timers`, which stores them as Oban jobs, so
  the wizard's abandonment reminder outlives the node that armed it. When
  such a job fires it comes back through `deliver/2` below, which is the
  same drive loop entered from a process that has never seen this run.

  A schedule that fails raises rather than answering `{:error, _}`: the
  stepper re-enters an executor failure as `error.communication`, so an
  infrastructure fact returned as an error would steer the chart.

  ## Serialization

  Every entry point passes `serialization: {RunLock, RunLock}` explicitly.
  It has to: the default strategy asks the adapter for `lock_run/3` and
  `StatifierExamples.Persistence` does not export it, so the default
  refuses with `{:error, {:serialization, :not_supported}}` before
  anything runs. `StatifierExamples.Charts.RunLock`'s moduledoc has the
  reasoning; this module is the caller that would otherwise get the
  refusal.
  """

  alias Statifier.Effect.Invoke
  alias Statifier.{Event, Machine}
  alias Statifier.Invoke.Types
  alias StatifierBlocks.{Compiled, Compiler, Document}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Fixture, Run, RunLock, Timers}
  alias StatifierPersistence.{Runs, Storage}

  # The run-record metadata key that says which shipped fixture a run is a
  # run OF. It is the only thing a fired timer job carries back into a
  # cold node that can name the chart again - the job itself holds a run
  # id and an event, and a chart is neither.
  @fixture_key "fixture"

  @type t :: %__MODULE__{
          run_id: String.t(),
          store: Storage.t(),
          machine: Machine.t()
        }

  @enforce_keys [:run_id, :store, :machine]
  defstruct [:run_id, :store, :machine]

  @typedoc "A driver and the reading it produced, threaded together."
  @type driven :: {t(), Run.t()}

  @doc """
  Starts a durable run of `compiled` and drives it to its first rest.

  `run_id` is the caller's opaque key (ADR-0004 decision 2) and this app
  puts it in the page URL, which is what makes a run something a reader
  can come back to. Creating one that already exists is the adapter's
  atomic `:run_exists` refusal, not a pre-check.

  `fixture_key` is recorded in the run's metadata, and it is what
  `deliver/2` reads to rebuild the chart when a timer fires on a node
  that has never seen this run. It is optional because a run of a
  document that is not a shipped fixture has no key to record - such a
  run steps and resumes exactly as before, and a timer fired for it is
  discarded rather than delivered, which `deliver/2` says in its own
  words.
  """
  @spec start(Compiled.t(), Document.t(), String.t(), String.t() | nil) ::
          {:ok, driven()} | {:error, term()}
  def start(compiled, document, run_id, fixture_key \\ nil)

  def start(%Compiled{} = compiled, %Document{} = document, run_id, fixture_key)
      when is_binary(run_id) do
    with {:ok, machine} <- Statifier.compile(compiled.scxml),
         {:ok, store} <- store() do
      durable = %__MODULE__{run_id: run_id, store: store, machine: machine}
      run = Run.reading(machine, compiled, document, run_id)
      run = Run.note(run, :started, "Run started", run_id)

      drive(durable, run, create_run(store, run_id, machine, fixture_key))
    end
  end

  @doc """
  Picks a stored run back up: the same document, the same run id, a fresh
  process, and whatever the last step left in `statifier_runs`.

  Nothing is stepped. The position is loaded so the page can paint the
  marks the run is actually sitting on, and the reading opens with a row
  saying where it came from. Continuing is the reader's next press.

  A run id nobody stored is `{:error, :run_not_found}`. A document edited
  since the run started is `{:error, {:identity_mismatch, stored,
  supplied}}` out of the storage layer's own guard, which is the answer
  this app wants: resuming a run on a chart that is no longer the chart it
  ran on is exactly the thing chart identity exists to refuse.
  """
  @spec resume(Compiled.t(), Document.t(), String.t()) :: {:ok, driven()} | {:error, term()}
  def resume(%Compiled{} = compiled, %Document{} = document, run_id) when is_binary(run_id) do
    with {:ok, machine} <- Statifier.compile(compiled.scxml),
         {:ok, store} <- store(),
         {:ok, record} <- Storage.fetch_run(store, run_id),
         {:ok, machine_state} <- Storage.load_run_position(store, run_id, machine) do
      durable = %__MODULE__{run_id: run_id, store: store, machine: machine}

      run =
        machine
        |> Run.reading(compiled, document, run_id)
        |> Run.note(:started, "Run resumed from storage", "#{run_id} (#{record.status})")
        |> Run.absorb({:effect, {:trace, stable(machine_state)}})
        |> resumed_status(record.status)

      {:ok, {durable, run}}
    end
  end

  @doc """
  Delivers one external event and drives the run to its next rest.
  """
  @spec send_event(t(), Run.t(), String.t()) :: {:ok, driven()} | {:error, term()}
  def send_event(%__MODULE__{} = durable, %Run{} = run, name) when is_binary(name) do
    drive(durable, run, step(durable, Event.external(name)))
  end

  @doc """
  Abandons the run: the one terminal transition the host makes rather than
  the chart (ADR-0004 decision 6). The stored position is left exactly
  where it was, so the record says who stopped it and the chart's own last
  word is not overwritten.
  """
  @spec abandon(t()) :: :ok
  def abandon(%__MODULE__{} = durable) do
    _result =
      Runs.fail(durable.store, durable.run_id, "host:stopped", serialization: serialization())

    :ok
  end

  @doc """
  A fresh run id. A UUID's worth of randomness, hex, no dashes: it goes in
  a URL and in a fictional email address, and both read better without.
  """
  @spec new_run_id() :: String.t()
  def new_run_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  @doc """
  The one compile recipe a durable run's chart identity is keyed on.

  Every place this app compiles a document it intends to run goes through
  here, and that is load bearing rather than tidy. `:declare` and
  `terminate: true` both change the generated bytes, and the bytes are
  what the content hash is taken over, so a second spelling of this call
  that dropped either one would compile a chart the storage layer refuses
  to resume onto. The page compiles the document on its canvas; a fired
  timer compiles the fixture it was shipped from; the two agree because
  there is one call.
  """
  @spec compile(Document.t(), [Fixture.declaration()]) ::
          {:ok, Compiled.t()} | {:error, [Compiler.Finding.t()]}
  def compile(%Document{} = document, declare) when is_list(declare) do
    Compiler.compile(document, Charts.palette(),
      known_invoke_types: Charts.invoke_types(),
      declare: declare,
      terminate: true
    )
  end

  @doc """
  Feeds one fired durable timer's event back into a stored run.

  The cold entry point: everything it is given is a run id and an event
  name, and everything else - which chart, where the run had got to, what
  it does next - comes back out of SQLite. That is what makes the
  wizard's reminder survive a restart, and it is why this function takes
  no `%__MODULE__{}`: the process that armed the timer is gone.

  `:delivered` when the event was fed back, `{:discarded, reason}` when
  it was not. Discarding is the ordinary answer for a run that is no
  longer live (spec 6.2, st-ADR-0054 decision 4) and for a chart this app
  can no longer rebuild;
  `StatifierExamples.Charts.Timers.Delivery`'s moduledoc walks the
  reasons. Anything else - a database that is not there - raises out of
  the layer below and is retried by Oban, which is the right answer to a
  fact about the node rather than about the run.

  A delivered event is broadcast on `topic/1`, so a page that happens to
  be showing this run redraws instead of waiting for someone to reload
  it. Nothing here depends on anyone listening.
  """
  @spec deliver(String.t(), String.t()) :: :delivered | {:discarded, term()}
  def deliver(run_id, event) when is_binary(run_id) and is_binary(event) do
    with {:ok, store} <- store(),
         {:ok, record} <- Storage.fetch_run(store, run_id),
         :active <- record.status,
         {:ok, fixture} <- fixture_for(record),
         {:ok, compiled} <- compile(fixture.document, fixture.declare),
         {:ok, driven} <- resume(compiled, fixture.document, run_id),
         {:ok, {durable, run}} <- continue(driven, event) do
      broadcast(run_id, {durable, run})

      :delivered
    else
      :error -> {:discarded, :chart_unknown}
      {:error, reason} -> {:discarded, reason}
      status when is_atom(status) -> {:discarded, status}
    end
  end

  @doc """
  The PubSub topic one run's out-of-band advances are announced on.

  A run id and not a page: which processes are showing a run is not
  something a background job can know, and the run id is the one name
  both ends already have.
  """
  @spec topic(String.t()) :: String.t()
  def topic(run_id) when is_binary(run_id), do: "run:" <> run_id

  @spec continue(driven(), String.t()) :: {:ok, driven()} | {:error, term()}
  defp continue({durable, run}, event), do: send_event(durable, run, event)

  @spec broadcast(String.t(), driven()) :: :ok
  defp broadcast(run_id, driven) do
    Phoenix.PubSub.broadcast(
      StatifierExamples.PubSub,
      topic(run_id),
      {:run_advanced, run_id, driven}
    )
  end

  # A run started from a document that is not a shipped fixture recorded
  # no key, and a key whose fixture was renamed away resolves to nothing.
  # Both are `:error`, which `deliver/2` reports as `:chart_unknown`.
  #
  # The record's `metadata` is `%{}` and never `nil` when a caller supplied
  # none (the storage contract's ADR-0006 decision 1), so there is no
  # absent-map arm to write here.
  @spec fixture_for(map()) :: {:ok, Fixture.t()} | :error
  defp fixture_for(record) do
    case Map.get(record.metadata, @fixture_key) do
      key when is_binary(key) -> Charts.fixture(key)
      _absent -> :error
    end
  end

  # ------------------------------------------------------------- the loop

  # One turn: fold what the executor saw into the reading, then answer
  # every call the chart made and step again for each answer. Recursion
  # ends when a turn produces no `<invoke>`, which is what "the chart is
  # waiting on the outside world" looks like from here.
  @spec drive(t(), Run.t(), term()) :: {:ok, driven()} | {:error, term()}
  defp drive(durable, run, {:ok, record, _machine_state}) do
    {run, invokes} = absorb_effects(durable, run)
    run = finish(run, record.status)

    case invokes do
      [] -> {:ok, {durable, run}}
      _pending -> answer(durable, run, invokes)
    end
  end

  defp drive(durable, run, {:discarded, record}) do
    {run, _invokes} = absorb_effects(durable, run)

    {:ok, {durable, finish(run, record.status)}}
  end

  defp drive(_durable, _run, {:error, reason}), do: {:error, reason}

  @spec answer(t(), Run.t(), [Invoke.t()]) :: {:ok, driven()} | {:error, term()}
  defp answer(durable, run, invokes) do
    Enum.reduce_while(invokes, {:ok, {durable, run}}, fn invoke, {:ok, {durable, run}} ->
      case answer_one(durable, run, invoke) do
        {:ok, driven} -> {:cont, {:ok, driven}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec answer_one(t(), Run.t(), Invoke.t()) :: {:ok, driven()} | {:error, term()}
  defp answer_one(durable, run, %Invoke{} = invoke) do
    context = %{run_id: durable.run_id}

    case Charts.dispatch(invoke.type, params(invoke.params), context) do
      {:ok, donedata} ->
        run = Run.note(run, :performed, "Performed", performed(invoke, donedata))

        drive(durable, run, step(durable, done_event(durable, invoke, donedata)))

      {:error, reason} ->
        run = Run.note(run, :performed, "Call refused", "#{invoke.type}: #{inspect(reason)}")

        drive(durable, run, step(durable, failure_event(durable, invoke, reason)))
    end
  end

  @spec step(t(), Event.t()) :: term()
  defp step(durable, event) do
    Runs.step(durable.store, durable.run_id, durable.machine, event, step_opts(durable.run_id))
  end

  # The create is its own one-line function so that the suppression below
  # reaches exactly this call and nothing else.
  #
  # `StatifierPersistence.Runs.create/4` declares `[Runs.opt()]` and its
  # `executor:` is REQUIRED - `Keyword.fetch!/2` on the first line. But the
  # body then hands the same list to
  # `StatifierPersistence.Storage.check_metadata/2`, whose contract is the
  # much narrower `[Storage.run_write_opt()]`
  # (`:failure` / `:metadata` / `:position`), so the success typing
  # dialyzer derives for `create/4` accepts no `executor:` at all and every
  # correct call is reported as one that "will never return". `step/5`,
  # which does not call `check_metadata/2`, is clean.
  #
  # That is an upstream spec inconsistency in `statifier_persistence`, not
  # a fact about this app's options: the call is correct, it runs, and
  # `StatifierExamples.Charts.DurableTest` asserts what it produces. The
  # finding belongs upstream and is reported there; suppressing it on a
  # three-line function is the smallest thing that does not either hide it
  # or blind `start/3`.
  @dialyzer {:nowarn_function, create_run: 4}
  @spec create_run(Storage.t(), String.t(), Machine.t(), String.t() | nil) :: term()
  defp create_run(store, run_id, machine, fixture_key) do
    Runs.create(store, run_id, machine, create_opts(run_id, fixture_key))
  end

  @spec create_opts(String.t(), String.t() | nil) :: keyword()
  defp create_opts(run_id, fixture_key) do
    [
      executor: executor(run_id),
      initialize: [trace: true, invoke_types: invoke_types()],
      metadata: metadata(fixture_key),
      serialization: serialization()
    ]
  end

  @spec metadata(String.t() | nil) :: %{optional(String.t()) => String.t()}
  defp metadata(nil), do: %{}
  defp metadata(fixture_key) when is_binary(fixture_key), do: %{@fixture_key => fixture_key}

  @spec step_opts(String.t()) :: keyword()
  defp step_opts(run_id) do
    [executor: executor(run_id), invoke_types: invoke_types(), serialization: serialization()]
  end

  # `Statifier.Session` builds exactly these two events for an answered and
  # a refused call (6.4.3: an invocation's answer is an external event), so
  # a durable driver that built them differently would be a chart running
  # one way in a session and another way in storage.
  @spec done_event(t(), Invoke.t(), map()) :: Event.t()
  defp done_event(_durable, %Invoke{invoke_id: invoke_id}, donedata) do
    Event.external("done.invoke." <> invoke_id, data: donedata, invokeid: invoke_id)
  end

  @spec failure_event(t(), Invoke.t(), term()) :: Event.t()
  defp failure_event(_durable, %Invoke{invoke_id: invoke_id}, reason) do
    Event.external("error.communication.invoke." <> invoke_id,
      data: %{"reason" => inspect(reason)},
      invokeid: invoke_id
    )
  end

  # ---------------------------------------------------------- the executor

  # An arity-2 fun rather than a module, because what it closes over - the
  # run id it tags with and the process it reports to - is per-call state a
  # module would have to be handed some other way.
  @spec executor(String.t()) :: StatifierPersistence.Executor.t()
  defp executor(run_id) do
    reader = self()

    fn effect, _context ->
      :ok = Timers.consume(run_id, effect)

      send(reader, {:durable_effect, run_id, effect})

      :ok
    end
  end

  # Drains this turn's effects, in the order the stepper handed them over,
  # folding each into the reading and keeping the `<invoke>`s aside.
  @spec absorb_effects(t(), Run.t()) :: {Run.t(), [Invoke.t()]}
  defp absorb_effects(durable, run) do
    effects = drain(durable.run_id, [])

    run = Enum.reduce(effects, run, &Run.absorb(&2, {:effect, &1}))
    invokes = for {:invoke, %Invoke{} = invoke} <- effects, do: invoke

    {run, invokes}
  end

  @spec drain(String.t(), [Statifier.Effect.t()]) :: [Statifier.Effect.t()]
  defp drain(run_id, acc) do
    receive do
      {:durable_effect, ^run_id, effect} -> drain(run_id, [effect | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # ------------------------------------------------------------- readings

  # The stepper reports the run's status; the reading speaks the vocabulary
  # `Run.absorb/2`'s `{:halted, reason}` message uses, so a durable run and
  # a session run finish with the same row and the same status word.
  @spec finish(Run.t(), atom()) :: Run.t()
  defp finish(run, :completed), do: Run.absorb(run, {:halted, :done})
  defp finish(run, :failed), do: Run.absorb(run, {:halted, :cancelled})
  defp finish(run, :active), do: run

  @spec resumed_status(Run.t(), atom()) :: Run.t()
  defp resumed_status(run, :active), do: run
  defp resumed_status(run, status), do: finish(run, status)

  # A resumed run has no entry set to fold - nothing entered, it was
  # already there - so the marks come from the loaded configuration, which
  # is exactly what `MacrostepStable` carries. Building one is how the
  # reading learns where the run is sitting without a second derivation
  # living here.
  @spec stable(Statifier.MachineState.t()) :: Statifier.Effect.Trace.MacrostepStable.t()
  defp stable(machine_state) do
    %Statifier.Effect.Trace.MacrostepStable{
      configuration: machine_state.configuration,
      macrostep: machine_state.macrostep,
      microstep: machine_state.microstep,
      round: machine_state.round
    }
  end

  @spec performed(Invoke.t(), map()) :: String.t()
  defp performed(%Invoke{type: type}, donedata) when map_size(donedata) == 0, do: type

  defp performed(%Invoke{type: type}, donedata) do
    detail = Enum.map_join(Enum.sort(donedata), ", ", fn {key, value} -> "#{key}=#{value}" end)

    "#{type} -> #{detail}"
  end

  @spec params(term()) :: map()
  defp params(params) when is_map(params), do: params
  defp params(_absent), do: %{}

  # ----------------------------------------------------------- the wiring

  @spec store() :: {:ok, Storage.t()} | {:error, term()}
  defp store, do: Storage.new(StatifierExamples.Persistence, [])

  @spec serialization() :: {module(), GenServer.server()}
  defp serialization, do: {RunLock, RunLock}

  @spec invoke_types() :: Types.t()
  defp invoke_types, do: Types.new(types: Charts.invoke_types())
end
