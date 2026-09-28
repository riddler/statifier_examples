defmodule StatifierExamples.FirstWorkflowTest do
  @moduledoc """
  The first-workflow recipe, run the way `mix statifier_examples.first_workflow`
  runs it: every step of `docs/guides/first-workflow.md` against this app's
  own database and Oban instance, which the test configuration keeps in
  `testing: :manual`, so every job here runs because the recipe drained
  its queue.

  Not async: the recipe steps through the application's named
  serialization strategy and drains the shared Oban instance.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Statifier.Effect.Invoke
  alias StatifierExamples.Charts.ExecutionLock
  alias StatifierExamples.{FirstWorkflow, Repo}
  alias StatifierExamples.FirstWorkflow.{Delivery, SetAside}
  alias StatifierPersistence.{Driver, Execution, Executions, Storage}

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: made `open/3` create the execution without the hold in its
  # datamodel; the set-aside job answered `{:error, {:no_hold, _}}` and was
  # left to retry, and this went red with the recipe naming the `acted`
  # step timed out. Reverted from a copy.
  test "runs the whole recipe, and the execution completes with a stamp and a trace" do
    execution_id = "first_workflow_test_run"

    assert {:ok, lines} = FirstWorkflow.run(execution_id: execution_id)

    assert [
             "first workflow on statifier 2.9." <> _pins,
             "expressible  bdoc_hold_pickup against the host palette",
             "published    every publish-time check passed, 0 warning(s)",
             "registered   chart sha256:" <> _hash,
             "opened       execution first_workflow_test_run: active, the set-aside call queued",
             "acted        myapp:set_aside answered under a 5000 ms bound: " <>
               ~s(%{"copy" => "c-2291", "shelf" => "Eastside branch hold shelf"}),
             "timer fired  the pickup window elapsed",
             "ended        completed at " <> _ended_at,
             "trace        the input log, oldest first:" | trace
           ] = lines

    assert [
             "  0 done_invocation done.invoke." <> _invoke_id,
             "  1 step statifier_blocks.wait." <> _wait
           ] = trace

    {:ok, record} = Storage.fetch_execution(FirstWorkflow.store(), execution_id)
    execution = Execution.from_record(record)
    assert %Execution{status: :completed, ended_at: %DateTime{}} = execution
    assert Executions.ended?(execution)
  end

  # Sabotage: dropped `invoke_timeout:` from `FirstWorkflow.config/0`; the
  # bound read back `:infinity` and this went red. Reverted from a copy.
  test "the set-aside call runs under a finite run-time bound" do
    assert %StatifierOban.Config{invoke_timeout: 5_000} = SetAside.config()
  end

  # Sabotage: made `SetAside.run/1` answer `{:ok, %{}}` for every
  # invocation; the no-hold clause went red. Reverted from a copy.
  test "the set-aside act answers a shelf for a hold and refuses anything else" do
    hold = %{"patron" => "p-1", "copy" => "c-1", "branch" => "Northside branch"}

    assert {:ok, %{"copy" => "c-1", "shelf" => "Northside branch hold shelf"}} =
             SetAside.run(invoke(%{"hold" => hold}))

    assert {:error, {:no_hold, %{}}} = SetAside.run(invoke(%{}))
  end

  defp invoke(params) do
    %Invoke{
      type: "myapp:set_aside",
      params: params,
      invoke_id: "inv_1",
      state_index: 0,
      invoke_index: 0,
      macrostep: 1,
      microstep: 1,
      round: 0
    }
  end

  # Sabotage: made `Delivery.drive/2` throw before it read the execution;
  # this went red, with the recipe and the task tests. Reverted from a
  # copy.
  test "a delivery to an execution that was never opened is discarded, not raised" do
    assert {:discarded, _reason} = Delivery.deliver("first_workflow_nobody", "inv_1", %{})
  end

  # The pickup window elapsing while a migration has the hold parked: the
  # timer job is retried rather than cancelled, and once the execution is
  # unparked the same firing ends the hold. The recipe runs once first so
  # the chart is registered; the second execution is opened on it through
  # the recipe's own driver. The park is written through
  # `Storage.update_execution_status/4`, as a migration's own park writes
  # it; the unpark is the package's `Executions.unpark/3`.
  #
  # Sabotage: made the timer `deliver/2`'s `{:needs_migration, _}` clause
  # answer `{:discarded, :needs_migration}`; the first timer drain cancelled
  # the job and this went red on `%{failure: 1}`. Reverted from a copy.
  test "a pickup window that elapses into a parked execution is retried and ends it once unparked" do
    assert {:ok, _lines} = FirstWorkflow.run(execution_id: "first_workflow_registers")

    store = FirstWorkflow.store()
    {:ok, machine} = FirstWorkflow.machine_for(store, "first_workflow_registers")
    execution_id = "first_workflow_parked"
    hold = %{"patron" => "p-1043", "copy" => "c-3107", "branch" => "Northside branch"}

    assert {:ok, %Execution{status: :active}, _machine_state} =
             store
             |> FirstWorkflow.driver(machine)
             |> Driver.create(execution_id, initialize: [datamodel: %{"hold" => hold}])

    # The set-aside answer lands and the wait arms the pickup window.
    assert %{success: 1} = Oban.drain_queue(queue: :statifier_invocations)

    :ok = Storage.update_execution_status(store, execution_id, :needs_migration)

    assert %{failure: 1, cancelled: 0, success: 0} =
             Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

    assert {:ok, %{status: :needs_migration}} = Storage.fetch_execution(store, execution_id)

    assert {:ok, %Execution{status: :active}} =
             Executions.unpark(store, execution_id, serialization: {ExecutionLock, ExecutionLock})

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

    assert {:ok, %{status: :completed}} = Storage.fetch_execution(store, execution_id)
  end

  # Sabotage: made the task print none of the lines; this went red.
  # Reverted from a copy.
  test "the mix task prints every line the recipe answers" do
    Mix.shell(Mix.Shell.Process)

    try do
      Mix.Tasks.StatifierExamples.FirstWorkflow.run([])
    after
      Mix.shell(Mix.Shell.IO)
    end

    assert_received {:mix_shell, :info, ["first workflow on " <> _pins]}
    assert_received {:mix_shell, :info, ["ended        completed at " <> _ended_at]}
  end
end
