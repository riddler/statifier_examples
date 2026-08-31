defmodule StatifierExamples.Charts.Durable do
  @moduledoc """
  One durable run of one compiled document, driven through
  `StatifierPersistence.Driver`: load, step, execute effects, persist -
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

  ## The drive loop is upstream's

  One press of an event button is: step, perform each call the chart made,
  step again with each answer, repeat until the chart asks for nothing
  more. `Statifier.Session` runs that loop for a live session and
  `StatifierPersistence.Driver` runs it over `StatifierPersistence.Runs`,
  which is what this module calls. Every turn of it leaves a row in
  `statifier_runs` that survives the process.

  This app wrote that loop itself until se-4dt.3, and getting it out of
  here was worth more than the lines it saved: the app's hand-built answer
  events were **not** the ones `Statifier.Session` builds. They carried no
  `origin`/`origintype` pair, and a refused call reported `inspect(reason)`
  under a lone `"reason"` key rather than st-ADR-0068's
  `reason`/`attempts`/`detail`. The same chart, answered the same way,
  meant one thing in a session and another in storage. Upstream builds both
  events from `Statifier.Session`'s own writers, so the divergence is gone
  rather than fixed twice.

  ## The two funs this app hands the driver

  What stays here is the part that is genuinely this host's.

  `effects:` is an executor - every non-lifecycle effect, in the order the
  stepper hands them over. It does two things and neither of them is "step
  the run": it records the effect for the feed, and it lets
  `StatifierExamples.Charts.Timers` claim the ones that are timers.

  `dispatch:` performs one `<invoke>`, through
  `StatifierExamples.Charts.dispatch/3` with the run id as its context, and
  records the answer for the feed. What the *chart* is told is the driver's
  to build.

  Both report through the driving process' own mailbox. They are called
  synchronously, inside the driver's own `Runs.create/4` and `Runs.step/5`,
  in this very process, so a message tagged with the run id and drained
  with a zero timeout is an ordered buffer that needs no second process and
  cannot outlive the drive that filled it. It is drained once, after the
  drive has returned, so a feed row's place in it is the order things
  happened in across every turn rather than within one.

  That the driver reports only the *final* step's result is all a reading
  needs: a run's status is `:active` until it is terminal, so every
  intermediate turn's status word is the one this module already ignores.

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

  The driver is built with `serialization: {RunLock, RunLock}` and
  `abandon/1`, which does not go through it, passes the same pair by hand.
  They have to: the default strategy asks the adapter for `lock_run/3` and
  `StatifierExamples.Persistence` does not export it, so the default
  refuses with `{:error, {:serialization, :not_supported}}` before
  anything runs. `StatifierExamples.Charts.RunLock`'s moduledoc has the
  reasoning; this module is the caller that would otherwise get the
  refusal.
  """

  alias Statifier.{Event, Machine}
  alias Statifier.Invoke.Types
  alias StatifierBlocks.{Compiled, Compiler, Document}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Fixture, Run, RunLock, Subchart, Timers}
  alias StatifierPersistence.{Driver, Runs, Storage}

  # The run-record metadata key that says which shipped fixture a run is a
  # run OF. It is the only thing a fired timer job carries back into a
  # cold node that can name the chart again - the job itself holds a run
  # id and an event, and a chart is neither.
  @fixture_key "fixture"

  # The run-record metadata key carrying the host-provenance pin: which
  # child chart each `core.subchart` in this run's document resolved to
  # when the run was created (campaign-023 ruling R-d). See
  # `StatifierExamples.Charts.Subchart.identities/1`, which builds it.
  @subcharts_key "subcharts"

  @type t :: %__MODULE__{
          run_id: String.t(),
          store: Storage.t(),
          machine: Machine.t()
        }

  @enforce_keys [:run_id, :store, :machine]
  defstruct [:run_id, :store, :machine]

  @typedoc "A driver and the reading it produced, threaded together."
  @type driven :: {t(), Run.t()}

  # One entry in a drive's buffer: an effect the stepper produced, or a row
  # the host wrote about a call it performed. Both shapes travel the one
  # mailbox so the feed reads in the order things actually happened.
  @typep buffered ::
           {:effect, Statifier.Effect.t()} | {:note, Run.entry_kind(), String.t(), String.t()}

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

  ## What else the metadata carries: the subchart pin

  A `core.subchart` names its child by **document id**, which is stable
  across every revision of that child, so the run record would otherwise
  say nothing about which revision this run actually ran. Campaign-023
  ruling R-d puts it in the metadata at create: one content hash per
  document the chart names as a child, taken over the child exactly as the
  handler compiles it (`StatifierExamples.Charts.Subchart.identities/1`).

  It is written at create and never rewritten, which is what makes it a
  pin rather than a cache. A document naming no child records no key at
  all - most runs of this app - and a child that cannot be resolved or
  compiled today is left out rather than recorded as an error, because a
  pin to nothing is not a pin.
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

      settle(
        durable,
        run,
        Driver.create(driver(durable), run_id, create_opts(fixture_key, document))
      )
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
    event = Event.external(name)

    settle(durable, run, Driver.send_event(driver(durable), durable.run_id, event))
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

  # ----------------------------------------------------------- the driver

  # The driver, rebuilt per entry point rather than held on the struct:
  # both funs below close over `self()`, and the process that resumes a run
  # is routinely not the one that started it (a fired timer's Oban worker,
  # a second LiveView). A driver carried across processes would report into
  # a mailbox nobody is draining.
  @spec driver(t()) :: Driver.t()
  defp driver(%__MODULE__{} = durable) do
    Driver.new(durable.store, durable.machine,
      dispatch: dispatch(durable.run_id),
      effects: executor(durable.run_id),
      invoke_types: invoke_types(),
      serialization: serialization()
    )
  end

  @spec create_opts(String.t() | nil, Document.t()) :: keyword()
  defp create_opts(fixture_key, document) do
    [initialize: [trace: true], metadata: metadata(fixture_key, document)]
  end

  # The two facts a created run records about the chart it is a run of:
  # which shipped fixture it came from, for a cold node rebuilding it, and
  # which child charts its subcharts resolved to, for a reader asking
  # afterwards what actually ran (campaign-023 ruling R-d).
  @spec metadata(String.t() | nil, Document.t()) :: %{optional(String.t()) => term()}
  defp metadata(fixture_key, document) do
    %{}
    |> put_present(@fixture_key, fixture_key)
    |> put_present(@subcharts_key, subcharts(document))
  end

  @spec subcharts(Document.t()) :: %{optional(String.t()) => String.t()} | nil
  defp subcharts(%Document{} = document) do
    case Subchart.identities(document) do
      empty when empty == %{} -> nil
      identities -> identities
    end
  end

  @spec put_present(map(), String.t(), term()) :: map()
  defp put_present(metadata, _key, nil), do: metadata
  defp put_present(metadata, key, value), do: Map.put(metadata, key, value)

  # Folds one drive's whole buffer into the reading and finishes it on the
  # status the last durable step wrote.
  #
  # The buffer is drained on the error arm too, and thrown away. Nothing
  # reads it - the page keeps the reading it had - and a drive that failed
  # part way through has still filled it, so leaving it would let a later
  # drive in this process narrate a run that is over.
  @spec settle(t(), Run.t(), Driver.result()) :: {:ok, driven()} | {:error, term()}
  defp settle(durable, run, {:ok, record, _machine_state}), do: rest(durable, run, record.status)
  defp settle(durable, run, {:discarded, record}), do: rest(durable, run, record.status)

  defp settle(durable, _run, {:error, reason}) do
    _discarded = drain(durable.run_id, [])

    {:error, reason}
  end

  @spec rest(t(), Run.t(), atom()) :: {:ok, driven()}
  defp rest(durable, run, status) do
    run =
      durable.run_id
      |> drain([])
      |> Enum.reduce(run, &fold(&2, &1))
      |> finish(status)

    {:ok, {durable, run}}
  end

  @spec fold(Run.t(), buffered()) :: Run.t()
  defp fold(run, {:effect, effect}), do: Run.absorb(run, {:effect, effect})
  defp fold(run, {:note, kind, label, detail}), do: Run.note(run, kind, label, detail)

  # ------------------------------------------------------ the host's funs

  # An arity-2 fun rather than a module, because what it closes over - the
  # run id it tags with and the process it reports to - is per-call state a
  # module would have to be handed some other way.
  @spec executor(String.t()) :: StatifierPersistence.Executor.t()
  defp executor(run_id) do
    reader = self()

    fn effect, _context ->
      :ok = Timers.consume(run_id, effect)

      send(reader, {:durable_buffered, run_id, {:effect, effect}})

      :ok
    end
  end

  # Performs one call and says so in the feed. What the *chart* is told is
  # `StatifierPersistence.Driver`'s to build, from `Statifier.Session`'s own
  # writers, which is the whole reason this returns an answer rather than
  # an event.
  #
  # A refusal is answered with st-ADR-0068's `failure` keyword list. Only
  # `:reason` is filled: this app makes one attempt through
  # `Charts.dispatch/3` and has no detail to add, and the driver spells an
  # absent key `:undefined` rather than `nil`.
  @spec dispatch(String.t()) :: Driver.dispatch()
  defp dispatch(run_id) do
    reader = self()
    context = %{run_id: run_id}

    fn type, params, _executor_context ->
      case Charts.dispatch(type, params(params), context) do
        {:ok, donedata} ->
          note(reader, run_id, "Performed", performed(type, donedata))

          {:ok, donedata}

        {:error, refusal} ->
          reason = reason(refusal)
          note(reader, run_id, "Call refused", "#{type}: #{reason}")

          {:error, [reason: reason]}
      end
    end
  end

  # The failure class the chart reads as `_event.data.reason`, spelled the
  # way `Statifier.Invoke.SyncHandler.Adapter` spells the same refusal for
  # a session run of the same chart. The adapter keeps its copy private, so
  # this is the one place the app repeats it, and a durable run and a
  # session run answering the same refusal differently is exactly what
  # se-4dt.3 was closing.
  #
  # One clause per way `Charts.dispatch/3` refuses, and no fall-through:
  # dialyzer reports a binary arm or an `inspect/1` default as unreachable
  # against that spec, which is what makes this the place a widened refusal
  # surfaces rather than somewhere the new shape is quietly `inspect/1`-ed.
  # se-4dt.4 widened it - `statifier_blocks:subchart` is registered and is
  # not a sync call - and this is where that showed up, exactly as the
  # paragraph above predicted.
  @spec reason({:unknown_invoke_type | :durable_subchart_unsupported, String.t()}) :: String.t()
  defp reason({:unknown_invoke_type, type}), do: "unknown_invoke_type:#{type}"
  # The subchart refusal names no type: unlike `:unknown_invoke_type`, where
  # the type IS what went wrong, this refusal is about one constant type
  # the note beside it already spells.
  defp reason({:durable_subchart_unsupported, _type}), do: "durable_subchart_unsupported"

  @spec note(pid(), String.t(), String.t(), String.t()) :: :ok
  defp note(reader, run_id, label, detail) do
    send(reader, {:durable_buffered, run_id, {:note, :performed, label, detail}})

    :ok
  end

  # Drains this drive's buffer, in the order the two funs above filled it.
  # One `receive` over both shapes rather than two passes: the mailbox is
  # scanned in arrival order and the first message matching either clause
  # is taken, so a `Performed` row keeps its place beside the effects of
  # the turn it belongs to.
  @spec drain(String.t(), [buffered()]) :: [buffered()]
  defp drain(run_id, acc) do
    receive do
      {:durable_buffered, ^run_id, item} -> drain(run_id, [item | acc])
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

  @spec performed(String.t(), map()) :: String.t()
  defp performed(type, donedata) when map_size(donedata) == 0, do: type

  defp performed(type, donedata) do
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
