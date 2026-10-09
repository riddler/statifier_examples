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

  alias Ecto.Adapters.SQL.Sandbox
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
  alias StatifierPersistence.{Execution, Storage}
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
end
