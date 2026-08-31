defmodule StatifierExamples.Charts.SubchartTest do
  @moduledoc """
  What this app's `statifier_blocks:subchart` handler does, driven rather
  than read: a `Statifier.Session` started with
  `StatifierExamples.Charts.invoke_handlers/0` runs the parent fixture, and
  what the assertions read is the child session that came out of it.

  The refusal set and the planning are `statifier_blocks`' and are tested
  where they live (sb-6edf). What is this app's is the resolver over its
  own fixtures, the pin `identities/1` builds, and the single-level limit
  the shipped documents are written to - so those are what is asserted
  here.
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

  # The wizard's first step, which is where a child session sits as soon as
  # it starts: `myapp:signup` is an invoke, and a child is started without
  # the parent's handlers (st-pvpz), so it stays there. That it is REACHED
  # is what makes it evidence that the child is the wizard.
  @child_first_state "s_blk_su_account"

  defp fixture(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture
  end

  defp session!(document, declare) do
    {:ok, compiled} = Durable.compile(document, declare)
    {:ok, machine} = Statifier.compile(compiled.scxml)

    {:ok, pid} =
      Statifier.Session.start_link(machine,
        invoke_handlers: Charts.invoke_handlers(),
        record: true
      )

    on_exit(fn -> if Process.alive?(pid), do: Statifier.Session.stop(pid) end)

    pid
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
  # layer compares. Reaching the wizard's first step is the third half of
  # it: an empty child chart would have the wrong hash, but a child sitting
  # in `s_blk_su_account` is unambiguously the wizard.
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

    assert @child_first_state in Enum.map(
             snapshot.configuration,
             &Machine.id(snapshot.machine, &1)
           )
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
  # a comment in a fixture. A child session is started without the parent's
  # `:invoke_handlers` (statifier-ex st-pvpz), so a child that names a
  # subchart of its own would start a grandchild nothing can run. This is
  # also what makes `resolve_chart/2`'s missing `{:cycle, _}` arm honest:
  # a graph one level deep, fixed at build time, has no cycle to refuse.
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
             "#{document_id} is used as a child and names a subchart of its own (st-pvpz)"
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
end
