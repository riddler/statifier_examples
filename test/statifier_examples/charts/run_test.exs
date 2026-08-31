defmodule StatifierExamples.Charts.RunTest do
  # Async: nothing here starts a process or writes a row. `Run` is a fold
  # over effects, so every derivation it makes is testable by handing it
  # the effects rather than by driving a chart into producing them - and
  # since se-b2f deleted the in-memory driver, handing them over is the
  # only way this module is exercised on its own. What the durable driver
  # does with the same functions is `StatifierExamples.Charts.DurableTest`.
  use ExUnit.Case, async: true

  alias Statifier.Effect.Trace
  alias Statifier.{Event, Machine}
  alias StatifierBlocks.Compiler
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Run

  # The wizard compiled exactly as the editor page compiles it - the
  # fixture's own `declare:` and the page's `terminate: true` - because the
  # provenance the marks are looked up in is part of those bytes.
  defp reading do
    {:ok, fixture} = Charts.fixture("signup_wizard")

    {:ok, compiled} =
      Compiler.compile(fixture.document, Charts.palette(),
        known_invoke_types: Charts.invoke_types(),
        declare: fixture.declare,
        terminate: true
      )

    {:ok, machine} = Statifier.compile(compiled.scxml)

    Run.reading(machine, compiled, fixture.document, "run-b2f")
  end

  defp state_index(run, state_id) do
    {:ok, index} = Machine.index(run.machine, state_id)
    index
  end

  defp details(run), do: run |> Run.entries() |> Enum.map(& &1.detail)

  defp kinds(run), do: run |> Run.entries() |> Enum.map(& &1.kind)

  defp dequeued(name) do
    {:effect,
     {:trace,
      %Trace.EventDequeued{
        event: %Event{name: name, type: :internal},
        from: :internal,
        macrostep: 1,
        microstep: 1,
        round: 1
      }}}
  end

  # The bare mark: an `:invoke` effect on its own leaves the run pointing at
  # the block with no answer, which is the editor's spelling for a call that
  # is still out.
  #
  # Sabotage: made the `:invoke` clause of `absorb/2` leave `run.invoke`
  # alone; this went red. Reverted.
  test "an invoke effect alone marks the block with no answer yet" do
    run = reading()

    invoke = %Statifier.Effect.Invoke{
      invoke_id: "x.inv_1",
      type: "myapp:signup",
      state_index: state_index(run, "s_blk_su_account__running"),
      invoke_index: 0,
      macrostep: 1,
      microstep: 1,
      round: 1
    }

    marked = Run.absorb(run, {:effect, {:invoke, invoke}})

    assert marked.invoke == "blk_su_account"
    assert "myapp:signup on Collect email and password" in details(marked)
  end

  # And the answer: the internal `done.outcome.<state>.<outcome>` event that
  # `StatifierBlocks.InvokeStep.emit/4` raises on entering an outcome
  # `<final>` turns the bare mark into `{block_id, outcome}`, which is what
  # the editor tints.
  #
  # Sabotage: made `outcome_mark/3` set `run.invoke` to the block id alone;
  # this went red on the tuple match. Reverted.
  test "the outcome event marks the block with what the call came back with" do
    run = Run.absorb(reading(), dequeued("done.outcome.s_blk_su_account__o_done.done"))

    assert run.invoke == {"blk_su_account", "done"}
    assert "done on Collect email and password" in details(run)
  end

  # The feed's own rule: an event it has already narrated in its own words is
  # not drawn twice. `done.outcome.*` is narrated by the Outcome row above,
  # `done.state.*` by the Entered row after it, and `done.invoke.*` by both -
  # they are the compiler's bookkeeping, not events anybody sent.
  #
  # Sabotage: emptied `@narrated_prefixes`; the bookkeeping rows appeared and
  # this went red on all three refutations. Reverted.
  test "the feed draws the events nothing else has already said" do
    run =
      Enum.reduce(
        [
          "signup.email_verified",
          "done.state.s_blk_su_account",
          "done.invoke.x.inv_1",
          "done.outcome.s_blk_su_account__o_done.done"
        ],
        reading(),
        &Run.absorb(&2, dequeued(&1))
      )

    events = for %{kind: :event} = entry <- Run.entries(run), do: entry.detail

    assert events == ["signup.email_verified"]
  end

  # The active marks the editor paints. Atomic states only: the configuration
  # carries every ancestor, and a mark on the root block would say the run is
  # everywhere at once.
  #
  # Sabotage: dropped the `Machine.atomic?/2` filter from `mark_active/2`;
  # `blk_su_root` joined the marks and this went red. Reverted.
  test "active marks are the blocks of the atomic configuration, never the root" do
    run = reading()

    configuration =
      MapSet.new([
        state_index(run, "s_blk_su_root"),
        state_index(run, "s_blk_su_account"),
        state_index(run, "s_blk_su_account__running")
      ])

    marked =
      Run.absorb(
        run,
        {:effect,
         {:trace,
          %Trace.MacrostepStable{
            configuration: configuration,
            macrostep: 1,
            microstep: 1,
            round: 1
          }}}
      )

    assert marked.active == ["blk_su_account"]
  end

  # Entering a step enters its wrapper and its inner running state, which are
  # two states of one block and therefore one row.
  #
  # Sabotage: dropped the `Enum.uniq/1` from `blocks_in/2`; the row read
  # "Collect email and password, Collect email and password" and this went
  # red. Reverted.
  test "the two states of one step are drawn as one Entered row" do
    run = reading()

    indexes = [
      state_index(run, "s_blk_su_account"),
      state_index(run, "s_blk_su_account__running")
    ]

    entered =
      Run.absorb(
        run,
        {:effect,
         {:trace,
          %Trace.EntrySet{
            indexes: indexes,
            configuration: MapSet.new(indexes),
            macrostep: 1,
            microstep: 1,
            round: 1
          }}}
      )

    assert details(entered) == ["Collect email and password"]
  end

  # A run that is over takes the status, drops the invoke mark - nothing is
  # out any more - and draws the row that says so.
  #
  # Sabotage: made the `{:halted, reason}` clause leave `run.invoke` alone;
  # the finished run still carried a call and this went red. Reverted.
  test "a halted run takes the status, clears the mark, and says so" do
    run =
      reading()
      |> Run.absorb(dequeued("done.outcome.s_blk_su_account__o_done.done"))
      |> Run.absorb({:halted, :done})

    assert run.status == :done
    assert run.invoke == nil
    assert :halted in kinds(run)
    assert "done" in details(run)
  end

  # The buttons the page draws come off the document, not off a list beside
  # it: a `core.on_event` block is the one place a chart says what the
  # outside may send it.
  #
  # Sabotage: matched on `"core.on_events"` in the comprehension; this went
  # red with an empty list. Reverted.
  test "the external events are read off the document's own interrupt blocks" do
    {:ok, fixture} = Charts.fixture("signup_wizard")

    assert Run.event_names(fixture.document) ==
             ["signup.abandoned", "signup.email_verified", "signup.reminder_due"]
  end

  # A block labelled by its author is named by that label in the feed; one
  # with no label is named by its id rather than by nothing.
  #
  # Sabotage: made `label/2` answer `""` for an unlabelled block; this went
  # red on the id assertion. Reverted.
  test "the feed names a block by its label, and by its id when it has none" do
    run = reading()

    assert Run.name(run, "blk_su_account") == "Collect email and password"
    assert Run.name(run, "blk_su_root") == "blk_su_root"
  end
end
