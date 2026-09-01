defmodule StatifierExamples.Charts.SubchartTest do
  @moduledoc """
  What this app's `statifier_blocks:subchart` handler does, driven rather
  than read: a `Statifier.Session` started with
  `StatifierExamples.Charts.invoke_handlers/0` runs the parent fixture, and
  what the assertions read is the child session that came out of it.

  The refusal set and the planning are `statifier_blocks`' and are tested
  where they live (sb-6edf). What is this app's is the resolver over its
  own fixtures, the pin `identities/1` builds, the option a root session is
  started with, and the shape of the documents it ships - so those are what
  is asserted here.

  ## Depth 2

  A parent that starts a child is depth 1 doing something; a child that
  answers its own calls and finishes is depth 2 (se-8zp). The second needs
  `Statifier.Session`'s `:inherit_invoke_handlers`, which this app passes
  in `session_opts/0` below - see it for why the engine defaults it off.
  The pair of tests around `@child_first_state` and `@child_verify_group`
  is that difference, driven both ways round.
  """

  # Not async: a session registers under the application's own
  # `Statifier.Registry`, and its children are started under the shared
  # `Statifier.SessionSupervisor`.
  use ExUnit.Case, async: false

  alias Statifier.Machine
  alias Statifier.Machine.Identity
  alias StatifierBlocks.{Compiled, Compiler, Edit}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Subchart}

  @parent "signup_onboarding"
  @child_document_id "bdoc_signup_demo"

  # The one `core.subchart` in the parent fixture, and the block its
  # `on_error` slot holds - the path a refused start routes to.
  @subchart_block "blk_so_wizard"

  # The event `statifier_blocks` raises for a refused start:
  # `error.communication.invoke.<invoke id>`, and `core.subchart` emits its
  # `<invoke>` with the block's own id (ADR-0004's amendment C3).
  @refusal_event "error.communication.invoke.blk_so_wizard"

  # The document id used for the refusal tests. Nothing ships it, which is
  # the whole of what makes it `unknown_document`.
  @missing "bdoc_nothing_ships_this"

  # The wizard's first step. A child session that cannot answer
  # `myapp:signup` sits here for the rest of the run, which is what the
  # whole document did before handler inheritance arrived (st-pvpz).
  @child_first_state "s_blk_su_account"

  # The group the wizard enters once its first step is DONE - the email
  # verification block. A child only reaches it by running the account step
  # to completion: `myapp:signup` dispatched, answered, and its result
  # assigned. That is the depth-2 evidence, and the group rather than a
  # step inside it is what is named because the group is where the child
  # stays (it holds a 24h wait), while which of its body steps is current
  # depends on how far the delayed sends have got.
  @child_verify_group "s_blk_su_verify"

  # The root of the wizard's datamodel. The document declares it, so the
  # key is present from the start; the account step's `assign_to` is what
  # puts a map in it. `nil` is therefore "declared and never written",
  # which is exactly the parked child's state.
  @child_assigned_root "signup"

  # The parent's final state, and the value its `assign_to` lands. The
  # child ends by reporting an outcome, the parent routes it through the
  # `on_done` slot and the root sequence finishes.
  @parent_done_state "s_blk_so_root__root_done"
  @child_outcome %{"outcome" => "done"}

  # The event that carries the wizard child to its end, out of the
  # document's own interrupt vocabulary (`blk_su_abandoned`). Sent to the
  # CHILD, which is the point: a chart deep in the tree answering its own
  # events is what "runs to depth 2" means.
  @child_end_event "signup.abandoned"

  defp fixture(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture
  end

  # The options this app starts a ROOT session with, and the one place
  # `:inherit_invoke_handlers` is passed (se-8zp). The engine defaults it
  # to `false`, so a child would otherwise start with no `:invoke_handlers`
  # at all and could not answer even the types its own document names
  # (statifier-ex st-pvpz, PR 251). Opting in is transitive: a child
  # started under it carries both the map and the flag, so a grandchild
  # inherits too.
  #
  # It is an option and not the default upstream on purpose - inheritance
  # runs a host's handlers inside charts nobody registered them for - so a
  # host that embeds charts states it, and this is the reference embedder
  # stating it.
  defp session_opts do
    [
      invoke_handlers: Charts.invoke_handlers(),
      record: true,
      inherit_invoke_handlers: true
    ]
  end

  defp session!(document, declare, opts \\ []) do
    {:ok, compiled} = Durable.compile(document, declare)
    {:ok, machine} = Statifier.compile(compiled.scxml)

    {:ok, pid} = Statifier.Session.start_link(machine, Keyword.merge(session_opts(), opts))

    on_exit(fn -> if Process.alive?(pid), do: Statifier.Session.stop(pid) end)

    pid
  end

  defp child_states(pid) do
    snapshot = Statifier.Session.snapshot(pid)
    Enum.map(snapshot.configuration, &Machine.id(snapshot.machine, &1))
  end

  # A session answers `status/1` and `invocations/1` synchronously, and both
  # queue behind the start's own drain - so by the time either returns, the
  # first macrostep is over and a child that was going to start has. No
  # sleeping, and nothing to poll.
  defp invocations(pid), do: Statifier.Session.invocations(pid)

  # The parent fixture with its subchart pointed at a document nothing
  # ships. An `Edit` rather than a second fixture file: what is under test
  # is the resolver's answer for an unknown id, and a shipped example whose
  # child does not exist would be a broken document in `priv/`.
  defp naming_a_missing_child(document) do
    [block] = for b <- StatifierBlocks.Document.blocks(document), b.id == @subchart_block, do: b
    config = Map.put(block.config, "chart", @missing)

    {:ok, edited, _inverse} = Edit.apply(document, {:update_config, @subchart_block, config})

    edited
  end

  # The evidence for "the new fixture runs the wizard as a child": a child
  # session exists, under the block's own id, and the machine it is running
  # is byte-for-byte the chart the run's pin names - the same content hash,
  # which is the identity statifier-ex ADR-0052 defines and the storage
  # layer compares. Being inside the wizard's own body is the third half of
  # it: an empty child chart would have the wrong hash, but a child sitting
  # in `s_blk_su_verify` is unambiguously the wizard.
  #
  # Sabotage: pointed `resolve_chart/2` at the invitations document instead
  # of resolving `src`; this went red on the identity assertion, the child's
  # hash naming a different chart from the one the pin names. Reverted from
  # a backup copy.
  test "the parent starts the wizard as a child session, on the chart the pin names" do
    parent = fixture(@parent)
    pid = session!(parent.document, parent.declare)

    assert [%{invoke_id: @subchart_block, pid: child}] = invocations(pid)

    snapshot = Statifier.Session.snapshot(child)
    pinned = Subchart.identities(parent.document)

    assert Machine.identity(snapshot.machine).content_hash ==
             Map.fetch!(pinned, @child_document_id)

    assert @child_verify_group in child_states(child)
  end

  # Depth 2, driven rather than read (se-8zp). The parent is depth 1 and
  # the wizard child is depth 2, and what makes it a *depth* rather than a
  # process tree is that the child dispatches its own `myapp:signup` call,
  # gets an answer, and assigns it - so the wizard's second step is
  # reachable and its datamodel root is written. None of that happened
  # before the root session opted into handler inheritance.
  #
  # Both halves are asserted because either alone is weak: a state can be
  # entered without a call being answered, and a datamodel root can be
  # seeded rather than assigned.
  #
  # Sabotage: dropped `inherit_invoke_handlers: true` from `session_opts/0`;
  # this went red on the state assertion, the child still sitting in
  # `s_blk_su_account` with `signup` still nil. Reverted from a backup copy.
  test "the wizard child answers its own calls and advances past its first step" do
    parent = fixture(@parent)
    pid = session!(parent.document, parent.declare)

    assert [%{pid: child}] = invocations(pid)

    assert @child_verify_group in child_states(child)
    refute @child_first_state in child_states(child)

    assert %{@child_assigned_root => assigned} = Statifier.Session.snapshot(child).datamodel
    assert is_map(assigned)
  end

  # The negative control for the test above, and the honest record of what
  # this document did for its whole life before st-pvpz: with inheritance
  # off - the engine's own default - the child starts, is the right chart,
  # and then parks at its first step forever, because `myapp:signup`
  # reaches a session holding no handler map at all.
  #
  # Worth keeping rather than deleting with the limitation: it is what
  # pins the option as the cause. Without it, a passing depth-2 assertion
  # says nothing about why it passes.
  #
  # Sabotage: flipped this call site's `inherit_invoke_handlers` to `true`;
  # this went red on the first-step assertion, the child having advanced
  # into `s_blk_su_verify`. Reverted from a backup copy.
  test "with inheritance off the child parks at its first step, as it did before st-pvpz" do
    parent = fixture(@parent)
    pid = session!(parent.document, parent.declare, inherit_invoke_handlers: false)

    assert [%{pid: child}] = invocations(pid)

    assert @child_first_state in child_states(child)
    assert Statifier.Session.snapshot(child).datamodel[@child_assigned_root] == nil
  end

  # The other end of depth 2: the child does not merely advance, it
  # finishes, and the outcome it finished with reaches the parent - which
  # is the one reading `signup_onboarding` exists for. The event goes to
  # the CHILD, out of the wizard's own interrupt vocabulary, so what drives
  # the run to its end is a chart one level down answering its own event.
  #
  # `{:halted, :done}` off a subscription rather than a poll: the parent's
  # finish is several hops after this call returns (the child ends, reports
  # `done.invoke`, the parent routes it through `on_done`, runs the notify
  # there and completes), and a snapshot taken before those hops is a race,
  # not a result. The subscription's halt message is the last one a session
  # sends for a run (st ADR-0044 decision 2).
  #
  # Sabotage: dropped `inherit_invoke_handlers: true` from `session_opts/0`;
  # this went red on `assert_receive` timing out - the parked child never
  # ends, so the parent never finishes. Reverted from a backup copy.
  test "the child runs to an outcome and the parent routes on it" do
    parent = fixture(@parent)
    pid = session!(parent.document, parent.declare)

    :ok = Statifier.Session.subscribe(pid, self())
    assert [%{pid: child}] = invocations(pid)

    Statifier.Session.send_event(child, @child_end_event)

    assert_receive {:statifier, _session_id, {:halted, :done}}, 5_000

    assert %{status: :done, configuration: configuration} = Statifier.Session.status(pid)
    assert @parent_done_state in configuration
    assert Statifier.Session.snapshot(pid).datamodel["onboarding"] == @child_outcome
    assert outcome_reported(pid) == @child_outcome
  end

  # `unknown_document`, the first of campaign-023 ruling R-b's three
  # refusal reasons, read from the parent rather than from the handler: the
  # package raises `error.communication.invoke.<block id>` and the block's
  # own compiled transition routes it to the `on_error` slot. So what a
  # host sees is its own error path taken, which is what this asserts.
  #
  # The event is read out of the session's own recording rather than off
  # the configuration: the `on_error` slot here runs a notify and finishes,
  # so by the time a caller looks, the parent has left that state. The
  # raised event is the durable evidence, and it carries the reason - which
  # is the half a host actually routes on.
  #
  # `attempts` is deliberately absent from the payload: a refusal made no
  # attempt (`StatifierBlocks.Runtime.Subchart`, campaign-023 ruling R-b).
  # Asserting the whole data map is what pins that absence.
  #
  # Sabotage: made `resolve_chart/2` fall back to the first fixture for an
  # id nothing ships, so every id resolved; this went red on the refute - a
  # child session stood under the subchart block's id and nothing was
  # refused. Reverted from a backup copy.
  test "a chart id nothing ships is refused as unknown_document, with the id in the detail" do
    parent = fixture(@parent)
    pid = parent.document |> naming_a_missing_child() |> session!(parent.declare)

    refute Enum.any?(invocations(pid), &(&1.invoke_id == @subchart_block))
    assert refusal(pid) == %{"reason" => "unknown_document", "detail" => %{"chart" => @missing}}
  end

  # Sabotage: made `references/1` read the `assign_to` config key instead of
  # `chart`; this went red on the first assertion, answering the value the
  # outcome is written to rather than the chart it came from. Reverted from
  # a backup copy.
  test "references/1 reads the child document ids off the blocks that name them" do
    assert Subchart.references(fixture(@parent).document) == [@child_document_id]
    assert Subchart.references(fixture("signup_wizard").document) == []
  end

  # A pin is a pin: there is nothing to record for a child that cannot be
  # resolved, and the run finds out at execution time instead (the refusal
  # the test above drives). Recording an error string here would put a
  # value in the provenance slot that names no chart.
  #
  # Sabotage: made `identity/1` record `{document_id, "unresolved"}` on the
  # `:error` arm; this went red. Reverted from a backup copy.
  test "identities/1 pins the children that resolve and stays silent about the rest" do
    parent = fixture(@parent)

    assert %{@child_document_id => "sha256:" <> _hash} = Subchart.identities(parent.document)
    assert parent.document |> naming_a_missing_child() |> Subchart.identities() == %{}
  end

  # The single-level rule, asserted over the shipped set rather than left to
  # a comment in a fixture. It is now an authoring choice about which
  # documents this app ships and no longer an engine limit: with
  # `inherit_invoke_handlers: true` a grandchild inherits the map too
  # (statifier-ex st-pvpz), so a nested subchart would run. What the rule
  # still buys is what makes `resolve_chart/2`'s missing `{:cycle, _}` arm
  # honest: a graph one level deep, fixed at build time, has no cycle to
  # refuse. Deepening the shipped set is the day that arm gets written.
  #
  # Sabotage: added a `core.subchart` naming `bdoc_su_invites_demo` to the
  # wizard document in memory before the walk; this went red naming
  # `bdoc_signup_demo` as a child that is itself a parent. Reverted from a
  # backup copy.
  test "no shipped document that is used as a child names a subchart of its own" do
    children =
      Charts.fixtures()
      |> Enum.flat_map(&Subchart.references(&1.document))
      |> Enum.uniq()

    for document_id <- children do
      {:ok, fixture} = Enum.find_value(Charts.fixtures(), :error, &child(&1, document_id))

      assert Subchart.references(fixture.document) == [],
             "#{document_id} is used as a child and names a subchart of its own (se-8zp)"
    end
  end

  # The pin is only true while the compile that builds it and the compile
  # the package runs produce the same bytes. Both are `child_use: true`
  # against this app's palette with its registered invoke types; this
  # re-derives the hash from the child fixture directly, so a recipe that
  # drifted in `Subchart` alone goes red here.
  #
  # Sabotage: dropped `child_use: true` from `child_compile/1`; this went
  # red - the pinned hash and the hash re-derived here named different
  # charts, which differ by exactly the outcome finals `:child_use` emits.
  # Reverted from a backup copy.
  test "the pinned hash is the child compiled as a child, against this app's palette" do
    child = fixture("signup_wizard")

    {:ok, %Compiled{scxml: scxml}} =
      Compiler.compile(child.document, Charts.palette(),
        child_use: true,
        known_invoke_types: Charts.invoke_types()
      )

    assert Subchart.identities(fixture(@parent).document) == %{
             @child_document_id => Identity.of_source(scxml).content_hash
           }
  end

  defp child(fixture, document_id) do
    if fixture.document.id == document_id, do: {:ok, fixture}
  end

  # The `data:` of the one refusal this session raised, or `nil`. Read off
  # `Statifier.Session.recording/1`, which is what a session started with
  # `record: true` keeps.
  defp refusal(pid) do
    {:ok, recording} = Statifier.Session.recording(pid)

    Enum.find_value(recording.entries, fn
      {:internal, :platform, @refusal_event, _origin, opts, _routes} -> Keyword.get(opts, :data)
      _other -> nil
    end)
  end

  # The `data:` the child's `done.invoke` carried, read off the parent's
  # recording. A finished child reports its outcome as an invoked event
  # keyed on the block's own id, which is the value `assign_to` writes and
  # the `on_*` slots route on - so this is the same fact as the datamodel
  # assertion, read at the wire rather than after the assign.
  defp outcome_reported(pid) do
    {:ok, recording} = Statifier.Session.recording(pid)

    Enum.find_value(recording.entries, fn
      {:invoked_event, @subchart_block, %Statifier.Event{data: data}, _routes} -> data
      _other -> nil
    end)
  end
end
