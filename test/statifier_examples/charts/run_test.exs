defmodule StatifierExamples.Charts.RunTest do
  # Not async: a run starts a real `Statifier.Session`, which registers
  # under the application's `Statifier.Registry` - shared, named state.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias StatifierBlocks.Compiler
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Run

  defp signup do
    {:ok, fixture} = Charts.fixture("signup_wizard")

    # `declare:` and `terminate:` from the fixture and the page, exactly as
    # the editor page compiles it: the wizard's plan branch guards on
    # `signup.plan`, and a guard reading a root nothing declared raises
    # `error.execution`; `terminate: true` is what lets the session reach
    # `:done` at all rather than resting on its root outcome forever. The
    # in-memory driver and the durable one run the same bytes, which is the
    # only way their statuses can be compared.
    {:ok, compiled} =
      Compiler.compile(fixture.document, Charts.palette(),
        known_invoke_types: Charts.invoke_types(),
        declare: fixture.declare,
        terminate: true
      )

    {compiled, fixture.document}
  end

  # Drains this process' subscriber messages into the run until the stream
  # goes quiet. A run is driven by a session that answers its own invokes,
  # so "quiet" is the only end state a test can wait for; the timeout is
  # generous rather than tight because a slow machine draining late would
  # otherwise be a flake rather than a failure.
  defp drain(run, timeout \\ 1_500) do
    receive do
      {:statifier, session_id, message} when session_id == run.session_id ->
        drain(Run.absorb(run, message), timeout)
    after
      timeout -> run
    end
  end

  defp start_run do
    {compiled, document} = signup()
    {:ok, run} = Run.start(compiled, document, self())
    on_exit(fn -> Run.stop(run) end)
    run
  end

  # The whole point of the bead in one assertion: a Run press reaches the
  # host handlers, the handlers' answers step the chart, and the chart gets
  # far enough to park at its own wait.
  #
  # Sabotage: made `Charts.invoke_handlers/0` answer `%{}`, so no type was
  # registered; the run raised `error.execution` instead and this went red
  # on the log assertion and on the block marks. Reverted.
  test "a run dispatches through the host handlers and steps the chart" do
    # `config/test.exs` holds the primary logger at `:warning`, which drops
    # the handlers' `:info` lines before any capture handler sees them - so
    # the level is raised for this test alone and put back afterwards. This
    # is the one place the log IS the evidence: it is what distinguishes the
    # app's own `handle/2` having run from the chart merely advancing.
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    log = capture_log(fn -> send(self(), {:drained, drain(start_run())}) end)
    assert_received {:drained, run}

    assert log =~ "myapp:signup collected step \"account\""
    assert log =~ "myapp:signup collected step \"send_verification\""

    assert run.status == :running
    assert "blk_su_verify_wait" in run.active
  end

  # se-5ep: the wizard's `core.assign` runs two blocks in, before the wait
  # this drains to, and an assign writing to a root nothing declared raises
  # `error.execution` exactly as a guard reading one does. So the in-memory
  # driver - the one the editor page runs on - has its own refutation, and
  # not only the durable one.
  #
  # Sabotage: emptied the wizard's declaration list in
  # `StatifierExamples.Signup`'s `@documents`; the assign raised and this
  # went red. Reverted.
  test "the shipped wizard raises nothing on the way to its wait" do
    details = start_run() |> drain() |> Run.entries() |> Enum.map(& &1.detail)

    refute "error.execution" in details
  end

  # The active marks the editor paints. Atomic states only: the
  # configuration carries every ancestor, and the root block being lit
  # would say the run is everywhere at once.
  #
  # Sabotage: dropped the `Machine.atomic?/2` filter from `mark_active/2`;
  # `blk_su_root` joined the marks and this went red. Reverted.
  test "active marks are the blocks of the atomic configuration, never the root" do
    run = drain(start_run())

    refute "blk_su_root" in run.active
    assert "blk_su_verify_wait" in run.active
    assert Enum.all?(run.active, &String.starts_with?(&1, "blk_su_"))
  end

  # The invoke mark: bare while the call is out, `{block_id, outcome}` once
  # the chart's own outcome final has been entered. The bare half cannot be
  # observed after the drain - these handlers answer inside the same turn -
  # so it is asserted on the fold instead, below.
  #
  # The mark holds the LATEST outcome, and since the reminder window landed
  # (se-hp2) that is the `core.send` that arms the nudge rather than the
  # verification call: arming a delayed send completes in the same
  # macrostep, so it is the last thing that finishes before the wizard
  # parks. The call's own outcome is the row before it, which is why both
  # halves are asserted.
  #
  # Sabotage: made `outcome_mark/3` set `run.invoke` to the block id alone;
  # this went red on the tuple match. Reverted.
  test "the invoke mark carries the block and the outcome the call came back with" do
    run = drain(start_run())

    assert {block_id, "done"} = run.invoke
    assert block_id == "blk_su_reminder_timer"

    assert "done on Send the verification email" in (run
                                                     |> Run.entries()
                                                     |> Enum.map(& &1.detail))
  end

  # The bare mark, on the fold rather than through a race: an `:invoke`
  # effect on its own leaves the run pointing at the block with no answer.
  #
  # Sabotage: made the `:invoke` clause of `absorb/2` leave `run.invoke`
  # alone; this went red. Reverted.
  test "an invoke effect alone marks the block with no answer yet" do
    run = start_run()

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
  end

  # The feed's own rule: an event the feed has already narrated in its own
  # words is not drawn twice. `done.state.*` is the compiler's bookkeeping
  # and the Entered row after it says the same thing.
  #
  # Sabotage: emptied `@narrated_prefixes`; the bookkeeping rows appeared
  # and this went red. Reverted.
  test "the feed narrates outcomes and drops the bookkeeping events that repeat them" do
    entries = start_run() |> drain() |> Run.entries()

    kinds = entries |> Enum.map(& &1.kind) |> Enum.uniq()
    details = Enum.map(entries, & &1.detail)

    assert :started in kinds
    assert :invoked in kinds
    assert :outcome in kinds
    refute Enum.any?(details, &String.starts_with?(to_string(&1), "done.state."))
    refute Enum.any?(details, &String.starts_with?(to_string(&1), "done.invoke."))
  end

  # An external event sent from the page reaches the chart and the feed
  # says so. This is the affordance the run buttons drive.
  #
  # Sabotage: made `Run.send_event/2` return the run without sending; the
  # `signup.email_verified` row never appeared and this went red. Reverted.
  test "an external event steps the run and is drawn as its own row" do
    run = start_run() |> drain() |> Run.send_event("signup.email_verified") |> drain()

    details = run |> Run.entries() |> Enum.map(& &1.detail)

    assert "signup.email_verified" in details
  end

  # se-k4a, and the in-memory half of the same fix: compiled with
  # `terminate: true`, a run that gets past the verification wait reaches
  # the top-level `<final>` the option emitted, the session halts, and the
  # feed draws the row that says so. Without the option the same run rested
  # on its root outcome with `:running` forever - the in-memory driver had
  # no way to say a chart was over, which is the visible half of the durable
  # driver's record never reaching `:completed`.
  #
  # The wait's own event is what steps it, the same one
  # `StatifierExamples.Charts.DurableTest` sends: the 24-hour `core.wait`
  # is not something a test waits out.
  #
  # Sabotage: dropped `terminate: true` from `signup/0`'s compile; the run
  # stayed `:running` with no halted row and this went red on the status.
  # Reverted.
  test "a run that finishes halts and the feed says so" do
    run =
      start_run()
      |> drain()
      |> Run.send_event("statifier_blocks.wait.blk_su_verify_wait")
      |> drain()

    assert run.status == :done
    assert :halted in (run |> Run.entries() |> Enum.map(& &1.kind))
  end

  # The buttons the page draws come off the document, not off a list beside
  # it: a `core.on_event` block is the one place a chart says what the
  # outside may send it.
  #
  # Sabotage: matched on `"core.on_events"` in the comprehension; this went
  # red with an empty list. Reverted.
  test "the external events are read off the document's own interrupt blocks" do
    {_compiled, document} = signup()

    assert Run.event_names(document) ==
             ["signup.abandoned", "signup.email_verified", "signup.reminder_due"]
  end

  # A block labelled by its author is named by that label in the feed; one
  # with no label is named by its id rather than by nothing.
  #
  # Sabotage: made `label/2` answer `""` for an unlabelled block; this went
  # red on the id assertion. Reverted.
  test "the feed names a block by its label, and by its id when it has none" do
    run = drain(start_run())

    assert Run.name(run, "blk_su_account") == "Collect email and password"
    assert Run.name(run, "blk_su_root") == "blk_su_root"
  end

  defp state_index(run, state_id) do
    {:ok, index} = Statifier.Machine.index(run.machine, state_id)
    index
  end
end
