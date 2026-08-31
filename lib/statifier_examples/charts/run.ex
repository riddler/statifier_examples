defmodule StatifierExamples.Charts.Run do
  @moduledoc """
  The reading of one run of one compiled document: the marks the editor
  paints, and the feed of what happened.

  `StatifierExamples.Charts.Durable` produces it: it steps a durable run
  through `statifier_persistence` and folds the effects each step returns.
  The fold is written against the effect vocabulary rather than against
  that driver, because an effect is an effect - `{tag, payload}` in
  `Statifier.Effect`'s vocabulary - whether it arrived in a return value
  or in a mailbox. An in-memory driver that folded a subscriber's mailbox
  ran beside the durable one through the demo era; se-b2f deleted it once
  the durable driver covered the editor page on its own, and the fold
  below did not have to move for either its arrival or its going.

  ## Why a struct and not a process

  What this module holds is the *reading* - which blocks are lit, which
  call is out, and the rows a reader sees - and that is a fold, not a
  second process. `absorb/2` is pure, so every derivation below is tested
  by feeding it effects rather than by driving a browser.

  What the reading deliberately does not hold is a lifetime. A run that
  outlives the page it was started from needs a store, an owner that is
  not a viewer, and a way back in, and every one of those is
  `StatifierExamples.Charts.Durable`'s - which is why the page starts its
  runs there and this struct is only what a reader sees.

  ## The three derivations

  A `%Statifier.Effect.Trace.EntrySet{}` and a
  `%Statifier.Effect.Trace.MacrostepStable{}` both carry the whole
  `configuration` as state **indexes**. `active/1` is that configuration's
  *atomic* states mapped through `StatifierBlocks.Provenance`'s
  `by_state_id` to block ids: atomic only, because the configuration
  includes every ancestor and a mark on the root block would say "the run
  is everywhere". The compiler's provenance is total over the emission, so
  every state a run can be in names a block.

  An `%Statifier.Effect.Invoke{}` lights the *invoke* mark: it carries the
  `state_index` of the state whose `<invoke>` fired, which is the block's
  own inner running state, so the same provenance lookup names the block.
  It is set bare - the editor's spelling for "no answer yet".

  The answer arrives as the internal event
  `done.outcome.<state id>.<outcome>` that
  `StatifierBlocks.InvokeStep.emit/4` raises on entering an outcome
  `<final>`. Reading it here is not a package internal read: that emission
  is the leaf-step shape `statifier_blocks` ADR-0007 records and every
  `myapp.*` type in this app declares itself on, and the outcome names are
  `StatifierBlocks.InvokeStep.outcomes/0`'s. The mark becomes
  `{block_id, outcome}` and the editor tints what it knows.
  """

  alias Statifier.Effect.{Invoke, Log, SendDelayed, Trace}
  alias Statifier.Machine
  alias StatifierBlocks.{Block, Compiled, Document, Provenance}

  @typedoc """
  What a row is about. `started` opens a run and reopens a resumed one,
  `performed` is a call the host answered, and the rest name what the
  chart did.
  """
  @type entry_kind ::
          :started
          | :entered
          | :invoked
          | :performed
          | :outcome
          | :event
          | :delayed
          | :log
          | :halted

  @typedoc """
  One row of the feed. `kind` is what the row is about and is what the
  stylesheet tints; `label` and `detail` are the two columns a reader sees.
  """
  @type entry :: %{
          seq: non_neg_integer(),
          kind: entry_kind(),
          label: String.t(),
          detail: String.t() | nil
        }

  @type t :: %__MODULE__{
          session_id: String.t(),
          machine: Machine.t(),
          provenance: Provenance.t(),
          labels: %{String.t() => String.t()},
          events: [String.t()],
          entries: [entry()],
          seq: non_neg_integer(),
          active: [String.t()],
          invoke: nil | String.t() | {String.t(), String.t()},
          status: :running | :done | :cancelled | :budget_exhausted
        }

  # Every key here is a fact the reading cannot be built without, so every
  # key here is enforced. `session_id` is the run id the durable driver
  # goes by, and it is the only name this struct has.
  @enforce_keys [:session_id, :machine, :provenance, :labels, :events]
  defstruct [
    :session_id,
    :machine,
    :provenance,
    :labels,
    :events,
    entries: [],
    seq: 0,
    active: [],
    invoke: nil,
    status: :running
  ]

  @outcome_prefix "done.outcome."

  # The three event families the feed does not draw a row for, because it
  # has already said the same thing in its own words one row earlier or
  # later: `done.invoke.<id>` and `done.outcome.<state>.<outcome>` are both
  # narrated by the Outcome row, and `done.state.<state>` by the Entered
  # row that follows it. They are the compiler's bookkeeping, not events
  # anybody sent, and a feed that showed each of them tripled its length
  # without telling a reader anything new. Every other event is drawn,
  # `statifier_blocks.*` included: a wait firing and an interrupt resuming
  # are things that happened, and nothing else in the feed says so.
  @narrated_prefixes ["done.invoke.", "done.outcome.", "done.state."]

  @doc """
  The reading of a run, identified by `run_id`.

  The durable driver's constructor, and the only one. It takes the
  `machine` explicitly rather than compiling one, because the machine a
  durable run resumes on has to be the one whose identity matched the
  stored position - deriving a second one here would be the same bytes
  compiled twice and a place for them to disagree.

  No opening row: a created run and a resumed one open with different
  words, and which of the two this is belongs to the driver that knows.
  """
  @spec reading(Machine.t(), Compiled.t(), Document.t(), String.t()) :: t()
  def reading(%Machine{} = machine, %Compiled{} = compiled, %Document{} = document, run_id)
      when is_binary(run_id) do
    %__MODULE__{
      session_id: run_id,
      machine: machine,
      provenance: compiled.provenance,
      labels: labels(document),
      events: event_names(document)
    }
  end

  @doc """
  Appends one row the *driver* wrote rather than one the chart produced.

  The feed is a fold over effects, and almost every row is. Three things a
  reader needs to see are not effects at all: that a run started, that a
  run was picked back up out of storage, and what a call the host
  performed actually did. Those come through here, and they are marked as
  their own kinds so the stylesheet can tell them apart from the chart's
  own narration.
  """
  @spec note(t(), entry_kind(), String.t(), String.t() | nil) :: t()
  def note(%__MODULE__{} = run, kind, label, detail), do: append(run, kind, label, detail)

  @doc """
  Folds one thing that happened into the run. Pure.

  What arrives is an effect a step returned, wrapped `{:effect, {tag,
  payload}}`, or `{:halted, reason}` for a run that is over. Anything this
  reading has nothing to say about - a trace point that is not one of the
  rows, an effect the feed does not name - leaves the run exactly as it
  was, which is what lets the fold be total over a vocabulary that grows.
  """
  @spec absorb(t(), term()) :: t()
  def absorb(%__MODULE__{} = run, {:effect, {:invoke, %Invoke{} = invoke}}) do
    block_id = block_at(run, invoke.state_index)

    run
    |> Map.put(:invoke, block_id)
    |> append(:invoked, "Invoke dispatched", "#{invoke.type} on #{name(run, block_id)}")
  end

  def absorb(%__MODULE__{} = run, {:effect, {:send_delayed, %SendDelayed{} = send}}) do
    append(run, :delayed, "Delayed send", "#{send.event} in #{send.delay_ms} ms")
  end

  def absorb(%__MODULE__{} = run, {:effect, {:log, %Log{} = log}}) do
    append(run, :log, log.label || "Log", to_string(log.value))
  end

  def absorb(%__MODULE__{} = run, {:effect, {:trace, %Trace.EntrySet{} = entry_set}}) do
    entered = blocks_in(run, entry_set.indexes)

    run
    |> mark_active(entry_set.configuration)
    |> append_entered(entered)
  end

  def absorb(%__MODULE__{} = run, {:effect, {:trace, %Trace.MacrostepStable{} = stable}}) do
    mark_active(run, stable.configuration)
  end

  def absorb(%__MODULE__{} = run, {:effect, {:trace, %Trace.EventDequeued{} = dequeued}}) do
    name = dequeued.event.name

    run
    |> absorb_outcome(name)
    |> append_event(name)
  end

  def absorb(%__MODULE__{} = run, {:halted, reason}) do
    run
    |> Map.put(:status, reason)
    |> Map.put(:invoke, nil)
    |> append(:halted, "Run finished", to_string(reason))
  end

  def absorb(%__MODULE__{} = run, _other), do: run

  @doc """
  The feed's rows, oldest first. Held reversed so appending is a cons.
  """
  @spec entries(t()) :: [entry()]
  def entries(%__MODULE__{entries: entries}), do: Enum.reverse(entries)

  @doc """
  The label a block goes by in the feed: the `label` the author typed, or
  the block id when they typed none.
  """
  @spec name(t(), String.t() | nil) :: String.t()
  def name(_run, nil), do: "an unmapped state"
  def name(%__MODULE__{labels: labels}, block_id), do: Map.get(labels, block_id, block_id)

  # ------------------------------------------------------------- derivation

  @spec mark_active(t(), MapSet.t(non_neg_integer())) :: t()
  defp mark_active(%__MODULE__{} = run, configuration) do
    active =
      configuration
      |> Enum.filter(&Machine.atomic?(run.machine, &1))
      |> Enum.map(&block_at(run, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    %{run | active: active}
  end

  @spec append_entered(t(), [String.t()]) :: t()
  defp append_entered(run, []), do: run

  defp append_entered(run, block_ids) do
    append(run, :entered, "Entered", Enum.map_join(block_ids, ", ", &name(run, &1)))
  end

  # The blocks the entry set's own states belong to, deduplicated: entering
  # a step enters its wrapper and its inner running state, which are two
  # states of one block and one row.
  @spec blocks_in(t(), [non_neg_integer()]) :: [String.t()]
  defp blocks_in(run, indexes) do
    indexes
    |> Enum.map(&block_at(run, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @spec append_event(t(), String.t()) :: t()
  defp append_event(run, name) do
    if Enum.any?(@narrated_prefixes, &String.starts_with?(name, &1)) do
      run
    else
      append(run, :event, "Event", name)
    end
  end

  @spec absorb_outcome(t(), String.t()) :: t()
  defp absorb_outcome(run, @outcome_prefix <> rest) do
    case String.split(rest, ".") do
      [state_id, outcome] -> outcome_mark(run, state_id, outcome)
      _other -> run
    end
  end

  defp absorb_outcome(run, _name), do: run

  @spec outcome_mark(t(), String.t(), String.t()) :: t()
  defp outcome_mark(run, state_id, outcome) do
    case Map.fetch(run.provenance.by_state_id, state_id) do
      {:ok, %{block_id: block_id}} ->
        run
        |> Map.put(:invoke, {block_id, outcome})
        |> append(:outcome, "Outcome", "#{outcome} on #{name(run, block_id)}")

      :error ->
        run
    end
  end

  @spec block_at(t(), non_neg_integer()) :: String.t() | nil
  defp block_at(run, index) do
    with state_id when is_binary(state_id) <- Machine.id(run.machine, index),
         {:ok, %{block_id: block_id}} <- Map.fetch(run.provenance.by_state_id, state_id) do
      block_id
    else
      _absent -> nil
    end
  end

  @spec append(t(), entry_kind(), String.t(), String.t() | nil) :: t()
  defp append(run, kind, label, detail) do
    entry = %{seq: run.seq, kind: kind, label: label, detail: detail}

    %{run | entries: [entry | run.entries], seq: run.seq + 1}
  end

  # ---------------------------------------------------------------- reading

  @doc """
  The external events this document is prepared to receive, sorted.

  Read off the `core.on_event` blocks the document holds, which is the one
  place a block document says "the outside may say this". The host page
  turns each into a button, so the affordance for stepping a run is derived
  from the chart rather than typed beside it - a document that grows an
  interrupt grows a button.
  """
  @spec event_names(Document.t()) :: [String.t()]
  def event_names(%Document{} = document) do
    names =
      for %Block{type: "core.on_event", config: config} <- Document.blocks(document),
          name = Map.get(config, "event"),
          is_binary(name) and name != "",
          uniq: true,
          do: name

    Enum.sort(names)
  end

  @spec labels(Document.t()) :: %{String.t() => String.t()}
  defp labels(document) do
    for %Block{id: id, config: config} <- Document.blocks(document),
        into: %{},
        do: {id, label(config, id)}
  end

  @spec label(map(), String.t()) :: String.t()
  defp label(config, id) do
    case Map.get(config, "label") do
      label when is_binary(label) and label != "" -> label
      _absent -> id
    end
  end
end
