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
end
