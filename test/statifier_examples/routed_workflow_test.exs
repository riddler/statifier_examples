defmodule StatifierExamples.RoutedWorkflowTest do
  @moduledoc """
  The routed first-workflow recipe, run the way
  `mix statifier_examples.first_workflow_routed` runs it: every step of
  `docs/guides/first-workflow-routed.md` against this app's own database
  and Oban instance, which the test configuration keeps in
  `testing: :manual`, so every job here runs because the recipe drained
  its queue.

  Not async: the recipe steps through the application's named
  serialization strategy and drains the shared Oban instance.
  """
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias Mix.Tasks.StatifierExamples.FirstWorkflowRouted
  alias Statifier.{Event, Machine}
  alias StatifierExamples.{FirstWorkflow, Repo, RoutedWorkflow}
  alias StatifierExamples.RoutedWorkflow.{DoorstepNotice, DoorstepRoute, PublishedCharts, Stepper}
  alias StatifierPersistence.{Execution, Executions, Storage}

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: dropped `on_complete:` from `RoutedWorkflow.config/0`; the
  # doorstep scan finished the execution with no notice queued, and this
  # went red with the recipe naming the `completed` step. Reverted from a
  # copy.
  test "runs the whole recipe, and every scan reaches the parcel's one execution" do
    assert {:ok, lines} = RoutedWorkflow.run(parcel_id: "parcel-test")

    assert [
             "first workflow routed on statifier_router 0.6." <> _pins,
             "migrated     4 router tables, depot_id at position 2 on each",
             "published    bdoc_parcel_route accepts parcel.scanned; " <>
               "every publish-time check passed, 0 warning(s)",
             "guarded      a binding naming an event bdoc_parcel_route does not accept " <>
               "is refused at the contracts stage",
             "registered   chart sha256:" <> _hash,
             "created      parcel parcel-test: execution " <> created,
             "duplicate    the depot scan routed again: duplicate, no execution read or stepped",
             "completed    the doorstep scan delivered to " <> completed,
             "finished     a late scan dropped: finished; the ledger reads " <>
               "created_and_delivered, duplicate, delivered, dropped: finished",
             "reaped       past the 1000 ms horizon: 3 dedupe row(s) and 1 address row(s) removed",
             "ended        completed at " <> _ended_at,
             "trace        the input log, oldest first:" | trace
           ] = lines

    [execution_id, "created and delivered"] = String.split(created, ", ")
    assert completed == "#{execution_id}: completed, 1 doorstep notice sent"

    assert [
             "  0 step parcel.scanned at depot",
             "  1 step parcel.scanned at doorstep"
           ] = trace

    {:ok, record} = Storage.fetch_execution(FirstWorkflow.store(), execution_id)
    execution = Execution.from_record(record)
    assert %Execution{status: :completed, ended_at: %DateTime{}} = execution
    assert Executions.ended?(execution)
  end

  # Sabotage: made `Stepper.create/4` drop the `serialization:` it adds; the
  # router's create took the adapter lock this app's SQLite adapter does not
  # offer, and this went red. Reverted from a copy.
  test "the stepper hands the router's calls this app's serialization" do
    {:ok, machine, _scxml} = RoutedWorkflow.runtime_chart()
    store = FirstWorkflow.store()
    opts = [executor: &RoutedWorkflow.execute/2]

    assert {:error, {:serialization, :not_supported}} =
             Executions.create(store, "routed_no_lock", machine, opts)

    assert {:ok, %Execution{status: :active}, _state} =
             Stepper.create(store, "routed_with_lock", machine, opts)
  end

  # Sabotage: made `PublishedCharts.resolve/2` skip the registry read; the
  # unregistered chart resolved, and this went red. Reverted from a copy.
  test "the resolver answers only a chart the registry holds" do
    document = RoutedWorkflow.document_id()

    assert {:error, :not_published} = PublishedCharts.resolve("depot_eastside", document)
    assert {:error, :not_published} = PublishedCharts.resolve("depot_eastside", "bdoc_other")

    {:ok, machine, scxml} = RoutedWorkflow.runtime_chart()
    :ok = Storage.save_chart(FirstWorkflow.store(), machine, scxml)
    hash = Machine.identity(machine).content_hash

    assert {^hash, %Machine{}} = PublishedCharts.resolve("depot_eastside", document)
    assert {:ok, %Machine{}} = PublishedCharts.chart(hash)
    assert :error = PublishedCharts.chart("sha256:none")
  end

  # Sabotage: dropped `unique:` from `DoorstepNotice`'s `use Oban.Worker`;
  # the second hand-off queued a second notice, and this went red. Reverted
  # from a copy.
  test "the route queues one notice per idempotency key, however often it is handed over" do
    event = %Event{Event.external("done.execution") | origin: "ex_route_test"}
    position = %{send_id: nil, macrostep: 2, microstep: 1, round: 0, c_index: nil, owner: nil}
    key = {"ex_route_test", position, nil}

    assert :ok = DoorstepRoute.deliver(%{queue: :parcel_notices}, event, key)
    assert :ok = DoorstepRoute.deliver(%{queue: :parcel_notices}, event, key)

    worker = inspect(DoorstepNotice)

    assert [
             %Oban.Job{
               args: %{"execution_id" => "ex_route_test", "key" => "ex_route_test:2:1:0:-"}
             }
           ] =
             Repo.all(from(j in Oban.Job, where: j.worker == ^worker))
  end

  # Sabotage: made the task print none of the lines; this went red.
  # Reverted from a copy.
  test "the mix task prints every line the recipe answers" do
    Mix.shell(Mix.Shell.Process)

    try do
      FirstWorkflowRouted.run([])
    after
      Mix.shell(Mix.Shell.IO)
    end

    assert_received {:mix_shell, :info, ["first workflow routed on " <> _pins]}
    assert_received {:mix_shell, :info, ["ended        completed at " <> _ended_at]}
  end
end
