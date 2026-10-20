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

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL
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
             "first workflow on statifier 2.13." <> _pins,
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

  describe "an answer that cannot step now" do
    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # a parked execution; the set-aside job was cancelled and this went red
    # on `%{failure: 1}`. Reverted from a copy.
    test "an answer to a parked execution raises, is retried, and lands once unparked" do
      {store, execution_id} = opened!("first_workflow_parked_answer")
      :ok = Storage.update_execution_status(store, execution_id, :needs_migration)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "retryable", attempt: 1, errors: [%{"error" => error}]}] =
               set_aside_jobs(execution_id)

      assert error =~ "is parked (:needs_migration)"
      assert {:ok, %{status: :needs_migration}} = Storage.fetch_execution(store, execution_id)

      assert {:ok, %Execution{status: :active}} =
               Executions.unpark(store, execution_id,
                 serialization: {ExecutionLock, ExecutionLock}
               )

      # The retry runs the set-aside call again and its answer lands: the
      # wait it enters arms the pickup window, whose firing ends the hold.
      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_invocations, with_scheduled: true)

      assert [%Oban.Job{state: "completed", attempt: 2}] = set_aside_jobs(execution_id)
      assert %{"shelved" => %{"copy" => "c-3107"}} = datamodel(store, execution_id)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

      assert {:ok, %{status: :completed}} = Storage.fetch_execution(store, execution_id)
    end

    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # every reason it does not name; the set-aside job was cancelled and
    # this went red on `%{failure: 1}`. Reverted from a copy.
    test "an answer the store cannot step raises, is retried, and lands once the store answers" do
      {store, execution_id} = opened!("first_workflow_unreadable_answer")
      blob = position_blob(execution_id)
      :ok = put_position_blob(execution_id, nil)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "retryable", attempt: 1}] = set_aside_jobs(execution_id)

      :ok = put_position_blob(execution_id, blob)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_invocations, with_scheduled: true)

      assert %{"shelved" => %{"copy" => "c-3107"}} = datamodel(store, execution_id)
    end

    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # a parked execution; this went red on the raise. Reverted from a copy.
    test "a failure delivered to a parked execution raises" do
      {store, execution_id} = opened!("first_workflow_parked_failure")
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = set_aside_jobs(execution_id)
      :ok = Storage.update_execution_status(store, execution_id, :needs_migration)

      assert_raise RuntimeError, ~r/is parked \(:needs_migration\)/, fn ->
        Delivery.deliver_failure(execution_id, invoke_id, reason: "run_failed", attempts: 3)
      end

      assert {:ok, %{status: :needs_migration}} = Storage.fetch_execution(store, execution_id)
    end

    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # every reason it does not name, as the timer door did before; the
    # timer job was cancelled and this went red on `%{failure: 1}`.
    # Reverted from a copy.
    test "a pickup window the store cannot step raises, is retried, and ends the hold once it answers" do
      {store, execution_id} = opened!("first_workflow_unreadable_timer")
      assert %{success: 1} = Oban.drain_queue(queue: :statifier_invocations)
      blob = position_blob(execution_id)
      :ok = put_position_blob(execution_id, nil)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

      :ok = put_position_blob(execution_id, blob)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

      assert {:ok, %{status: :completed}} = Storage.fetch_execution(store, execution_id)
    end
  end

  describe "an answer that is still discarded" do
    # Sabotage: made `drive/2` raise for an event the driver discarded;
    # the job failed rather than cancelling and this went red on
    # `%{cancelled: 1}`. Reverted from a copy.
    test "an answer to a finished execution" do
      {store, execution_id} = opened!("first_workflow_failed_answer")
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = set_aside_jobs(execution_id)

      # The host fails the execution from outside its chart, which leaves
      # the set-aside job stored, so the job answers a finished execution.
      assert {:ok, %Execution{status: :failed}} =
               Executions.fail(store, execution_id, "host:gave_up",
                 serialization: {ExecutionLock, ExecutionLock}
               )

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = set_aside_jobs(execution_id)
      assert {:discarded, :failed} = Delivery.deliver_failure(execution_id, invoke_id, [])
    end

    # Sabotage: dropped `:execution_not_found` from the reasons `Delivery`
    # discards; the job failed rather than cancelling and this went red on
    # `%{cancelled: 1}`. Reverted from a copy.
    test "an answer to an execution the store no longer holds" do
      {_store, execution_id} = opened!("first_workflow_deleted_answer")

      %{num_rows: 1} =
        SQL.query!(Repo, "DELETE FROM statifier_executions WHERE execution_id = ?1", [
          execution_id
        ])

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = set_aside_jobs(execution_id)
    end

    # Sabotage: made `drive/2` answer `:delivered` for an event the driver
    # discarded; this went red on the second answer. Reverted from a copy.
    test "an answer the position no longer waits for" do
      {_store, execution_id} = opened!("first_workflow_answered_twice")
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = set_aside_jobs(execution_id)

      assert %{success: 1} = Oban.drain_queue(queue: :statifier_invocations)

      assert {:discarded, :active} = Delivery.deliver(execution_id, invoke_id, %{})
    end

    # Sabotage: made `Delivery`'s refusal raise for a step that exhausted
    # the execution's macrostep budget; the job failed rather than
    # cancelling and this went red on `%{cancelled: 1}`. Reverted from a
    # copy.
    test "an answer whose step exhausts the execution's budget" do
      {store, execution_id} = opened!("first_workflow_budget_answer")
      {:ok, machine} = FirstWorkflow.machine_for(store, execution_id)
      {:ok, state} = Storage.load_execution_position(store, execution_id, machine)

      :ok =
        Storage.update_execution(store, execution_id, %{state | max_macrostep_rounds: 1}, :active)

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = set_aside_jobs(execution_id)
      assert {:ok, %{status: :failed}} = Storage.fetch_execution(store, execution_id)
    end
  end

  # A second execution opened on the recipe's chart, resting on its
  # set-aside call, as the parked-timer test above opens one.
  defp opened!(execution_id) do
    assert {:ok, _lines} = FirstWorkflow.run(execution_id: execution_id <> "_registers")

    store = FirstWorkflow.store()
    {:ok, machine} = FirstWorkflow.machine_for(store, execution_id <> "_registers")
    hold = %{"patron" => "p-1043", "copy" => "c-3107", "branch" => "Northside branch"}

    assert {:ok, %Execution{status: :active}, _machine_state} =
             store
             |> FirstWorkflow.driver(machine)
             |> Driver.create(execution_id, initialize: [datamodel: %{"hold" => hold}])

    assert [%Oban.Job{state: "available"}] = set_aside_jobs(execution_id)
    {store, execution_id}
  end

  defp set_aside_jobs(execution_id) do
    Repo.all(
      from(j in Oban.Job,
        where: j.queue == "statifier_invocations" and j.args["scope"] == ^execution_id,
        order_by: j.id
      )
    )
  end

  defp datamodel(store, execution_id) do
    {:ok, machine} = FirstWorkflow.machine_for(store, execution_id)
    {:ok, state} = Storage.load_execution_position(store, execution_id, machine)
    state.datamodel
  end

  defp position_blob(execution_id) do
    %{rows: [[blob]]} =
      SQL.query!(
        Repo,
        "SELECT position_blob FROM statifier_executions WHERE execution_id = ?1",
        [execution_id]
      )

    blob
  end

  defp put_position_blob(execution_id, blob) do
    %{num_rows: 1} =
      SQL.query!(
        Repo,
        "UPDATE statifier_executions SET position_blob = ?1 WHERE execution_id = ?2",
        [blob, execution_id]
      )

    :ok
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
