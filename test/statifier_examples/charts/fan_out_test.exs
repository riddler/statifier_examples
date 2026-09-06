defmodule StatifierExamples.Charts.FanOutTest do
  @moduledoc """
  The hybrid fan-out, end to end: a `core.map` over ten chunk
  descriptors, one bulk data-plane call per chunk, one promoted row with
  a run of its own, and both aggregation policies proved through the
  parent's own door (se-j87).
  """

  # Not async: durable runs step through the application's own
  # `StatifierExamples.Charts.RunLock`, which is named, shared state, and
  # they write to the repo and to the Oban jobs table.
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable, FanOut}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.Invites
  alias StatifierOban.Invoke.ChildStartWorker

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run_id: "fan-#{System.unique_integer([:positive])}"}
  end

  defp start!(key, run_id) do
    {:ok, fixture} = Charts.fixture(key)
    {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)

    {:ok, {_durable, run}} = Durable.start(compiled, fixture.document, run_id, key)

    run
  end

  defp datamodel(run_id) do
    {:ok, machine_state} = Durable.machine_state(run_id)

    machine_state.datamodel
  end

  defp start_jobs do
    Repo.all(from(j in Oban.Job, where: j.worker == ^inspect(ChildStartWorker)))
  end

  defp drain, do: Oban.drain_queue(queue: AsyncCalls.queue())

  # The type is registered but is not a call, and the word says which:
  # falling through to `:unknown_invoke_type` would tell a reader of the
  # feed that this app does not answer `core.map`, and it does.
  #
  # Sabotage: dropped the `FanOut.fan_out?/1` arm from
  # `Charts.dispatch/3`; this went red with `:unknown_invoke_type`.
  # Reverted.
  test "the map invoke type is registered and is refused as a sync call" do
    assert FanOut.invoke_type() in Charts.invoke_types()
    assert Map.has_key?(Charts.invoke_handlers(), FanOut.invoke_type())
    assert Map.keys(Charts.invoke_handlers()) |> Enum.sort() == Charts.invoke_types()

    assert {:error, {:fan_out_not_a_sync_call, _type}} =
             Charts.dispatch(FanOut.invoke_type(), %{}, %{})
  end

  # The parent's own step creates nothing. N creates cannot hold the
  # parent's exclusion, so what a fan-out's dispatch does is store one job
  # and rest with the invocation live - which is an asynchronous
  # invocation from the parent's point of view, one layer up.
  #
  # Sabotage: made the dispatch fun's fan-out arm answer `{:ok, %{}}`
  # instead of `:pending`; this went red - the parent completed with no
  # job stored. Reverted.
  test "the parent rests with one fan-out job stored and no children", %{run_id: run_id} do
    run = start!("signup_bulk_invites", run_id)

    assert run.status == :running
    assert start_jobs() == []
    assert Repo.aggregate(Oban.Job, :count) == 1
    assert Repo.aggregate(from(r in "statifier_runs", select: r.run_id), :count) == 1
  end

  # The whole shape, once: ten descriptors in, ten chunk children, ten
  # answers assembled into one dense list at the author's `collect` path,
  # and the two hundred and fifty rows in the host's own table where the
  # boundary rule puts them.
  #
  # What the assembled entry carries is the child's own donedata, and on
  # `statifier_blocks` 0.19.0 a child answers its OUTCOME NAME and
  # nothing else - `child_use: true` emits
  # `<donedata><param expr="'done'" name="outcome"/></donedata>` and
  # there is no authoring surface for a richer one. So the per-chunk
  # summary the handler builds reaches the host's table and the run feed
  # rather than the parent's datamodel. That gap is reported upstream
  # rather than worked around here, and the assertions below say what the
  # shipped vocabulary actually gives.
  #
  # Sabotage: made `Invites.record/3` write nothing; this went red on the
  # row count while the assembled list stayed green - which is the
  # boundary being real rather than asserted, since the chart's answer
  # and the data plane's rows are two different writes. Reverted.
  test "on: all fans out over ten descriptors and assembles ten answers", %{run_id: run_id} do
    start!("signup_bulk_invites", run_id)

    assert %{success: 1} = drain()
    assert length(start_jobs()) == 10

    assert %{success: 10} = drain()

    results = Map.fetch!(datamodel(run_id), "results")

    assert length(results) == 10
    assert Enum.map(results, & &1["index"]) == Enum.to_list(0..9)
    assert Enum.all?(results, &(&1["status"] == "completed"))
    assert Enum.all?(results, &(&1["donedata"] == %{"outcome" => "done"}))

    assert Invites.count() == 250
  end

  # The descriptor reached the index it belongs to, proved where the
  # evidence actually is: a chunk's rows carry the run that wrote them,
  # and a fan-out child's run id is the parent's plus the invocation plus
  # the index. So `su-c07`'s rows being written by `.../blk_bi_chunks/6`
  # is the seventh descriptor having been handed to the seventh child.
  #
  # Sabotage: made `FanOut.start_child/5` seed `Enum.at(descriptors, 0)`
  # for every index; this went red - every chunk's rows named child 0.
  # Reverted.
  test "each descriptor is seeded into the child at its own index", %{run_id: run_id} do
    start!("signup_bulk_invites", run_id)

    assert %{success: 1} = drain()
    assert %{success: 10} = drain()

    for {n, index} <- Enum.with_index(1..10) do
      chunk = "su-c#{String.pad_leading("#{n}", 2, "0")}"
      rows = Invites.for_chunk(chunk)

      assert length(rows) == 25
      assert Enum.all?(rows, &(&1.run_id == "#{run_id}/blk_bi_chunks/#{index}"))
    end
  end

  # The other half of the boundary rule. One invitee's signup waits on a
  # person, which is chart semantics and not a row's, so that row gets an
  # ordinary run of the wizard - openable, resumable and drivable like
  # any other, which is what `resume/1` answering it proves.
  #
  # Sabotage: made `Promotion.promote/1` answer `{:ok, :none}` for every
  # chunk; this went red on the promoted row count. Reverted.
  test "exactly one row is promoted to a run of its own", %{run_id: run_id} do
    start!("signup_bulk_invites", run_id)

    assert %{success: 1} = drain()
    assert %{success: 10} = drain()

    assert [promoted] = Invites.promoted()
    assert promoted.chunk_id == "su-c07"
    assert promoted.email == "invitee-su-c07-3@example.com"
    assert promoted.status == "promoted"
    assert promoted.promoted_run_id == "promoted-su-c07"

    assert {:ok, {{_durable, run}, document}} = Durable.resume("promoted-su-c07")
    assert document.id == "bdoc_signup_demo"
    assert run.status == :running

    assert Invites.count() == 250
  end

  # A start job is at-least-once, so the whole chain has to be. The child
  # run is adopted rather than created twice, the rows are one set rather
  # than two, and the promoted invitee has one run and not a second.
  #
  # Sabotage: made `Invites.promoted_run_id/1` mint a fresh id per call;
  # this went red - the second delivery started a second wizard run.
  # Reverted.
  test "a redelivered chunk start is idempotent", %{run_id: run_id} do
    start!("signup_bulk_invites", run_id)

    assert %{success: 1} = drain()
    assert %{success: 10} = drain()

    before_rows = Invites.count()
    before_runs = Repo.aggregate(from(r in "statifier_runs", select: r.run_id), :count)

    job = Enum.find(start_jobs(), &(&1.args["index"] == 6))
    assert :ok = ChildStartWorker.perform(job)

    assert Invites.count() == before_rows
    assert Repo.aggregate(from(r in "statifier_runs", select: r.run_id), :count) == before_runs
  end

  # `first_error` cancels the rest, and the half only a host can reach is
  # the unstarted one: an index whose start job has not run has no run
  # record for the cascade to walk, so the driver's `child_canceller:`
  # seam is what cancels its job.
  #
  # The one executed start job is driven through `perform/1` on its own
  # stored row rather than through a drain, so the other nine are still
  # `available` when the failure settles. That also means the executed
  # row is never transitioned to `completed` the way a real queue run
  # would transition it, so the assertions below name the nine sibling
  # indices rather than counting cancelled rows.
  #
  # Sabotage: dropped `child_canceller:` from the driver; this went red -
  # the nine sibling start jobs stayed `available`. Reverted.
  test "on: first_error cancels the siblings that never started", %{run_id: run_id} do
    start!("signup_bulk_invites_strict", run_id)

    assert %{success: 1} = drain()
    assert length(start_jobs()) == 10
    assert Enum.all?(start_jobs(), &(&1.state == "available"))

    refused = Enum.find(start_jobs(), &(&1.args["index"] == 3))
    assert :ok = ChildStartWorker.perform(refused)

    siblings = Enum.reject(start_jobs(), &(&1.args["index"] == 3))

    assert length(siblings) == 9

    assert Enum.all?(siblings, &(&1.state == "cancelled")),
           "expected every sibling start job cancelled, got: " <>
             inspect(Enum.map(siblings, &{&1.args["index"], &1.state}))

    assert %{success: 0} = drain()

    results = Map.fetch!(datamodel(run_id), "results")

    assert length(results) == 10
    assert Enum.map(results, & &1["index"]) == Enum.to_list(0..9)
    assert Enum.at(results, 3)["status"] == "failed"

    assert results |> List.delete_at(3) |> Enum.all?(&(&1["status"] == "cancelled"))

    assert Invites.count() == 0
  end

  # A failed child and a cancelled sibling sit at different indices of the
  # same answer, so the page has to call them different things. It did not
  # until this bead: nothing in this app produced a `:failed` run before a
  # fan-out did, and `finish/2` folded `:failed` into `:cancelled`'s word.
  # A browser capture of the strict document is what found it.
  #
  # Sabotage: pointed `finish(run, :failed)` back at `{:halted,
  # :cancelled}`; this went red on the first assertion. Reverted.
  test "a failed chunk reads failed, not cancelled", %{run_id: run_id} do
    start!("signup_bulk_invites_strict", run_id)

    assert %{success: 1} = drain()

    refused = Enum.find(start_jobs(), &(&1.args["index"] == 3))
    assert :ok = ChildStartWorker.perform(refused)

    assert {:ok, {{_durable, child}, _document}} =
             Durable.resume("#{run_id}/blk_bi_chunks/3")

    assert child.status == :failed
  end
end
