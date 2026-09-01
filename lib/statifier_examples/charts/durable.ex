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
  stepper hands them over. It does three things and none of them is "step
  the run": it records the effect for the feed, it lets
  `StatifierExamples.Charts.Timers` claim the ones that are timers, and it
  lets `StatifierExamples.Charts.AsyncCalls` claim the ones that start or
  cancel an asynchronous invocation.

  `dispatch:` performs one `<invoke>`, through
  `StatifierExamples.Charts.dispatch/3` with the run id as its context, and
  records the answer for the feed. What the *chart* is told is the driver's
  to build.

  There is a third, and it is not a fun: `chart_resolver:` is how a driver
  reaches a chart it does not hold, which it needs when a durable subchart
  child finishes and its **parent** has to be answered. See
  `resolve_chart/1`.

  ## A subchart is not answered here either: it starts its own run

  `statifier_blocks:subchart` never reaches
  `StatifierExamples.Charts.dispatch/3`. The dispatch fun routes it to
  `StatifierBlocks.Runtime.DurableSubchart`, which resolves the child
  document this host publishes and hands back
  `{:start_child, resolved, {:invoke, invoke}}` - the same instruction
  `Statifier.Session` gets, unrenamed. The driver executes it by creating
  the child as **its own persisted run**, inside the parent's own
  exclusion, then answers `:pending`: the parent reaches quiescence with
  the invocation live, exactly as it does for an asynchronous call below.

  The child is an ordinary run in every way that matters to this app. It
  has its own row in `statifier_runs`, its own position, its own status,
  and a run id a reader can put in the page URL - `resume/3` picks it up
  with no idea it is anybody's child. What makes it a child is one key in
  its metadata, `StatifierPersistence.Run.Linkage`'s, naming the parent
  run, the invocation, and the child's own content hash.

  Two things follow from the linkage and this module does both. When the
  child reaches a terminal status, the driver answers the parent's
  invocation through `done_invocation/5` or `failed_invocation/5` - which
  needs the parent's chart, hence `chart_resolver:`. And when a parent is
  stopped by its host, its live children have to go with it, which is what
  `abandon/1` cascades.

  ## One call is not answered here at all

  `StatifierExamples.Charts.AsyncCalls` claims one of this app's calls -
  the wizard's company-details step - and for that one `dispatch:` answers
  `:pending` instead of a donedata map. Nothing is buffered, the drive
  reaches quiescence, and the position persists with the invocation still
  live in `active_invocations`: the run rests durably in the middle of a
  call, with no process holding it and an Oban job carrying the work.
  Whatever eventually finishes that job answers through
  `complete_invocation/3` or `fail_invocation/3` below, which are
  `deliver/2`'s siblings and just as cold. That arm is
  `StatifierPersistence.Driver`'s ADR-0007, and that module's moduledoc
  says why this app has one such call and which one.

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
  alias Statifier.Machine.Identity
  alias StatifierBlocks.{Compiled, Compiler, Document}
  alias StatifierBlocks.Runtime
  alias StatifierBlocks.Runtime.DurableSubchart
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Fixture, Run, RunLock, Subchart, Timers, Tracing}
  alias StatifierPersistence.{Driver, Runs, Storage}
  alias StatifierPersistence.Run.Linkage

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
  Picks a stored run back up knowing only its id: the chart is read out of
  the record rather than supplied.

  `resume/3`'s sibling for the caller that has a run id and nothing else,
  which is every caller that got one out of a URL. It is what makes a
  durable subchart child openable at all: the page compiles the document on
  its canvas with `compile/2`'s root recipe, and a child run's stored
  identity is keyed on the **child** recipe (`child_use: true`, no
  declarations, no `terminate:`), so resuming a child with the page's own
  compile is refused as `{:error, {:identity_mismatch, _, _}}` - correctly,
  and unhelpfully, since the two are compiles of the same document.

  `chart_for/1` picks the recipe off the stored record, which is the one
  place that knowledge lives. The document comes back with the driven pair
  because a caller resuming by id has no other way to know which one it
  got.

  `{:error, :chart_unknown}` for a run of a chart this app no longer
  ships; everything else is `resume/3`'s.
  """
  @spec resume(String.t()) :: {:ok, {driven(), Document.t()}} | {:error, term()}
  def resume(run_id) when is_binary(run_id) do
    with {:ok, store} <- store(),
         {:ok, record} <- Storage.fetch_run(store, run_id),
         {:ok, {compiled, document}} <- chart_for(record),
         {:ok, driven} <- resume(compiled, document, run_id) do
      {:ok, {driven, document}}
    else
      :error -> {:error, :chart_unknown}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Delivers one external event and drives the run to its next rest.

  The event carries this host's `caller_context` stamp (st-ADR-0063): the
  current trace context in W3C text form, or `nil` when nothing is being
  traced. The core copies it onto every effect this event's macrostep
  produces, `statifier_oban` stores it on the job row untouched, and it
  comes back on the fired event days later - which is what gives a fired
  timer a link to the trace that armed it instead of leaving it an
  unlinked root. `StatifierExamples.Charts.Tracing` holds the reasoning
  and the wire form.

  This is the only place the stamp is applied, and it covers the cold
  re-entry doors too: `deliver/2` and `complete_invocation/3` both drive
  the run back through here.
  """
  @spec send_event(t(), Run.t(), String.t()) :: {:ok, driven()} | {:error, term()}
  def send_event(%__MODULE__{} = durable, %Run{} = run, name) when is_binary(name) do
    event = Event.external(name, caller_context: Tracing.caller_context())

    settle(durable, run, Driver.send_event(driver(durable), durable.run_id, event))
  end

  @doc """
  Abandons the run: the one terminal transition the host makes rather than
  the chart (ADR-0004 decision 6). The stored position is left exactly
  where it was, so the record says who stopped it and the chart's own last
  word is not overwritten.

  ## It cascades into the run's durable subchart children

  A run stopped by its host while a `core.subchart` child is live would
  otherwise leave that child `active` forever: nothing is holding it, its
  parent will never be answered, and no press anywhere reaches it. So this
  walks the child subtree too, with `StatifierPersistence.Runs.cascade_cancel/3`
  over `StatifierPersistence.Run.Linkage.parent_match/1` - *every* child
  this run ever started, across every invocation, and every run linked to
  those, recursively (sp ADR-0008 decision 5).

  Cancellation retains: a cancelled child keeps its record and its stored
  position byte-identical, and only the status word changes, to
  `:cancelled`. That is deliberate on the package's part and it is what
  makes this safe to press - a cancelled child is still a run a reader can
  open and read the position of.

  The two terminal words differ, and the difference is honest rather than
  an inconsistency to smooth over: the run the host stopped is `failed`
  with `host:stopped`, because a host stopping a run is what ADR-0004
  decision 6 calls a failure, and the children are `cancelled`, because
  ADR-0008 decision 5's cascade is what happened to them.

  The parent is failed **first**. A child cancelled while its parent is
  still active could complete in the window between the two writes and
  answer a parent that is about to be stopped anyway; failing the parent
  first means that answer lands on a terminal run and is discarded, which
  is ADR-0007 decision 3's mechanism doing its job.
  """
  @spec abandon(t()) :: :ok
  def abandon(%__MODULE__{} = durable) do
    _result =
      Runs.fail(durable.store, durable.run_id, "host:stopped", serialization: serialization())

    _cancelled = cascade(durable)

    :ok
  end

  # Guarded on the store's own answer rather than on knowledge about this
  # app's adapter: `child_listing_supported?/1` is how the package asks
  # whether an adapter exports `list_runs_by_metadata/2`, and it is the same
  # guard `StatifierPersistence.Driver` puts in front of its own cascade.
  # `StatifierExamples.Persistence` does export it - that is what opts this
  # app into durable subcharts at all - so the false arm is not dead code
  # about this adapter, it is what keeps `abandon/1` correct for a host
  # that copies this module onto one that does not.
  @spec cascade(t()) :: {:ok, non_neg_integer()} | {:error, term()} | :unsupported
  defp cascade(%__MODULE__{} = durable) do
    if Storage.child_listing_supported?(durable.store) do
      Runs.cascade_cancel(durable.store, Linkage.parent_match(durable.run_id),
        serialization: serialization()
      )
    else
      :unsupported
    end
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
         {:ok, {compiled, document}} <- chart_for(record),
         {:ok, driven} <- resume(compiled, document, run_id),
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
  Answers one asynchronous invocation and drives the stored run on.

  `deliver/2`'s sibling for the other kind of out-of-band arrival: where
  that one feeds a fired timer's event into a run, this one feeds an
  invocation's own answer through
  `StatifierPersistence.Driver.done_invocation/5` - the public re-entry
  door its ADR-0007 added, which builds the same `done.invoke.<invoke_id>`
  event a live `Statifier.Session` would build and steps it inside the
  run's serialization strategy.

  Cold in exactly the way `deliver/2` is: everything it is given is a run
  id, an invocation id and a result, and which chart, where the run had
  got to and what it does next all come back out of SQLite. That is what
  makes the answer survive the restart, and it is why this takes no
  `%__MODULE__{}` - the process that started the call is gone.

  `:delivered` when the answer was fed back, `{:discarded, reason}` when
  it was not. Three reasons, and all three are ordinary:

    * the run is no longer live - it finished or was abandoned while the
      job ran;
    * the chart cannot be rebuilt - the same
      `StatifierExamples.Charts.Timers.Delivery` list, for the same
      reasons;
    * the invocation is no longer the live one under its state, which is
      spec 6.4.3's cancellation. For this app that is the wizard's
      abandonment deadline firing while the job was still running: the
      interrupt exits the invoking state, the entry leaves
      `active_invocations`, and the answer arrives for an invocation the
      chart has already stopped waiting for. The driver decides it from
      the loaded position, inside the run's own serialization strategy, so
      a cancel cannot land between the read and the step.

  The reason is the stored run's own status in all three cases, because
  that is what tells the two apart - the driver's `{:discarded, run}`
  deliberately does not (statifier_persistence ADR-0007's Consequences).
  To a job they mean the same thing: do not retry, nothing to do.

  The same discard is what makes redelivery safe: an at-least-once job
  queue answering twice finds the invocation gone the second time, because
  the chart left the invoking state on the first answer.
  """
  @spec complete_invocation(String.t(), String.t(), term()) :: :delivered | {:discarded, term()}
  def complete_invocation(run_id, invoke_id, donedata)
      when is_binary(run_id) and is_binary(invoke_id) do
    answer(run_id, invoke_id, {:done, donedata})
  end

  @doc """
  `complete_invocation/3`'s failing counterpart: reports one asynchronous
  invocation **permanently** failed, through
  `StatifierPersistence.Driver.failed_invocation/5`.

  Permanent in st-ADR-0068's sense - the host's retries are exhausted and
  no answer will follow - so the chart hears
  `error.communication.invoke.<invoke_id>` carrying `failure`'s
  `:reason`/`:attempts`/`:detail`. A transient failure never reaches here:
  `StatifierOban.Invoke.Worker` retries it, and only the attempt that
  gives up for good delivers.

  Returns and discards are `complete_invocation/3`'s.
  """
  @spec fail_invocation(String.t(), String.t(), keyword()) :: :delivered | {:discarded, term()}
  def fail_invocation(run_id, invoke_id, failure)
      when is_binary(run_id) and is_binary(invoke_id) and is_list(failure) do
    answer(run_id, invoke_id, {:failed, failure})
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

  # The cold half both re-entry doors share, and `deliver/2`'s own `with`
  # with one clause swapped: rebuild the chart from the record, resume onto
  # the stored position, then re-enter through the driver rather than
  # sending an event.
  #
  # It carries no `:active <- record.status` check of its own, and that is
  # deliberate rather than an omission. `deliver/2` has one because it
  # feeds an ordinary event and the driver would happily queue that against
  # a finished run. An invocation answer has a stricter guard already, in a
  # better place: `StatifierPersistence.Driver` reads liveness off the
  # loaded position INSIDE the run's serialization strategy, so a cancel
  # cannot land between the read and the step. A pre-check here would
  # answer the same question earlier and worse, and would hide the one that
  # counts.
  @spec answer(String.t(), String.t(), {:done, term()} | {:failed, keyword()}) ::
          :delivered | {:discarded, term()}
  defp answer(run_id, invoke_id, outcome) do
    with {:ok, store} <- store(),
         {:ok, record} <- Storage.fetch_run(store, run_id),
         {:ok, {compiled, document}} <- chart_for(record),
         {:ok, driven} <- resume(compiled, document, run_id),
         {:ok, {durable, run}} <- reenter(driven, invoke_id, outcome) do
      broadcast(run_id, {durable, run})

      :delivered
    else
      {:discarded, reason} -> {:discarded, reason}
      :error -> {:discarded, :chart_unknown}
      {:error, reason} -> {:discarded, reason}
    end
  end

  @spec reenter(driven(), String.t(), {:done, term()} | {:failed, keyword()}) ::
          {:ok, driven()} | {:discarded, term()} | {:error, term()}
  defp reenter({durable, run}, invoke_id, {:done, donedata}) do
    settle_answer(
      durable,
      run,
      Driver.done_invocation(driver(durable), durable.run_id, invoke_id, donedata)
    )
  end

  defp reenter({durable, run}, invoke_id, {:failed, failure}) do
    settle_answer(
      durable,
      run,
      Driver.failed_invocation(driver(durable), durable.run_id, invoke_id, failure)
    )
  end

  # `settle/3` for the doors, and it differs in exactly one place:
  # `{:discarded, record}` is an answer nobody wanted rather than a run to
  # keep reading, so it is reported rather than folded. The buffer is
  # drained and thrown away on both non-delivering arms, for the reason
  # `settle/3` gives - a drive that stopped part way through has still
  # filled it.
  @spec settle_answer(t(), Run.t(), Driver.result()) ::
          {:ok, driven()} | {:discarded, term()} | {:error, term()}
  defp settle_answer(durable, run, {:ok, record, _machine_state}),
    do: rest(durable, run, record.status)

  defp settle_answer(durable, _run, {:discarded, record}) do
    _discarded = drain(durable.run_id, [])

    {:discarded, record.status}
  end

  defp settle_answer(durable, _run, {:error, reason}) do
    _discarded = drain(durable.run_id, [])

    {:error, reason}
  end

  @spec broadcast(String.t(), driven()) :: :ok
  defp broadcast(run_id, driven) do
    Phoenix.PubSub.broadcast(
      StatifierExamples.PubSub,
      topic(run_id),
      {:run_advanced, run_id, driven}
    )
  end

  # The cold rebuild: which chart is `record` a run of, compiled the way
  # that run's stored identity is keyed on.
  #
  # Two answers, because this app now creates runs two ways and they record
  # different things.
  #
  # A run this app started records its fixture key, and is compiled with
  # `compile/2` - declarations and `terminate: true`. That is the arm every
  # fired timer and every asynchronous answer has always taken.
  #
  # A durable subchart child records **no** fixture key: it is created by
  # `StatifierPersistence.Driver` rather than by this module, and the
  # metadata it gets is the package's own linkage and nothing else. What it
  # does carry is its `content_hash`, and the compile that produced it is
  # the child recipe (`StatifierExamples.Charts.Subchart.child_compile/1`),
  # so the resolution is a walk over the shipped documents comparing hashes.
  #
  # Writing the fixture key onto the child instead was the other option and
  # is the wrong one: the metadata a child gets is the driver's to write,
  # and a host reaching into it would be writing into a record the package
  # owns. The hash is already there, it is already the thing identity is
  # keyed on, and matching on it is what a host is *supposed* to be able to
  # do with it.
  #
  # `:error` either way for a document this app no longer ships, which
  # `deliver/2` reports as `:chart_unknown`.
  #
  # The record's `metadata` is `%{}` and never `nil` when a caller supplied
  # none (the storage contract's ADR-0006 decision 1), so there is no
  # absent-map arm to write here.
  @spec chart_for(map()) :: {:ok, {Compiled.t(), Document.t()}} | :error
  defp chart_for(record) do
    case Map.get(record.metadata, @fixture_key) do
      key when is_binary(key) -> root_chart(key)
      _absent -> child_chart(record.content_hash)
    end
  end

  @spec root_chart(String.t()) :: {:ok, {Compiled.t(), Document.t()}} | :error
  defp root_chart(key) do
    with {:ok, fixture} <- Charts.fixture(key),
         {:ok, %Compiled{} = compiled} <- compile(fixture.document, fixture.declare) do
      {:ok, {compiled, fixture.document}}
    else
      _unresolvable -> :error
    end
  end

  @spec child_chart(String.t()) :: {:ok, {Compiled.t(), Document.t()}} | :error
  defp child_chart(content_hash) do
    Enum.find_value(Charts.fixtures(), :error, fn fixture ->
      case Subchart.child_compile(fixture.document) do
        {:ok, %Compiled{scxml: scxml} = compiled} ->
          Identity.of_source(scxml).content_hash == content_hash and
            {:ok, {compiled, fixture.document}}

        {:error, _findings} ->
          false
      end
    end)
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
      serialization: serialization(),
      chart_resolver: &resolve_chart/1
    )
  end

  # How a driver reaches a chart it does not hold (sp ADR-0008 decision 3):
  # when a durable subchart child finishes, the driver answers its parent,
  # and the parent's chart is not the child driver's own `machine`.
  #
  # The package cannot supply this and says so: a stored `chart_blob` is
  # opaque to it, and this app stores no chart blobs at all - it stores
  # positions and run records. What it does have is the shipped fixture
  # list, which is fixed at build time, so the resolution is a walk over
  # the charts this host publishes, matching on the content hash the
  # storage layer keyed the parent's record by.
  #
  # Both compiles are walked because a chart in the middle of a subchart
  # tree is both a parent and a child, and the two compiles produce
  # different bytes and therefore different hashes: a root is compiled with
  # its declarations and `terminate: true` (`compile/2`), a child with
  # `child_use: true` (`StatifierExamples.Charts.Subchart`'s recipe). A
  # single-level tree only ever needs the first; walking both is what makes
  # a nested one resolve without a second seam.
  #
  # It is recomputed per call rather than memoised, for
  # `StatifierExamples.Charts.Timers.config/0`'s reason - these are
  # constants and a cached copy is one more thing that can be stale - and
  # it can afford to be: a resolver is consulted once per run that
  # terminates with a parent, not once per step.
  @spec resolve_chart(String.t()) :: {:ok, Machine.t()} | :error
  defp resolve_chart(content_hash) when is_binary(content_hash) do
    Enum.find_value(charts(), :error, fn {hash, machine} ->
      hash == content_hash and {:ok, machine}
    end)
  end

  @spec charts() :: [{String.t(), Machine.t()}]
  defp charts do
    Enum.flat_map(Charts.fixtures(), fn fixture ->
      Enum.flat_map(
        [compile(fixture.document, fixture.declare), Subchart.child_compile(fixture.document)],
        &machine_entry/1
      )
    end)
  end

  @spec machine_entry(term()) :: [{String.t(), Machine.t()}]
  defp machine_entry({:ok, %Compiled{scxml: scxml}}) do
    case Statifier.compile(scxml) do
      {:ok, machine} -> identified(machine)
      {:error, _findings} -> []
    end
  end

  defp machine_entry(_uncompilable), do: []

  @spec identified(Machine.t()) :: [{String.t(), Machine.t()}]
  defp identified(machine) do
    case Machine.identity(machine) do
      nil -> []
      identity -> [{identity.content_hash, machine}]
    end
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
  # The two run ids `dispatch/1` describes, in the other fun. A durable
  # subchart child runs on this same executor, so a stored timer job keyed
  # on the closed-over `run_id` would arm the CHILD's 24-hour wait and its
  # abandonment reminder against the PARENT's run: they would fire, be
  # delivered to a chart with no such event, and the child would wait
  # forever for a clock nobody was holding for it. `context.run_id` is the
  # run the effect belongs to, and it is what both consumers get.
  #
  # The buffer tag stays the drive's own `run_id`, for `dispatch/1`'s
  # reason: it is what `drain/2` matches on.
  @spec executor(String.t()) :: StatifierPersistence.Executor.t()
  defp executor(run_id) do
    reader = self()

    fn effect, context ->
      :ok = Timers.consume(context.run_id, effect)
      :ok = AsyncCalls.consume(context.run_id, effect)

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
  # ## Two run ids, and which one each half uses
  #
  # A durable subchart child is driven by the driver this fun was built for,
  # with only the machine swapped (sp ADR-0008 decision 3's `create_child`),
  # so the SAME dispatch fun performs the child's calls. Two run ids are
  # therefore in play whenever a subchart is running, and they are not
  # interchangeable:
  #
  #   * `run_id`, closed over here, is the run whose *drive* this is - the
  #     one being narrated. The feed buffer is tagged with it, because
  #     `drain/2` matches on that tag and a row tagged with a child's id
  #     would sit in the mailbox until some later drive in this process
  #     picked it up and narrated a run that is over. Narrating a child's
  #     steps in the parent's feed is also what a reader watching the
  #     parent wants: it is what the child is doing on the parent's behalf.
  #
  #   * `context.run_id`, handed in per call, is the run the invocation
  #     actually BELONGS to. Everything with a consequence keys on it -
  #     which run an account row is written for, which run an asynchronous
  #     job is scoped to - because a child's `myapp:provision` writing under
  #     the parent's key, or a child's asynchronous call answered into the
  #     parent, is a real and silent corruption rather than a cosmetic one.
  #
  # The same split is in `executor/1` for the same reason.
  @spec dispatch(String.t()) :: Driver.dispatch()
  defp dispatch(run_id) do
    reader = self()

    fn type, params, dispatch_context ->
      cond do
        type == Runtime.Subchart.invoke_type() ->
          start_child(reader, run_id, type, params, dispatch_context)

        AsyncCalls.async?(type, params(params)) ->
          pending(reader, run_id, type)

        true ->
          perform(
            reader,
            run_id,
            %{run_id: dispatch_context.run_id},
            type,
            params(params)
          )
      end
    end
  end

  # The durable subchart arm. `StatifierBlocks.Runtime.DurableSubchart`
  # resolves the child document this app publishes for the `src` document
  # id, compiles it, and hands back
  # `{:start_child, resolved, {:invoke, invoke}}` - `Statifier.Session`'s
  # own instruction, unrenamed, which `StatifierPersistence.Driver`
  # executes by creating the child as its own persisted run and answering
  # `:pending` (sp ADR-0008 decision 3).
  #
  # It reads `src` off `dispatch_context.invoke`, which is why this app
  # carries an interim git pin on `statifier_persistence`: sp-2yx widened
  # the dispatch context to carry the whole effect, and on 0.4.0 the
  # handler raises rather than guess. `mix.exs` says the same beside the
  # pin.
  #
  # The two answers are the handler's own and neither is built here: a
  # refusal is st-ADR-0068's `failure` keyword list, which the driver
  # re-enters as `error.communication` and the chart routes down
  # `signup_onboarding`'s `on_error` slot exactly as it routes any other
  # failed call.
  @spec start_child(pid(), String.t(), String.t(), term(), map()) ::
          {:start_child, Statifier.Effect.Invoke.t(), {:invoke, Statifier.Effect.Invoke.t()}}
          | {:error, keyword()}
  defp start_child(reader, run_id, type, params, dispatch_context) do
    case DurableSubchart.dispatch(type, params, dispatch_context, Subchart) do
      {:start_child, _resolved, {:invoke, invoke}} = instruction ->
        note(reader, run_id, "Child chart started", child_detail(run_id, invoke))

        instruction

      {:error, failure} = refusal ->
        note(reader, run_id, "Child chart refused", "#{type}: #{failure[:reason]}")

        refusal
    end
  end

  # The child's run id, said in the feed at the moment it is started. It is
  # `StatifierPersistence.Run.Linkage.child_run_id/3`'s deterministic
  # construction rather than a value read back out of storage, because at
  # this point the child does not exist yet - the driver creates it when
  # this drive's dispatch fun returns. It is what a reader types into the
  # page URL to open the child as a run of its own, which is the whole
  # point of a durable subchart, so the feed says it rather than making
  # someone query for it.
  @spec child_detail(String.t(), Statifier.Effect.Invoke.t()) :: String.t()
  defp child_detail(run_id, invoke) do
    "#{invoke.src} as run #{Linkage.child_run_id(run_id, invoke.invoke_id, 0)}"
  end

  # The asynchronous arm. The job was stored by the executor a moment ago
  # (`AsyncCalls`' moduledoc says why the enqueue lives there), so there is
  # nothing left to do here but decline to answer: `:pending` buffers
  # nothing, the drive reaches quiescence, and the position persists with
  # the invocation live. What eventually answers it is
  # `StatifierExamples.Charts.AsyncCalls.Delivery`, through
  # `complete_invocation/3` below.
  @spec pending(pid(), String.t(), String.t() | nil) :: :pending
  defp pending(reader, run_id, type) do
    note(reader, run_id, "Call started", "#{type}: running as a job, answer to follow")

    :pending
  end

  @spec perform(pid(), String.t(), Charts.call_context(), String.t() | nil, map()) ::
          {:ok, map()} | {:error, keyword()}
  defp perform(reader, run_id, context, type, params) do
    case Charts.dispatch(type, params, context) do
      {:ok, donedata} ->
        note(reader, run_id, "Performed", performed(type, donedata))

        {:ok, donedata}

      {:error, refusal} ->
        reason = reason(refusal)
        note(reader, run_id, "Call refused", "#{type}: #{reason}")

        {:error, [reason: reason]}
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
  @spec reason({:unknown_invoke_type | :subchart_not_a_sync_call, String.t()}) :: String.t()
  defp reason({:unknown_invoke_type, type}), do: "unknown_invoke_type:#{type}"
  # The subchart refusal names no type: unlike `:unknown_invoke_type`, where
  # the type IS what went wrong, this refusal is about one constant type
  # the note beside it already spells. It is also no longer reachable from
  # this app's durable driver, which routes the subchart type to
  # `start_child/5` above before `Charts.dispatch/3` is asked; the clause
  # stays because the spec it satisfies is the routing table's, not this
  # driver's.
  defp reason({:subchart_not_a_sync_call, _type}), do: "subchart_not_a_sync_call"

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
  #
  # There are FOUR stored statuses, not three: `statifier_persistence` 0.4.0
  # added `:cancelled` as a fourth terminal value (ADR-0008 decision 5), and
  # this app now produces one - `abandon/1` cascades into a live subchart
  # child. A clause for it is not optional: a cancelled run opened by URL
  # reached this function with no matching clause and the page raised, which
  # is what a browser capture of the cascade found (se-6ag). The two arrive
  # at the same reading word for a reason - a run somebody stopped and a run
  # cancelled because its parent was stopped both ended by a decision from
  # outside the chart - and the stored record keeps them apart for anyone
  # who needs to know which.
  @spec finish(Run.t(), atom()) :: Run.t()
  defp finish(run, :completed), do: Run.absorb(run, {:halted, :done})
  defp finish(run, :failed), do: Run.absorb(run, {:halted, :cancelled})
  defp finish(run, :cancelled), do: Run.absorb(run, {:halted, :cancelled})
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
