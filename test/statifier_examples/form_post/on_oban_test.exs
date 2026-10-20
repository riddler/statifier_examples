defmodule StatifierExamples.FormPost.OnObanTest do
  @moduledoc """
  The card application recipe end to end on this app's Oban: one stored
  application, the intake job, the three steps' jobs and the deadline
  timers, all run by `StatifierExamples.FormPost.Drain` in order, through
  the real document under `priv/form_post/`.

  Not async: writes to the repo, runs Oban jobs in the test process and
  sets the application environment.
  """
  use ExUnit.Case, async: false
  # The engine and notifier are named because `Oban.Testing` builds its
  # own config, whose defaults are Postgres'; this app's Oban is SQLite's.
  use Oban.Testing,
    repo: StatifierExamples.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts.ExecutionLock
  alias StatifierExamples.{FirstWorkflow, Repo}

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplications,
    CardApplicationSend,
    Delivery,
    Drain,
    PublishedCharts,
    Router,
    ScreenApplication
  }

  alias StatifierOban.Timer.Worker, as: TimerWorker
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.Address

  setup do
    :ok = Sandbox.checkout(Repo)
    {:ok, machine, scxml} = PublishedCharts.runtime_chart()
    :ok = Storage.save_chart(FirstWorkflow.store(), machine, scxml)

    on_exit(fn -> Application.delete_env(:statifier_examples, ScreenApplication) end)

    :ok
  end

  defp store!(street_address) do
    {:ok, %CardApplication{id: id}, :created} =
      CardApplications.receive_application("riverbend", %{
        "name" => "Odile Marsh",
        "email" => "odile.marsh@example.com",
        "phone" => "555-0142",
        "street_address" => street_address,
        "wants_card" => "true",
        "wants_newsletter" => "true",
        "idempotency_key" => "form-#{System.unique_integer([:positive])}"
      })

    id
  end

  defp execution_id(id) do
    key = Integer.to_string(id)

    Repo.one!(
      from(a in Config.queryable(Router.config(), Address),
        where: a.document == ^Router.document_id() and a.key == ^key,
        select: a.execution_id
      )
    )
  end

  # The stored execution and the datamodel of its stored position.
  defp execution(execution_id) do
    store = FirstWorkflow.store()
    {:ok, record} = Storage.fetch_execution(store, execution_id)
    {:ok, machine} = PublishedCharts.chart(record.content_hash)
    {:ok, state} = Storage.load_execution_position(store, execution_id, machine)
    {Execution.from_record(record), Map.take(state.datamodel, ~w(screen sort area))}
  end

  # The deadline timer jobs stored under the execution, by event name.
  defp timers(execution_id) do
    worker = Oban.Worker.to_string(TimerWorker)

    from(j in Oban.Job, where: j.worker == ^worker and j.args["scope"] == ^execution_id)
    |> Repo.all()
    |> Map.new(fn %Oban.Job{args: %{"event" => event}} = job -> {event, job} end)
  end

  # The step jobs stored under the execution, by invoke type.
  defp step_jobs(execution_id) do
    Repo.all(
      from(j in Oban.Job,
        where: j.queue == "statifier_invocations" and j.args["scope"] == ^execution_id,
        order_by: j.id
      )
    )
  end

  defp sends(id) do
    Repo.all(
      from(s in CardApplicationSend,
        where: s.application_id == ^id,
        order_by: s.route,
        select: s.route
      )
    )
  end

  describe "an application that asks for both" do
    # Sabotage: dropped `persistence_options:` from the router's
    # configuration; the screen's `<invoke>` was refused as unsupported,
    # the execution failed, and this went red on `:completed`. Making
    # `Steps.execute/2` answer `:ok` for every `<invoke>` stored no step
    # job and went red the same way. Making it skip `Timer.cancel/3` left
    # both deadlines scheduled and went red on `"cancelled"`. Each
    # reverted from a copy.
    test "runs every step on the app's Oban and reaches both routes" do
      id = store!("12 Millrace Lane")

      assert {:ok, %{success: success, failure: 0, discard: 0}} = Drain.run()
      assert success >= 4

      execution_id = execution_id(id)

      assert {%Execution{status: :completed},
              %{"screen" => "ok", "sort" => "both", "area" => "inside"}} =
               execution(execution_id)

      assert ["newsletter", "patron_system"] == sends(id)
      assert %Config{timer_queue: nil} = Router.config()

      # Each deadline was armed as a timer job and cancelled when its step
      # answered in time; the arrival wait was cancelled by the event.
      assert %{"deadline.screen" => screen, "deadline.area" => area} = timers(execution_id)
      assert %Oban.Job{state: "cancelled", queue: "statifier_timers"} = screen
      assert %Oban.Job{state: "cancelled", queue: "statifier_timers"} = area
    end
  end

  describe "the delivery" do
    # Sabotage: made the answer builder in `Delivery` skip its check that
    # the position still holds the invocation; the stale answer was
    # stepped, and this went red on the discard. Reverted from a copy.
    test "an answer nobody waits for is discarded, and an unrouted execution is not stepped" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("12 Millrace Lane")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)

      assert {:discarded, :active} = Delivery.deliver(execution_id, "inv_stale", "screened_out")
      assert {%Execution{status: :active}, %{"screen" => "unscreened"}} = execution(execution_id)

      assert {:discarded, :no_address} =
               Delivery.deliver("form_post_unrouted", "inv_stale", "ok")
    end

    # Sabotage: made `Delivery` step outside
    # `Scope.around_delivery/3`; the stepper refused with no library
    # system, the answer was discarded, and this went red on `:delivered`.
    # Reverted from a copy.
    test "a step's answer is stepped inside the application's library system" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("12 Millrace Lane")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)

      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)

      assert :delivered = Delivery.deliver(execution_id, invoke_id, "screened_out")

      assert {%Execution{status: :completed}, %{"screen" => "screened_out"}} =
               execution(execution_id)

      assert [] == sends(id)
    end

    # Sabotage: dropped the `{:discarded, %Execution{status: :completed}}`
    # clause of `Delivery`'s `record_outcome/4`; the retry was discarded
    # without the mark and this went red on "screened_out". Making
    # `Writer.record_screened_out/2` write a row already screened out went
    # red on the stamp. Each reverted from a copy.
    test "a mark the step's delivery failed to write is written by the retry, once" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("PO Box 77")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)

      # The write fails after the step has stored the finished execution:
      # the row is moved out of the library system the write is scoped to.
      moved = from(a in CardApplication, where: a.id == ^id)
      {1, _} = Repo.update_all(moved, set: [scope: "elsewhere"])

      assert_raise MatchError, fn ->
        Delivery.deliver(execution_id, invoke_id, "screened_out")
      end

      assert {%Execution{status: :completed}, %{"screen" => "screened_out"}} =
               execution(execution_id)

      {1, _} = Repo.update_all(moved, set: [scope: "riverbend"])
      assert %CardApplication{status: "received"} = Repo.get!(CardApplication, id)

      # The retry is discarded, the execution having finished, and writes
      # the mark the first attempt missed.
      assert {:discarded, :completed} = Delivery.deliver(execution_id, invoke_id, "screened_out")

      assert %CardApplication{status: "screened_out", updated_at: marked} =
               Repo.get!(CardApplication, id)

      # A later retry answers the same discard and keeps the first stamp.
      # (The stamp is microseconds, so a second write would move it.)
      assert {:discarded, :completed} = Delivery.deliver(execution_id, invoke_id, "screened_out")

      assert %CardApplication{status: "screened_out", updated_at: ^marked} =
               Repo.get!(CardApplication, id)
    end

    # Sabotage: made `Delivery`'s read of the finished execution's
    # position answer `:ok` on an error; the retry was discarded with the
    # mark unwritten and this went red on the raise. Reverted from a copy.
    test "a retry that cannot read the finished execution's position raises" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("PO Box 77")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)

      assert :delivered = Delivery.deliver(execution_id, invoke_id, "screened_out")
      :ok = put_position_blob(execution_id, nil)

      assert_raise RuntimeError, ~r/could not be read \(:execution_position_missing\)/, fn ->
        Delivery.deliver(execution_id, invoke_id, "screened_out")
      end
    end
  end

  describe "a screen past its bound" do
    # Sabotage: made `Steps.execute/2` answer `:ok` for a delayed `<send>`
    # instead of storing a timer job; no deadline was stored and this went
    # red on the scheduled timer. Making `Drain.run/1` stop after its first
    # pass left the sort's job unrun and went red on `:completed`. Each
    # reverted from a copy.
    test "the deadline timer is due five seconds on, fires, and the flow goes on" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("12 Millrace Lane")
      armed_at = DateTime.utc_now()

      assert {:ok, %{failure: 1}} = Drain.run()

      execution_id = execution_id(id)
      assert {%Execution{status: :active}, %{"screen" => "unscreened"}} = execution(execution_id)

      assert %{"deadline.screen" => %Oban.Job{state: "scheduled", scheduled_at: due}} =
               timers(execution_id)

      assert DateTime.diff(due, armed_at, :millisecond) in 4_000..6_000

      assert {:ok, %{success: success}} = Drain.run(until: due)
      assert success >= 1

      assert %{"deadline.screen" => %Oban.Job{state: "completed"}} = timers(execution_id)

      assert {%Execution{status: :completed},
              %{"screen" => "unscreened", "sort" => "both", "area" => "inside"}} =
               execution(execution_id)

      assert ["newsletter", "patron_system"] == sends(id)

      # The screen's job, failed and waiting to retry, was cancelled when
      # its bound fired.
      assert [
               %Oban.Job{args: %{"type" => "myapp:screen_application"}, state: "cancelled"},
               %Oban.Job{args: %{"type" => "myapp:sort_application"}, state: "completed"},
               %Oban.Job{args: %{"type" => "myapp:check_service_area"}, state: "completed"}
             ] = step_jobs(execution_id)
    end
  end

  # The execution's first step job, with the intake run and nothing else:
  # the step's job is stored and has not run.
  defp first_step!(street_address) do
    id = store!(street_address)
    assert %{success: 1} = Oban.drain_queue(queue: :card_application_intake)
    execution_id = execution_id(id)
    assert [%Oban.Job{state: "available"}] = step_jobs(execution_id)
    execution_id
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

  describe "a delivery that cannot step now" do
    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # a parked execution; the step's job was cancelled and this went red
    # on `%{failure: 1}`. Reverted from a copy.
    test "an answer to a parked execution raises, is retried, and lands once unparked" do
      execution_id = first_step!("12 Millrace Lane")
      store = FirstWorkflow.store()
      :ok = Storage.update_execution_status(store, execution_id, :needs_migration)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "retryable", attempt: 1}] = step_jobs(execution_id)
      assert {:ok, %{status: :needs_migration}} = Storage.fetch_execution(store, execution_id)

      assert {:ok, %Execution{status: :active}} =
               Executions.unpark(store, execution_id,
                 serialization: {ExecutionLock, ExecutionLock}
               )

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_invocations, with_scheduled: true)

      assert {%Execution{status: :active}, %{"screen" => "ok"}} = execution(execution_id)
    end

    # Sabotage: made `Delivery`'s refusal answer `{:discarded, reason}` for
    # every reason it does not name; the step's job was cancelled and this
    # went red on `%{failure: 1}`. Reverted from a copy.
    test "an answer the store cannot step raises, is retried, and lands once the store answers" do
      execution_id = first_step!("12 Millrace Lane")
      blob = position_blob(execution_id)
      :ok = put_position_blob(execution_id, nil)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "retryable", attempt: 1}] = step_jobs(execution_id)

      :ok = put_position_blob(execution_id, blob)

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_invocations, with_scheduled: true)

      assert {%Execution{status: :active}, %{"screen" => "ok"}} = execution(execution_id)
    end

    # Sabotage: made the timer `deliver/2` rescue the raise and answer
    # `{:discarded, :needs_migration}`; the timer job was cancelled and
    # this went red on `%{failure: 1}`. Reverted from a copy.
    test "a deadline that fires into a parked execution raises, is retried, and lands once unparked" do
      execution_id = first_step!("12 Millrace Lane")
      store = FirstWorkflow.store()
      :ok = Storage.update_execution_status(store, execution_id, :needs_migration)

      assert %{failure: 1, cancelled: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

      assert %{"deadline.screen" => %Oban.Job{state: "retryable", attempt: 1}} =
               timers(execution_id)

      assert {:ok, %Execution{status: :active}} =
               Executions.unpark(store, execution_id,
                 serialization: {ExecutionLock, ExecutionLock}
               )

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(queue: :statifier_timers, with_scheduled: true)

      assert %{"deadline.screen" => %Oban.Job{state: "completed"}} = timers(execution_id)
    end

    # Sabotage: made `Delivery` raise for a step the store discarded; the
    # job's retry failed rather than cancelling and this went red on
    # `%{cancelled: 1}`. Reverted from a copy.
    test "an answer to a finished execution is still discarded" do
      execution_id = first_step!("12 Millrace Lane")
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)

      # The host fails the execution from outside its chart, which leaves
      # the step's job stored, so the job answers a finished execution.
      assert {:ok, %Execution{status: :failed}} =
               Executions.fail(FirstWorkflow.store(), execution_id, "host:gave_up",
                 serialization: {ExecutionLock, ExecutionLock}
               )

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = step_jobs(execution_id)
      assert {:discarded, :failed} = Delivery.deliver_failure(execution_id, invoke_id, [])
    end

    # Sabotage: dropped `:execution_not_found` from the reasons
    # `Delivery` discards; the job failed rather than cancelling and this
    # went red on `%{cancelled: 1}`. Reverted from a copy.
    test "an answer to an execution the store no longer holds is still discarded" do
      execution_id = first_step!("12 Millrace Lane")

      %{num_rows: 1} =
        SQL.query!(Repo, "DELETE FROM statifier_executions WHERE execution_id = ?1", [
          execution_id
        ])

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = step_jobs(execution_id)
    end

    # Sabotage: made `Delivery`'s refusal raise for a step that exhausted
    # the execution's macrostep budget; the job failed rather than
    # cancelling and this went red on `%{cancelled: 1}`. Reverted from a
    # copy.
    test "an answer whose step exhausts the execution's budget is discarded" do
      execution_id = first_step!("12 Millrace Lane")
      store = FirstWorkflow.store()
      {:ok, record} = Storage.fetch_execution(store, execution_id)
      {:ok, machine} = PublishedCharts.chart(record.content_hash)
      {:ok, state} = Storage.load_execution_position(store, execution_id, machine)

      :ok =
        Storage.update_execution(store, execution_id, %{state | max_macrostep_rounds: 1}, :active)

      assert %{cancelled: 1, failure: 0, success: 0} =
               Oban.drain_queue(queue: :statifier_invocations)

      assert [%Oban.Job{state: "cancelled"}] = step_jobs(execution_id)
      assert {:ok, %{status: :failed}} = Storage.fetch_execution(store, execution_id)
    end
  end

  @doc false
  def handle_macrostep(_event, _measurements, metadata, test_pid) do
    send(test_pid, {:macrostep, metadata.event_name, metadata.caller_context})
  end

  describe "the caller's context" do
    setup do
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:statifier, :session, :macrostep, :start],
          &__MODULE__.handle_macrostep/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    # Sabotage: made `deliver/4` build its answer with no
    # `caller_context:`; the answer's macrostep carried `nil` and this
    # went red on the first `assert_received`. Reverted from a copy.
    test "an answer carries the job's caller context onto the step it drives, and onward" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("12 Millrace Lane")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)
      context = {:trace, make_ref()}

      assert :delivered =
               Delivery.deliver(execution_id, invoke_id, "ok", caller_context: context)

      done = "done.invoke." <> invoke_id
      assert_received {:macrostep, ^done, ^context}

      # The step the answer drove planned the next step's job with the
      # same context, and that job's answer carries it in turn.
      assert {:ok, %{failure: 0}} = Drain.run()
      assert {%Execution{status: :completed}, _words} = execution(execution_id)

      [_first, %Oban.Job{args: %{"invoke_id" => next_id}} | _rest] = step_jobs(execution_id)
      next = "done.invoke." <> next_id
      assert_received {:macrostep, ^next, ^context}
    end

    # Sabotage: made `deliver_failure/4` build its answer with no
    # `caller_context:`; the failure's macrostep carried `nil` and this
    # went red. Reverted from a copy.
    test "a failure carries the job's caller context onto the step it drives" do
      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      id = store!("12 Millrace Lane")
      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      [%Oban.Job{args: %{"invoke_id" => invoke_id}}] = step_jobs(execution_id)
      context = {:trace, make_ref()}
      failure = [reason: "run_failed", attempts: 3, detail: "gave up"]

      assert :delivered =
               Delivery.deliver_failure(execution_id, invoke_id, failure, caller_context: context)

      error = "error.communication.invoke." <> invoke_id
      assert_received {:macrostep, ^error, ^context}
    end
  end
end
