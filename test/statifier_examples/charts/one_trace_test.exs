defmodule StatifierExamples.Charts.OneTraceTest do
  @moduledoc """
  The campaign-026 capstone proof (`se-opg`): the whole durable arc -
  parent session, durable step, `start_child`, the child's own run, a
  timer firing, and the child's completion re-entering the parent -
  observable as **one navigable trace graph**.

  ## Why a graph and not one trace id

  The bead asked first for a single trace id spanning the arc. It cannot
  exist, and asking for it was the useful part: every seam this arc
  crosses is a deliberate root boundary in the accepted design, because
  each one can outlive the request that started it.

    * a macrostep span is its own trace root, stitched to its predecessor
      with a link (statifier-ex `docs/opentelemetry.md`; ots-ADR-0003
      decision 8 starts every span from a fresh context and never the
      ambient one, so no host span can gather them);
    * a child run is linked from its parent's step, never parented -
      parenthood would hold the parent's trace open for the child's whole
      life (sp `docs/telemetry.md`, ADR-0008);
    * a fired timer is linked to the trace that armed it, never parented,
      for the same reason across a longer gap (sob-ADR-0006 decision 7).

  Ruling RQ-026-4 re-worded the criterion to what the design does
  produce: N roots joined by shared correlation ids and by link edges,
  with the child-start, timer-fire and completion re-entry edges each
  visible. That is what this module asserts.

  `compile` is outside the graph deliberately: `StatifierBlocks.Compiler`
  emits no telemetry, so a compile has no span under any configuration,
  and the arc starts at session start.

  ## What the assertions are worth

  They run against real spans from the real SDK - the simple processor
  exports synchronously to this process (`config/test.exs`) - driven
  through the same `StatifierExamples.Charts.Durable` entry points the
  page uses. Nothing here stubs a span or hand-builds a graph.
  """

  # Not async, for `StatifierExamples.Charts.DurableTest`'s reasons - the
  # named run lock, and the repo - and for one of its own: the simple
  # processor's exporter is global, so two tests collecting at once would
  # read each other's spans.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Subchart, Timers, Tracing}
  alias StatifierExamples.Repo
  alias StatifierExamples.TraceCollector
  alias StatifierPersistence.Run.Linkage
  alias StatifierPersistence.Storage

  setup do
    :ok = Sandbox.checkout(Repo)
    :ok = TraceCollector.attach()

    run_id = "trace-#{System.unique_integer([:positive])}"

    %{run_id: run_id, child_id: Linkage.child_run_id(run_id, "blk_so_wizard", 0)}
  end

  describe "the arc" do
    setup %{run_id: run_id} do
      %{spans: arc!(run_id)}
    end

    # The arc reached its end at all. Asserted first and separately,
    # because every span assertion below is worthless against a run that
    # stopped halfway: a missing edge would then be reporting a broken
    # chart rather than a broken trace.
    #
    # Sabotage: dropped the timer drain from `arc!/1`; this went red with
    # the child still `:active`, which is also the clearest statement of
    # what the drain does - with no button pressed anywhere, a fired timer
    # is the only thing that advances either run. Reverted.
    test "runs to both terminal statuses", %{run_id: run_id, child_id: child_id} do
      assert record!(child_id).status == :completed
      assert record!(run_id).status == :completed
    end

    # Stage 2 and stage 4 of the arc, and the nesting the bridge does
    # produce. `{:start_child, _, _}` creates the child inside the
    # parent's own step, in the parent's process, so ots-ADR-0004's
    # bridge-owned nesting puts the child's step span *inside* the
    # parent's - the one place in this arc where two runs genuinely share
    # a trace id.
    #
    # Sabotage: asserted the child's step span was a root
    # (`parent_span_id == nil`); this went red reporting the parent step's
    # span id, which is the nesting this test is about. Reverted.
    test "the child's first step nests inside the parent's step", %{
      spans: spans,
      run_id: run_id,
      child_id: child_id
    } do
      parent_step = step_for!(spans, run_id)
      child_step = step_for!(spans, child_id)

      assert child_step.parent_span_id == parent_step.span_id
      assert child_step.trace_id == parent_step.trace_id
    end

    # Edge one of three: start_child. It is a *point* in the contract, so
    # the bridge lands it as a span event on the parent's open step span,
    # carrying both ends of the link - which is what makes it navigable
    # from the parent alone.
    #
    # Sabotage: asserted the child_run_id was the parent's run id; this
    # went red reporting the real child id. Reverted.
    test "the child-start edge names both runs", %{
      spans: spans,
      run_id: run_id,
      child_id: child_id
    } do
      {_name, attributes} = event!(spans, "statifier_persistence.child.started")

      assert attributes["statifier_persistence.parent_run_id"] == run_id
      assert attributes["statifier_persistence.child_run_id"] == child_id
      assert attributes["statifier_persistence.invoke_id"] == "blk_so_wizard"
    end

    # Edge two: the timer fire. The delivery seam runs in an Oban job with
    # nothing of this bridge open around it, so it is a detached root -
    # and the edge back to the run is `statifier.session_id`, onto which
    # the bridge aliases `statifier_oban`'s `scope`.
    #
    # The fired timer is matched to its own arming event by `send_id`,
    # which is the pair a reader follows: one `timer.scheduled` root and
    # one `timer.fired` root, same scope, same send.
    #
    # Sabotage: matched the fired spans against the PARENT's run id
    # instead of the child's; this went red with an empty list, which is
    # also the se-6ag finding restated - the wizard's timers are the
    # child's, not the parent's. Reverted.
    test "the timer-fire edge carries the child's scope and a send it was armed under", %{
      spans: spans,
      child_id: child_id
    } do
      fired = named(spans, "statifier_oban.timer.fired")
      armed = for s <- named(spans, "statifier_oban.timer.scheduled"), do: send_id(s)

      assert fired != []

      for span <- fired do
        assert span.attributes["statifier.session_id"] == child_id
        assert send_id(span) in armed
      end
    end

    # Edge three: the completion re-entry. The child finishing answers the
    # parent's invocation through the driver's own door, and the event
    # names the parent, the child and the invocation - the same triple the
    # start edge carried, which is what closes the loop for a reader.
    #
    # Sabotage: asserted the invoke_id was `"blk_su_wizard"` (a real id
    # from the child's own chart, not the parent's invocation); this went
    # red reporting `"blk_so_wizard"`. Reverted.
    test "the completion re-entry edge names the same triple", %{
      spans: spans,
      run_id: run_id,
      child_id: child_id
    } do
      assert [span] = named(spans, "statifier_persistence.child.answered")
      assert span.attributes["statifier_persistence.parent_run_id"] == run_id
      assert span.attributes["statifier_persistence.child_run_id"] == child_id
      assert span.attributes["statifier_persistence.invoke_id"] == "blk_so_wizard"
    end

    # The claim the capstone is actually making, and the only one that
    # needs the whole graph rather than one edge: starting from the
    # parent's first step span - the first thing a reader has an id for -
    # every stage of the arc is reachable by following parent edges, link
    # edges, and shared correlation ids.
    #
    # It is asserted as reachability rather than as "one trace" precisely
    # because the design refuses one trace. A reader navigates; they do
    # not filter by trace id.
    #
    # Sabotage: dropped `statifier.session_id` from
    # `TraceCollector`'s `@correlation` list; this went red on the
    # `statifier_oban` roots, which carry no other id this graph knows -
    # the bridge aliases `scope` onto that one key and nothing else joins
    # a fired timer to the run it belongs to. Reverted.
    test "every stage is reachable from the parent's first step", %{
      spans: spans,
      run_id: run_id
    } do
      first = step_for!(spans, run_id)
      reachable = TraceCollector.reachable(spans, &(&1.span_id == first.span_id))

      for name <- [
            "statifier_persistence.run.step",
            "statifier_persistence.child.answered",
            "statifier_oban.timer.fired",
            "statifier_oban.timer.scheduled"
          ] do
        assert Enum.any?(named(spans, name), &MapSet.member?(reachable, &1.span_id)),
               "no #{name} span is reachable from the parent's first step"
      end
    end
  end

  # The host obligation the arc above does not exercise, asserted on its
  # own so that it is covered rather than assumed.
  #
  # `caller_context` is the only value a library cannot supply: it is what
  # gives a fired timer a link to the trace that armed it instead of
  # leaving it the detached root the arc above shows. This app stamps it
  # in `Durable.send_event/3`, in W3C text form, and that form is the
  # whole contract - the row outlives the node, so a pid or an unfamiliar
  # atom would come back meaningless or undecodable.
  #
  # Why the arc's own timers carry none, which is a chart fact rather than
  # a wiring fault: this app's wizard arms every one of its delayed sends
  # either in the `:initialize` macrostep, which st-ADR-0063 decision 3
  # stamps `nil` because it has no calling event, or on a later turn of
  # the drive loop, whose answer events the driver builds. Only an effect
  # produced by the macrostep of the externally supplied event can carry
  # the stamp. The bead notes carry the upstream question that raises.
  #
  # Sabotage: made `caller_context/0` return the raw propagator carrier
  # (a list of tuples) rather than a map; this went red on the map
  # pattern, which is the shape `statifier_oban`'s job args round-trip.
  # Reverted.
  test "the host's caller_context stamp is the W3C text form, or nil" do
    assert Tracing.caller_context() == nil

    stamped = Tracing.drive("statifier_examples.probe", %{}, fn -> Tracing.caller_context() end)

    assert %{"traceparent" => traceparent} = stamped

    assert <<"00-", trace_id::binary-size(32), "-", span_id::binary-size(16), "-",
             _flags::binary>> = traceparent

    assert trace_id =~ ~r/^[0-9a-f]{32}$/
    assert span_id =~ ~r/^[0-9a-f]{16}$/
  end

  # The whole arc, driven through the same entry points the page uses.
  #
  # The three `Tracing.drive/3` wrappers are the host's own "request"
  # spans. They parent no bridge span - the bridge ignores the ambient
  # context on purpose - and exist so the work under them has a trace
  # context to stamp into `caller_context`, which is what a Phoenix or
  # Oban span would be in production.
  defp arc!(run_id) do
    {:ok, parent} = Charts.fixture("signup_onboarding")
    {:ok, compiled} = Durable.compile(parent.document, parent.declare)

    # Stages 1-4: the parent's session starts, its first durable step
    # runs, it reaches `core.subchart`, and the child is created as its
    # own persisted run inside that very step.
    Tracing.drive("statifier_examples.start", %{"statifier_examples.run_id" => run_id}, fn ->
      {:ok, _driven} = Durable.start(compiled, parent.document, run_id, "signup_onboarding")
    end)

    child_id = Linkage.child_run_id(run_id, "blk_so_wizard", 0)
    {:ok, child} = Charts.fixture("signup_wizard")
    {:ok, child_compiled} = Subchart.child_compile(child.document)

    # The child picked up cold, exactly as a fired timer picks it up: from
    # its run id and the stored position, by a struct that has never seen
    # the parent.
    {:ok, {_durable, _run}} = Durable.resume(child_compiled, child.document, child_id)

    # Stage 5: the timers fire. `with_scheduled: true` runs the jobs whose
    # scheduled time has not arrived, which is what makes a 45-second
    # reminder assertable without waiting 45 seconds. Two passes, because
    # a delivered timer's own step can arm the next one.
    for _pass <- 1..2 do
      Tracing.drive("statifier_examples.timer_delivery", %{}, fn ->
        Oban.drain_queue(queue: Timers.queue(), with_scheduled: true)
      end)
    end

    # Stage 6: the child reaches its own end, and its completion re-enters
    # the parent through the driver's `chart_resolver:` seam. The async
    # drain is the child's own company-details call being answered from
    # its Oban job - a durable subchart child is an ordinary run, so this
    # app's asynchronous invocation seam works inside one.
    #
    # Nothing presses a button anywhere in this arc, and that is the point
    # rather than an omission: every stage after the child's first rest is
    # reached by a stored job firing into a run no process was holding,
    # which is the whole claim the durable stack makes. The second timer
    # to fire is the wizard's 24-hour `core.wait`.
    Oban.drain_queue(queue: AsyncCalls.queue())

    TraceCollector.drain()
  end

  defp record!(run_id) do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    {:ok, record} = Storage.fetch_run(store, run_id)

    record
  end

  defp named(spans, name), do: Enum.filter(spans, &(&1.name == name))

  defp send_id(span), do: span.attributes["statifier_oban.send_id"]

  # The first step span for a run, which is the one a reader starts from.
  defp step_for!(spans, run_id) do
    spans
    |> named("statifier_persistence.run.step")
    |> Enum.filter(&(&1.attributes["statifier_persistence.run_id"] == run_id))
    |> List.first() ||
      flunk("no statifier_persistence.run.step span for #{run_id}")
  end

  defp event!(spans, name) do
    spans
    |> Enum.flat_map(& &1.events)
    |> Enum.find(&(elem(&1, 0) == name)) ||
      flunk("no #{name} span event in the collected spans")
  end
end
