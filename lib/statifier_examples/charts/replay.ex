defmodule StatifierExamples.Charts.Replay do
  @moduledoc """
  The stored run, read back as a run: this app's mapping from
  `statifier_persistence`'s durable per-run input log to the message
  stream `StatifierUI.Live.State` - and so `statifier_blocks`' Run pane -
  renders.

  Three packages meet here and none of them can do this on its own, which
  is why the mapping is the reference embedder's rather than any of
  theirs:

    * `statifier_persistence` stores the inputs. Its ADR-0010 adds two
      optional adapter callbacks - append one input, list a run's inputs -
      and states the mapping from a stored entry to a
      `t:Statifier.Session.Recording.entry/0` in its decision 8, then
      builds it nowhere: "`from_events/4` is `statifier-ui`'s and no code
      in this package calls it".
    * `statifier_ui` replays. `StatifierUI.Trace.Replay.from_events/4`
      takes the compiled chart, the options the run was made under, and
      the entries - and it has no idea where a host keeps them.
    * `statifier_blocks`' Run pane draws the result. It takes a
      `StatifierUI.Live.State` and asks nothing about where the stream
      came from, which is exactly why a persisted stream and a live one
      are the same struct.

  So this module is decision 8's table, in Elixir, plus the two facts a
  reader of the log cannot recover from the log: which chart the run ran,
  and which options it was created under.

  ## The options a replay needs, and where each one comes from

  ADR-0010 decision 8 is explicit that the log is one of four replay
  inputs and supplies exactly one: "a host that cannot reproduce the
  options its run was created under cannot replay it, log or no log".
  This app can reproduce all of them, and each is taken from the place
  the live run took it from rather than from a value that merely looks
  right:

    * `:trace` - `true`, because `StatifierExamples.Charts.Durable`'s
      create passes `initialize: [trace: true]` on every run it makes.
      Without it `from_events/4` refuses outright with
      `{:initialize_opts, :trace_disabled}` rather than quietly producing
      a stream missing ten of the format's twenty-five message types.
    * `:session_id` - decoded out of the stored position, at
      `machine_state.datamodel["_sessionid"]`. It is the one option the
      record names as recoverable only that way, and it is what stamps
      every message's envelope.
    * `:invoke_types` - `StatifierExamples.Charts.invoke_types/0`, in the
      `Statifier.Invoke.Types` snapshot the durable driver stamps on every
      step. This one is load-bearing rather than decorative:
      `Statifier.Replay` tracks an invocation in `live_invoke_ids` only
      when its type is registered, and a recorded
      `{:invoked_event, invoke_id, _, _}` whose id is not tracked is
      *dropped without an error*. Omitting the snapshot would silently
      replay a card-processing run with none of its authorization answers
      in it.

  Nothing else is passed, and the omissions are deliberate.
  `:invoke_handlers` is `%{}` because that is what the live run planned
  under: this app drives its runs through
  `StatifierPersistence.Driver`'s own `dispatch:` seam, which never puts a
  handler map on the interpreter's plan context. `:datamodel`, `:routes`
  and `:max_macrostep_rounds` are not passed for the same reason - the
  create does not pass them either. A replay is faithful when it is driven
  by the options the run was driven by, not by the options that would make
  it succeed.

  ## The doors, and the one this app cannot log

  Decision 5's table is the whole of what reaches a log: `:step`,
  `:done_invocation`, `:failed_invocation` and `:answer_parent` append,
  and `:create`, `:fail` and `:cancel` do not. This app's own doors land
  on it cleanly - a page's event button and a fired durable timer are both
  `:step`; a completed or failed asynchronous call is
  `:done_invocation`/`:failed_invocation`; a durable subchart's answer to
  its parent is `:answer_parent`, appended to the *parent's* log.

  The one honest gap is a fired delayed send. Upstream records a firing as
  `{:timer, send_id, event, routes}` and matches it against a pending
  timer credit; the log knows only that an event came in at the `:step`
  door, because that is the door
  `StatifierExamples.Charts.Durable.deliver/2` drives it through. So a
  firing replays as an ordinary external event: the credit the `<send>`
  raised stays outstanding and nothing is checked against it. The run
  replays identically either way - `Statifier.Replay` only *checks* a
  `{:timer, ...}` entry - so what is lost is a check, not a step, and the
  alternative would be this app guessing at a `send_id` the log does not
  carry.

  ## What a child run's log holds

  Nothing of its parent's, and the parent's holds nothing of the child's
  own inputs (ADR-0010 decision 7). A durable subchart's child is an
  ordinary run with an ordinary log, and what crosses between them is the
  child's *answer*, which reaches the parent through
  `StatifierPersistence.Driver.answer_parent/3` and lands on the parent's
  log at the `:answer_parent` door as the `done.invoke.<invoke_id>` or
  `error.communication.invoke.<invoke_id>` event the parent's interpreter
  actually saw.

  That is why the parent's Run pane narrates its children without this
  module joining anything: the answers are the parent's own inputs. What
  it does not narrate is the child's internal steps, and it should not -
  those are the child's run, and reading them means reading the child's
  log.
  """

  alias Statifier.Invoke.Types
  alias Statifier.MachineState
  alias StatifierBlocks.Compiled
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Durable
  alias StatifierPersistence.Runs
  alias StatifierPersistence.Storage
  alias StatifierUI.Live.State
  alias StatifierUI.Trace.Replay, as: TraceReplay

  @typedoc """
  Why a stored run could not be read back as a run.

    * `:input_log_unsupported` - the store keeps no input log. Nothing is
      broken; ADR-0010 decision 1 refuses at no door, so a run made
      against such a store ran normally and simply cannot be replayed.
    * `{:input_log_closed, seq}` - the run outgrew its cap and the log
      closed itself with a marker at that ordinal (decision 6). The
      prefix before it is real, and drawing it as a whole run would be
      the one dishonest reading available here.
    * `{:no_session_id, run_id}` - the stored position carries no
      `_sessionid`, so no message envelope can be stamped.
    * `{:unmapped_door, door, input}` - a row at a door decision 8's
      table has no mapping for. Refused rather than guessed at: a run
      replayed with an input silently dropped is a different run.
    * `{:no_invoke_id, event_name}` - an invocation answer whose event
      carries no `invokeid`; see `entry/1`.

  Anything else is `statifier_persistence`'s or
  `StatifierUI.Trace.Replay.from_events/4`'s own error, unwrapped.
  """
  @type refusal ::
          :input_log_unsupported
          | {:input_log_closed, non_neg_integer()}
          | {:no_session_id, String.t()}
          | {:unmapped_door, String.t(), map()}
          | {:no_invoke_id, String.t()}
          | term()

  @doc """
  The read model `statifier_blocks`' Run pane takes, built from `run_id`'s
  stored input log over `compiled`'s chart.

  `compiled` is this app's own `StatifierBlocks.Compiled` - the
  one `StatifierExamples.Charts.Durable.compile/3` produced and the run
  was created over. Its `scxml` is compiled here exactly as
  `Durable.start/4` compiles it, so the machine a replay runs on is the
  machine the run ran on rather than one that merely parses the same
  document.

  The result is a `StatifierUI.Live.State` with `stats: nil`, which is
  statifier-ui's own signal for a persisted stream: the status pane says
  so, and `statifier_blocks` reads the same `nil` to leave the Run pane's
  send control disabled. That is the honest reading - there is no session
  process behind a durable run to send into - and it is why this app keeps
  its own send controls on the page header.
  """
  @spec state(String.t(), Compiled.t()) :: {:ok, State.t()} | {:error, refusal()}
  def state(run_id, %Compiled{} = compiled) when is_binary(run_id) do
    with {:ok, machine} <- Statifier.compile(compiled.scxml),
         {:ok, messages} <- messages(run_id, machine) do
      {:ok, State.new(machine, messages: messages)}
    end
  end

  @doc """
  The wire-format v1 message stream for `run_id`, over an already compiled
  `machine`.

  `state/2`'s middle step, exposed for the same reason
  `StatifierUI.Trace.Replay.recording/3` is: a caller that wants the
  messages - to encode them, to count them, to assert on them in a test -
  should not have to build a read model to get at them.
  """
  @spec messages(String.t(), Statifier.Machine.t()) ::
          {:ok, [StatifierUI.Trace.Message.t()]} | {:error, refusal()}
  def messages(run_id, machine) when is_binary(run_id) do
    with {:ok, store} <- store(),
         {:ok, inputs} <- inputs(store, run_id),
         {:ok, entries} <- entries(inputs),
         {:ok, session_id} <- session_id(run_id) do
      TraceReplay.from_events(machine, initialize_opts(session_id), entries)
    end
  end

  @doc """
  Whether a run made now would have a log to be read back from.

  The capability question ADR-0010 decision 1 makes public precisely so a
  host does not have to infer it from a run that turned out to be
  unreplayable.
  """
  @spec supported?() :: boolean()
  def supported? do
    case store() do
      {:ok, store} -> Storage.input_log_supported?(store)
      {:error, _reason} -> false
    end
  end

  # The options the recorded run was made under. See the moduledoc for
  # where each one comes from and why the list is this short.
  @spec initialize_opts(String.t()) :: keyword()
  defp initialize_opts(session_id) do
    [
      session_id: session_id,
      trace: true,
      invoke_types: Types.new(types: Charts.invoke_types())
    ]
  end

  @spec inputs(Storage.t(), String.t()) :: {:ok, [Storage.input()]} | {:error, refusal()}
  defp inputs(store, run_id) do
    case Runs.inputs(store, run_id) do
      {:ok, inputs} -> {:ok, inputs}
      :not_supported -> {:error, :input_log_unsupported}
      {:error, reason} -> {:error, reason}
    end
  end

  # ADR-0010 decision 8's table, plus the one row it does not have. See
  # `entry/1`.
  @spec entries([Storage.input()]) ::
          {:ok, [Statifier.Session.Recording.entry()]} | {:error, refusal()}
  defp entries(inputs) do
    Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, acc} ->
      case entry(input) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  # One stored row, as the recording entry ADR-0010 decision 8 maps it to.
  #
  # Three of the record's four rows are literal here: a `"step"` row is
  # `{:event, ...}`; a `"done_invocation"` or `"failed_invocation"` row is
  # `{:invoked_event, ...}`; and `"answer_parent"` maps "as the
  # `done`/`failed` door it re-entered by", which is the same
  # `{:invoked_event, ...}` because a child's answer reaches the parent's
  # interpreter as its own `done.invoke.<invoke_id>` or
  # `error.communication.invoke.<invoke_id>`. The `invoke_id` is not a
  # stored column in any of them: it rides on the event's `invokeid`, and
  # reading it off the event is what the record says to do.
  #
  # The fourth row is `"create"`, and the record does not have it. Its
  # decision 5 table says a create appends nothing, on the grounds that
  # `Interpreter.initialize/2` takes no event - and that is true of the
  # initialize itself and false of the drive around it. This app's create
  # performs the chart's synchronous invocations, and every answer the
  # driver feeds back reaches the interpreter through the same single
  # write site inside the run's serialized unit, still carrying the
  # `entry: :create` stamp the create opened with. So a
  # `signup_wizard` run's log opens with two `"create"` rows holding
  # `done.invoke.<invoke_id>` events, before its first `"step"` row.
  #
  # They are mapped by what the event is rather than by the door, and that
  # is the record's own rule rather than a new one: decision 8 makes the
  # event authoritative for the `invoke_id` for exactly this reason, and
  # says outright that "a mapping that produced `{:event, ...}` would
  # replay an external delivery where the run had an invocation answer".
  # An `invokeid` on the event is what an invocation answer has and an
  # external delivery does not. The alternative - refusing the row - would
  # make every run this app can start unreplayable, which is not a reading
  # the record can have intended of a seam whose stated purpose is
  # unblocking this page.
  @spec entry(Storage.input()) ::
          {:ok, Statifier.Session.Recording.entry()} | {:error, refusal()}
  defp entry(%{event: nil, seq: seq}), do: {:error, {:input_log_closed, seq}}

  defp entry(%{door: "step", event: event}), do: {:ok, {:event, event, nil}}

  defp entry(%{door: door, event: event})
       when door in ["done_invocation", "failed_invocation", "answer_parent"],
       do: invoked(event)

  defp entry(%{door: "create", event: event}) do
    if is_binary(event.invokeid), do: invoked(event), else: {:ok, {:event, event, nil}}
  end

  defp entry(%{door: door} = input), do: {:error, {:unmapped_door, door, input}}

  # An invocation answer, refused rather than mapped when the event does
  # not carry the id the entry shape needs. `Statifier.Replay` drops an
  # `{:invoked_event, invoke_id, _, _}` whose id does not line up with a
  # live invocation *silently*, so a `nil` here would diverge the replayed
  # stream from the run with nothing said - the one failure mode this
  # module is worth having.
  @spec invoked(Statifier.Event.t()) ::
          {:ok, Statifier.Session.Recording.entry()} | {:error, refusal()}
  defp invoked(%{invokeid: invoke_id} = event) when is_binary(invoke_id),
    do: {:ok, {:invoked_event, invoke_id, event, nil}}

  defp invoked(event), do: {:error, {:no_invoke_id, event.name}}

  # `:session_id` is recoverable only by decoding the position, which
  # ADR-0010 decision 8 states as one of its two limits and
  # `Durable.machine_state/1` is already the door to.
  @spec session_id(String.t()) :: {:ok, String.t()} | {:error, refusal()}
  defp session_id(run_id) do
    with {:ok, %MachineState{datamodel: datamodel}} <- Durable.machine_state(run_id) do
      case Map.get(datamodel, "_sessionid") do
        session_id when is_binary(session_id) -> {:ok, session_id}
        _absent -> {:error, {:no_session_id, run_id}}
      end
    end
  end

  @spec store() :: {:ok, Storage.t()} | {:error, term()}
  defp store, do: Storage.new(StatifierExamples.Persistence, [])
end
