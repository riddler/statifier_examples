defmodule StatifierExamples.PersistenceTest do
  @moduledoc """
  `StatifierExamples.Persistence`'s own callback: the child enumeration
  that opts this adapter into durable subcharts (se-6ag).

  The package's conformance suite - run next door in
  `StatifierExamples.PersistenceConformanceTest` - already generates the
  containment case for any adapter that exports
  `list_runs_by_metadata/2`, and it is the case that matters. What is here
  is the part the suite does not cover and this adapter can still get
  wrong on its own: the refusals, and the multi-match ordering a cascade
  actually depends on.

  From se-j87 it also covers the two callbacks a Tier A fan-out needs at
  open - `supports_run_outcome?/1` and `list_run_states_by_metadata/2` -
  for the same reason: the projection is built here rather than delegated,
  so its shape is this adapter's own to get wrong.
  """

  # Not async: writes to the repo.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Persistence
  alias StatifierPersistence.Run.Linkage
  alias StatifierPersistence.Storage

  setup do
    :ok = Sandbox.checkout(StatifierExamples.Repo)
    {:ok, store} = Storage.new(Persistence, [])

    %{opts: store.opts}
  end

  defp insert!(opts, run_id, metadata) do
    :ok =
      Persistence.insert_run(opts, %{
        run_id: run_id,
        status: :active,
        content_hash: "sha256:persistence-test",
        identity_blob: <<1, 2, 3>>,
        position_blob: <<7, 8, 9>>,
        failure: nil,
        metadata: metadata
      })
  end

  # A parent with two children under two different invocations, plus an
  # unrelated run and one belonging to somebody else's parent. Both of the
  # driver's own match shapes are asserted against it, because the cascade
  # uses one and `StatifierExamples.Charts.Durable.abandon/1` uses the
  # other, and getting the containment right for one and wrong for the
  # other would cancel either too little or far too much.
  #
  # Sabotage: made `contains?/2` compare a map value with `==` instead of
  # recursing; this went red on the first assertion - the nested match
  # found nothing, because a match naming only `parent_run_id` never
  # equals a stored map that also carries `invoke_id`, `child_index` and
  # `content_hash`. Reverted.
  test "list_runs_by_metadata matches both of the driver's linkage shapes", %{opts: opts} do
    insert!(
      opts,
      "run-a/call-one/0",
      Linkage.to_metadata(Linkage.new("run-a", "call-one", 0, "h"))
    )

    insert!(
      opts,
      "run-a/call-two/0",
      Linkage.to_metadata(Linkage.new("run-a", "call-two", 0, "h"))
    )

    insert!(
      opts,
      "run-b/call-one/0",
      Linkage.to_metadata(Linkage.new("run-b", "call-one", 0, "h"))
    )

    insert!(opts, "run-unrelated", %{"fixture" => "signup_wizard"})

    assert {:ok, every_child} =
             Persistence.list_runs_by_metadata(opts, Linkage.parent_match("run-a"))

    assert Enum.map(every_child, & &1.run_id) |> Enum.sort() ==
             ["run-a/call-one/0", "run-a/call-two/0"]

    assert {:ok, one_invocation} =
             Persistence.list_runs_by_metadata(
               opts,
               Linkage.invocation_match("run-a", "call-two")
             )

    assert Enum.map(one_invocation, & &1.run_id) == ["run-a/call-two/0"]
  end

  # The records come back in `fetch_run/2`'s shape, because that is what
  # the storage contract says they are and what the cascade reads a status
  # off. Asserted rather than assumed: this adapter builds the list itself
  # rather than delegating the query, so the shape is its own to get wrong.
  #
  # Sabotage: made the reduce collect the `{run_id, metadata}` tuples it
  # filtered on instead of calling `fetch_run/2`; this went red on the
  # status key. Reverted.
  test "list_runs_by_metadata answers records in fetch_run's shape", %{opts: opts} do
    insert!(opts, "run-c/call/0", Linkage.to_metadata(Linkage.new("run-c", "call", 0, "h")))

    assert {:ok, [record]} =
             Persistence.list_runs_by_metadata(opts, Linkage.parent_match("run-c"))

    assert record.status == :active
    assert record.content_hash == "sha256:persistence-test"
    assert record.position_blob == <<7, 8, 9>>
  end

  # The one mistake this callback is able to make. An empty match map is
  # contained by every stored map, so answering it would hand a cascade
  # every run in the table to cancel. Both package adapters raise instead,
  # and so does this one.
  #
  # Sabotage: deleted the `map_size(match) > 0` guard from
  # `validate_match!/1`, so an empty map took the string-keys arm and
  # passed; this went red - every inserted run came back. Reverted.
  test "list_runs_by_metadata refuses an empty match rather than matching everything", %{
    opts: opts
  } do
    insert!(opts, "run-d/call/0", Linkage.to_metadata(Linkage.new("run-d", "call", 0, "h")))

    assert_raise ArgumentError, fn -> Persistence.list_runs_by_metadata(opts, %{}) end
    assert_raise ArgumentError, fn -> Persistence.list_runs_by_metadata(opts, %{key: "atom"}) end
    assert_raise ArgumentError, fn -> Persistence.list_runs_by_metadata(opts, "not a map") end
  end

  # `StatifierPersistence.Driver.start_child_at/6` asks the store three
  # questions before it creates anything, and refuses the whole fan-out if
  # any of them answers no. Asserted through `Storage`'s own wrappers
  # rather than by calling this module's callbacks directly, because the
  # wrappers are what the driver actually consults - each reads both the
  # export and `supports_metadata?/1`, so a callback exported without the
  # metadata declaration beside it would still refuse.
  #
  # Sabotage: made `supports_run_outcome?/1` answer `false`; this went red
  # on the second assertion. Reverted.
  test "the three capability guards a fan-out is opened against all hold" do
    {:ok, store} = Storage.new(Persistence, [])

    assert Storage.child_listing_supported?(store)
    assert Storage.run_outcome_supported?(store)
    assert Storage.run_states_supported?(store)
  end

  # The projection's whole point is that it answers "have all N settled,
  # and at which indices" without moving a blob per child, so what it
  # answers is three values and not a record. The index comes off the
  # linkage the package wrote, and the status comes off the stored string
  # as the atom the projection's type names.
  #
  # Sabotage: made `child_index/1` read `"index"` instead of
  # `"child_index"`; this went red with every index `nil`. Reverted.
  test "list_run_states_by_metadata projects run_id, status and child_index", %{opts: opts} do
    for index <- 0..2 do
      insert!(
        opts,
        "run-f/call/#{index}",
        Linkage.to_metadata(Linkage.new("run-f", "call", index, "h", 3, :first_error))
      )
    end

    assert {:ok, states} =
             Persistence.list_run_states_by_metadata(opts, Linkage.parent_match("run-f"))

    assert Enum.sort_by(states, & &1.child_index) == [
             %{run_id: "run-f/call/0", status: :active, child_index: 0},
             %{run_id: "run-f/call/1", status: :active, child_index: 1},
             %{run_id: "run-f/call/2", status: :active, child_index: 2}
           ]
  end

  # A matched run carrying no linkage answers `child_index: nil` rather
  # than raising or being dropped - the callback's own type says so, and a
  # match written wide enough to catch a parent is how it happens.
  #
  # Sabotage: made `child_index/1` raise on a metadata map with no
  # reserved key; this went red. Reverted.
  test "list_run_states_by_metadata answers nil for a run with no linkage", %{opts: opts} do
    insert!(opts, "run-g", %{"fixture" => "signup_bulk_invites"})

    assert {:ok, [state]} =
             Persistence.list_run_states_by_metadata(opts, %{
               "fixture" => "signup_bulk_invites"
             })

    assert state == %{run_id: "run-g", status: :active, child_index: nil}
  end

  # The same refusal `list_runs_by_metadata/2` makes, for a worse reason:
  # a settlement that read every run in the table as its own children
  # would answer a parent on behalf of runs that are nobody's child.
  #
  # Sabotage: dropped the `validate_match!/1` call from
  # `list_run_states_by_metadata/2`; this went red on the first
  # assertion. Reverted.
  test "list_run_states_by_metadata refuses an empty or badly keyed match", %{opts: opts} do
    insert!(opts, "run-h/call/0", Linkage.to_metadata(Linkage.new("run-h", "call", 0, "h")))

    assert_raise ArgumentError, fn -> Persistence.list_run_states_by_metadata(opts, %{}) end

    assert_raise ArgumentError, fn ->
      Persistence.list_run_states_by_metadata(opts, %{key: "atom"})
    end

    assert_raise ArgumentError, fn ->
      Persistence.list_run_states_by_metadata(opts, "not a map")
    end
  end
end
