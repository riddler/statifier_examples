defmodule StatifierExamples.Charts.AsyncCalls do
  @moduledoc """
  The one call in this app that does **not** answer inside the step that
  made it: the wizard's company-details step, started as an Oban job and
  answered minutes or days later, from a process that has never seen the
  run.

  Every other `<invoke>` here is a function call wearing an invoke's
  clothes - `StatifierExamples.Charts.dispatch/3` runs it and hands back
  a `donedata` map before the durable step returns. That is the easy half
  of spec 6.4, and it left the production-shaped half unexercised: an
  invocation that outlives the step, a run that rests durably with the
  invocation still live, a cancel that means something because there is
  something to cancel.

  ## Which call, and why that one

  `myapp:signup` on the `company_details` step, and it is chosen for what
  it means rather than for what it costs: collecting a company's details
  is a human step that takes hours, and the chart already surrounds it
  with the deadline that makes waiting safe. `blk_su_company` sits inside
  the wizard's onboarding group, whose body arms `signup.abandoned` two
  hours out and whose interrupt rail listens for it - so a run resting on
  this call is a run with a live invocation and an armed clock, which is
  the whole shape se-d74 was filed for.

  It is chosen per *block*, not per type: the same `myapp:signup` handler
  answers four other steps synchronously, and which step a call is for
  rides in the `<param>` the block emits. So `async?/2` reads the params,
  and the document says which of its own steps is the slow one.

  ## Asynchronous on the durable path only

  `:pending` is `StatifierPersistence.Driver`'s arm (its ADR-0007), and
  it exists because a durable run has no process to hold: the drive
  reaches quiescence, the position persists with the invocation live in
  `active_invocations`, and nothing is waiting. A `Statifier.Session` run
  of the same chart has a process, holds it, and answers the same call
  through `StatifierExamples.Charts.SyncAdapter` in the same breath.

  The chart cannot tell the difference - the same `done.invoke` arrives
  with the same donedata either way - and that is the point: which calls
  a deployment runs on a job queue is a host's decision, not a fact about
  the document. This app makes it in one predicate, here.

  ## The three doors, and who opens them

  - **Starting** is `StatifierOban.Invoke.Handler.perform_start/3`, called
    from `consume/2` on the `{:invoke, _}` effect - one job, unique on
    `{scope, invoke_id, macrostep}`, in the app's Oban queue. The scope is
    the durable run id, which is what `statifier_oban` means by "the
    host's own durable run id" where a session host passes `session_id`.
  - **Answering** is the job's: `StatifierOban.Invoke.Worker` calls
    `run/1` below, then hands the result to
    `StatifierExamples.Charts.AsyncCalls.Delivery`, which re-enters the
    run through `StatifierPersistence.Driver.done_invocation/5`.
  - **Cancelling** is `StatifierOban.Invoke.Handler.perform_cancel/3`,
    called from `consume/2` on the `{:cancel_invoke, _}` effect the
    interpreter emits when a state carrying a live invocation exits. The
    abandonment deadline firing is exactly that exit, so the timeout
    takes the job down and routes the chart's own abandon outcome.

  ## Why the base is a behaviour here and not a `use`

  `StatifierOban.Invoke.Handler`'s `__using__` injects four
  `Statifier.Invoke.Handler` callbacks - `start/2`, `cancel/2`,
  `forward/3` and `perform/2`. Those are a **session's** planning seam
  (st-ADR-0051): the session calls them, folds the instructions they
  return, and performs them. A durable run has no session and plans
  nothing, so all four would be dead code here.

  What this host needs is the impure half, and the package exports it:
  `perform_start/3` and `perform_cancel/3` are public functions over a
  handler module, and the worker asks a handler for `run/1` and nothing
  else. So this module states the `StatifierOban.Invoke.Handler`
  behaviour, implements its two callbacks, and calls the two doors itself
  from the executor. A host driving `StatifierPersistence` rather than
  `Statifier.Session` is the base's other documented caller, and this is
  what that looks like.

  ## The gap this app cannot close from here

  `c:StatifierOban.Invoke.Handler.run/1` is handed the effect and nothing
  else - no scope. The scope is on the job row (`JobArgs.from_invoke/4`
  writes it, and the worker reads it to deliver with) but it is not
  passed to the work, so a handler whose work keys on the *run* cannot be
  written against the base as shipped.

  That is why `myapp:provision` - this app's one call that writes, keyed
  on the run id by `StatifierExamples.Signup.Accounts` - stays
  synchronous, and why the asynchronous example is a call whose work is
  run-independent. `invoke.invoke_id` is the key the base offers instead,
  and it is the right key for deduplicating *this* invocation's work; it
  is not a substitute for the run, because it restarts per run
  (st-ADR-0008). Raising it in `statifier_oban` is the reference
  embedder's job; working around it here would hide it.

  ## The enqueue is in the executor, not in the dispatch fun

  `StatifierPersistence.Driver`'s dispatch fun receives the invoke's
  `type` and `params` and a context, not the `%Statifier.Effect.Invoke{}`
  itself - and `StatifierOban.Invoke.JobArgs` needs the whole effect,
  because the dedup triple is built from the position row the effect
  carries. The executor sees the effect, and the driver runs it first
  (`observe` before `perform`, in one wrapper), so the job is stored
  before the dispatch fun answers `:pending` for the same invocation.

  ## A start that fails raises

  `StatifierExamples.Charts.Timers`' reasoning, unchanged: returning `:ok`
  for a job that was never inserted would leave the chart resting on a
  call nobody is running, and answering `{:error, _}` would re-enter as
  `error.communication` and steer the chart with an infrastructure fact.
  So an insert that fails raises, the step fails loudly, and the position
  is not advanced past an invocation that was never started.
  """

  @behaviour StatifierOban.Invoke.Handler

  alias Statifier.Effect.{CancelInvoke, Invoke}
  alias Statifier.Invoke.Types
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.AsyncCalls.Delivery
  alias StatifierExamples.Charts.Timers
  alias StatifierOban.Config
  alias StatifierOban.Invoke.Handler

  # The one block this app runs asynchronously, named by the invoke type
  # its step declares and the `step` param the block emits. Two constants
  # rather than one because they are two different things: the type is
  # what a handler registers, and the step is what one call is for.
  @async_type "myapp:signup"
  @async_step "company_details"

  # This app's second Oban queue, and `config/config.exs` says why it is a
  # second one rather than the timers' own.
  @queue :statifier_invocations

  @doc """
  Whether this app runs `type` with these `params` as an asynchronous
  invocation.

  Read by `consume/2` on the way in, to decide whether to store a job, and
  by `StatifierExamples.Charts.Durable`'s dispatch fun on the way out, to
  decide whether to answer `:pending`. One predicate for both, because the
  two decisions are the same decision: a job stored for a call that was
  then answered inline would run against an invocation nobody is waiting
  for, and a `:pending` for a call nobody enqueued would rest forever.
  """
  @spec async?(String.t() | nil, map()) :: boolean()
  def async?(@async_type, %{"step" => @async_step}), do: true
  def async?(_type, _params), do: false

  @doc "The queue asynchronous invocation jobs are stored in."
  @spec queue() :: atom()
  def queue, do: @queue

  @doc """
  The `statifier_oban` configuration an asynchronous invocation runs
  under.

  `:invoke_queue` is this module's own queue rather than
  `StatifierExamples.Charts.Timers`', and the split is deliberate: the two
  job kinds fail differently. A timer job delivers an event and is over in
  milliseconds; an invoke job runs the host's actual work, which is the
  slow thing, the thing that retries, and the thing that can pile up.
  `config/config.exs` says the same in the place a reader looks for queue
  concurrency.

  `:invoke_delivery` is the seam that matters here, exactly as `:delivery`
  is for timers - the package's default answers run-liveness from
  `Statifier.Session`'s registry, and this app has no session process to
  ask. The timer half is still stated, because a `StatifierOban.Config`
  carries both and `:timers_queue` is required.

  Built on every call, for the reason `Timers.config/0` gives: these are
  constants, and a memoised copy would be one more thing that can be
  stale.
  """
  @impl StatifierOban.Invoke.Handler
  @spec config() :: Config.t()
  def config do
    options = [
      oban: Timers.oban(),
      timers_queue: Timers.queue(),
      delivery: Timers.Delivery,
      invoke_queue: @queue,
      invoke_delivery: Delivery
    ]

    case Config.new(options) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  The work itself, run inside the Oban job.

  It is the same call `StatifierExamples.Charts.dispatch/3` would have
  made inline, routed to the same handler module - which is what makes
  this an example of *when* a host defers a call rather than of a second
  way to answer one. The context is empty because this work is
  run-independent by construction (see the moduledoc's gap section); a
  handler clause that needs the run gets the clause that says so.

  At-least-once is the base's contract, so this is idempotent by being a
  log line and a canned answer - which is all any handler in this app
  does. A deployment whose company-details step wrote something would key
  that write on `invoke.invoke_id`.
  """
  @impl StatifierOban.Invoke.Handler
  @spec run(Invoke.t()) :: {:ok, map()} | {:error, term()}
  def run(%Invoke{type: type} = invoke) when is_binary(type) do
    Charts.dispatch(type, params(invoke.params), %{})
  end

  @doc """
  Consumes one effect on behalf of the run named by `run_id`.

  Two effects are this module's, and every other one passes through
  untouched:

    * `{:invoke, %Invoke{}}` for a call `async?/2` claims - one stored
      job, keyed on `{run_id, invoke_id, macrostep}`.
    * `{:cancel_invoke, %CancelInvoke{}}` - every stored job under
      `{run_id, invoke_id}`, whatever its macrostep. The interpreter emits
      one per live invocation when the invoking state exits, and this app
      hands them all to the package: a cancel matching nothing is a no-op
      by the base's own contract, which is what makes it safe to pass
      along the cancels of the synchronous invocations too.

  Answers `:ok` for every effect, including the ones it does nothing with:
  the caller is an executor, whose whole vocabulary is `:ok` and
  `{:error, _}`, and "this effect is not an asynchronous call" is not an
  error.
  """
  @spec consume(String.t(), Statifier.Effect.t()) :: :ok
  def consume(run_id, {:invoke, %Invoke{} = invoke}) when is_binary(run_id) do
    if async?(invoke.type, params(invoke.params)) do
      start!(run_id, invoke)
    else
      :ok
    end
  end

  def consume(run_id, {:cancel_invoke, %CancelInvoke{} = effect}) when is_binary(run_id) do
    case Handler.perform_cancel(__MODULE__, effect.invoke_id, ctx(run_id)) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "could not cancel #{effect.invoke_id} for #{run_id}: #{inspect(reason)}"
    end
  end

  def consume(run_id, _other) when is_binary(run_id), do: :ok

  @spec start!(String.t(), Invoke.t()) :: :ok
  defp start!(run_id, %Invoke{} = invoke) do
    case Handler.perform_start(__MODULE__, invoke, ctx(run_id)) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "could not start #{invoke.invoke_id} for #{run_id}: #{inspect(reason)}"
    end
  end

  # The context the base reads its scope out of. `statifier_oban` names
  # the field `session_id` because a session host's scope IS its session
  # id, and documents the other case in the same breath: "the host's own
  # durable run id". This host has no session, so the run id is what goes
  # there, and the two registration fields are empty because neither
  # `perform_start/3` nor `perform_cancel/3` reads them - the full shape
  # is built rather than a bare map so the value still satisfies
  # `t:Statifier.Invoke.Handler.ctx/0`.
  @spec ctx(String.t()) :: Statifier.Invoke.Handler.ctx()
  defp ctx(run_id) do
    %{session_id: run_id, invoke_types: Types.new(types: []), invoke_handlers: %{}}
  end

  @spec params(term()) :: map()
  defp params(params) when is_map(params), do: params
  defp params(_absent), do: %{}
end
