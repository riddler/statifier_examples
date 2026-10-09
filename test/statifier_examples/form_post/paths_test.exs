defmodule StatifierExamples.FormPost.PathsTest do
  @moduledoc """
  The card application recipe's paths end to end, each from the form's
  `POST /form-post/card-applications`: the controller stores the post,
  `StatifierExamples.FormPost.Drain` runs the intake job, the steps' jobs
  and the deadline timers in order, the document decides, and the routes
  write the outbox.

  A step is made slow or failing with the delay and failure hook
  (`StatifierExamples.FormPost.Steps.hooked/2`), never with a real sleep,
  and a step's job is made to fail for good by setting its own
  `max_attempts` to 1 before it runs.

  Not async: writes to the repo, runs Oban jobs in the test process and
  sets the application environment.
  """
  use StatifierExamplesWeb.ConnCase, async: false
  # The engine and notifier are named because `Oban.Testing` builds its
  # own config, whose defaults are Postgres'; this app's Oban is SQLite's.
  use Oban.Testing,
    repo: StatifierExamples.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.{FirstWorkflow, Repo}

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplicationSend,
    CheckServiceArea,
    Delivery,
    Drain,
    IntakeJob,
    PublishedCharts,
    PurgeJob,
    Router,
    ScreenApplication,
    SortApplication
  }

  alias StatifierOban.Timer.Worker, as: TimerWorker
  alias StatifierPersistence.{Execution, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.{Address, Ledger}

  @steps [ScreenApplication, SortApplication, CheckServiceArea]

  @form %{
    "name" => "Tamsin Rook",
    "email" => "tamsin.rook@example.com",
    "phone" => "555-0163",
    "street_address" => "12 Millrace Lane",
    "wants_card" => "true",
    "wants_newsletter" => "true"
  }

  setup do
    {:ok, machine, scxml} = PublishedCharts.runtime_chart()
    :ok = Storage.save_chart(FirstWorkflow.store(), machine, scxml)

    on_exit(fn ->
      for step <- @steps, do: Application.delete_env(:statifier_examples, step)
    end)

    :ok
  end

  # Posts the form as a browser would and answers the stored id.
  defp post_form!(conn, form \\ %{}) do
    body = %{
      "card_application" =>
        @form
        |> Map.merge(form)
        |> Map.put_new("idempotency_key", "form-#{System.unique_integer([:positive])}")
    }

    conn = post(conn, ~p"/form-post/card-applications", body)
    assert %{"application_id" => id} = json_response(conn, 202)
    id
  end

  defp execution_ids(id) do
    key = Integer.to_string(id)

    Repo.all(
      from(a in Config.queryable(Router.config(), Address),
        where: a.document == ^Router.document_id() and a.key == ^key,
        select: a.execution_id
      )
    )
  end

  defp execution_id(id) do
    [execution_id] = execution_ids(id)
    execution_id
  end

  # The stored execution and the words of its stored position.
  defp execution(execution_id) do
    store = FirstWorkflow.store()
    {:ok, record} = Storage.fetch_execution(store, execution_id)
    {:ok, machine} = PublishedCharts.chart(record.content_hash)
    {:ok, state} = Storage.load_execution_position(store, execution_id, machine)
    {Execution.from_record(record), Map.take(state.datamodel, ~w(screen sort area))}
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

  defp status(id), do: Repo.get!(CardApplication, id).status

  # The step jobs stored under the execution, in the order they were stored.
  defp step_jobs(execution_id) do
    Repo.all(
      from(j in Oban.Job,
        where: j.queue == "statifier_invocations" and j.args["scope"] == ^execution_id,
        order_by: j.id
      )
    )
  end

  defp step_job(execution_id, type) do
    Enum.find(step_jobs(execution_id), &match?(%Oban.Job{args: %{"type" => ^type}}, &1))
  end

  defp deadline(execution_id, event) do
    worker = Oban.Worker.to_string(TimerWorker)

    Repo.one(
      from(j in Oban.Job,
        where:
          j.worker == ^worker and j.args["scope"] == ^execution_id and
            j.args["event"] == ^event
      )
    )
  end

  # Makes a stored step job's next attempt its last, so a failure is final.
  defp last_attempt!(%Oban.Job{id: job_id}) do
    {1, _} = Repo.update_all(from(j in Oban.Job, where: j.id == ^job_id), set: [max_attempts: 1])
    :ok
  end

  defp ledger(id) do
    key = Integer.to_string(id)

    Repo.all(
      from(l in Config.queryable(Router.config(), Ledger),
        where: l.binding_id == ^Router.binding_id() and l.key == ^key,
        order_by: l.id,
        select: l.outcome
      )
    )
  end

  defp fail(step), do: Application.put_env(:statifier_examples, step, fail: true)

  describe "the screen past its bound" do
    # Sabotage: made `Steps.execute/2` answer `:ok` for a delayed `<send>`
    # instead of storing a timer job; no deadline was stored and this went
    # red on the scheduled deadline. Reverted from a copy.
    test "the flow goes on unscreened and both lanes still run", %{conn: conn} do
      fail(ScreenApplication)
      id = post_form!(conn)

      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      assert {%Execution{status: :active}, %{"screen" => "unscreened"}} = execution(execution_id)

      assert %Oban.Job{state: "scheduled", scheduled_at: due} =
               deadline(execution_id, "deadline.screen")

      assert {:ok, _counts} = Drain.run(until: due)

      assert {%Execution{status: :completed},
              %{"screen" => "unscreened", "sort" => "both", "area" => "inside"}} =
               execution(execution_id)

      assert ["newsletter", "patron_system"] == sends(id)
      assert "sent" == status(id)
    end
  end

  describe "both checkboxes" do
    # Sabotage: made `NewsletterRoute.deliver/3` answer `:ok` without
    # recording the hand-off; this went red on the two outbox rows.
    # Reverted from a copy.
    test "two outbox rows, one per route, and the application sent", %{conn: conn} do
      id = post_form!(conn)

      assert {:ok, %{failure: 0, discard: 0}} = Drain.run()

      assert {%Execution{status: :completed},
              %{"screen" => "ok", "sort" => "both", "area" => "inside"}} =
               execution(execution_id(id))

      assert ["newsletter", "patron_system"] == sends(id)

      assert %CardApplication{
               status: "sent",
               external_reference: "RPL-P-" <> _,
               newsletter_reference: "RPL-N-" <> _
             } = Repo.get!(CardApplication, id)
    end
  end

  describe "a screened-out application" do
    # Sabotage: dropped the screened-out write from `Delivery`'s step; the
    # row stayed "received" and this went red on the status. Making
    # `Writer.record_screened_out/2` leave `updated_at` alone went red on
    # the first purge, the age measured from the post. Each reverted from a
    # copy.
    test "no outbox row, the execution abandoned, the row screened out and later purged",
         %{conn: conn} do
      id = post_form!(conn, %{"street_address" => "PO Box 77"})

      # The post is dated long ago, so only the outcome's own stamp keeps
      # the row inside the screened-out age below.
      {1, _} =
        Repo.update_all(from(a in CardApplication, where: a.id == ^id),
          set: [updated_at: DateTime.add(DateTime.utc_now(), -400 * 86_400, :second)]
        )

      assert {:ok, %{failure: 0, discard: 0}} = Drain.run()
      execution_id = execution_id(id)

      # The application group was abandoned at the screen: the execution
      # finished with the sort never asked and no send made.
      assert {%Execution{status: :completed}, %{"screen" => "screened_out", "sort" => "unsorted"}} =
               execution(execution_id)

      assert [%Oban.Job{args: %{"type" => "myapp:screen_application"}}] =
               step_jobs(execution_id)

      assert [] == sends(id)
      assert "screened_out" == status(id)

      # The host's retention clears the row's personal fields past the
      # screened-out age, measured from the outcome, and not before.
      days =
        :statifier_examples
        |> Application.fetch_env!(PurgeJob)
        |> Keyword.fetch!(:screened_out_after_days)

      now = DateTime.utc_now()

      assert {:ok, %{"riverbend" => %{"screened_out" => 0}}} =
               PurgeJob.purge(DateTime.add(now, (days - 1) * 86_400, :second))

      assert %CardApplication{email: "tamsin.rook@example.com"} = Repo.get!(CardApplication, id)

      assert {:ok, %{"riverbend" => %{"screened_out" => 1}}} =
               PurgeJob.purge(DateTime.add(now, (days + 1) * 86_400, :second))

      assert %CardApplication{name: "", email: "", phone: nil, street_address: ""} =
               Repo.get!(CardApplication, id)
    end
  end

  describe "the same post twice" do
    # Sabotage: made `IntakeJob.request/2` add a fresh suffix to the
    # provider id; the second run was a new message, delivered to the same
    # execution, and this went red on the duplicate. Reverted from a copy.
    test "one row, one execution, one duplicate from the router", %{conn: conn} do
      form = %{"idempotency_key" => "form-twice"}

      # The controller's layer: the repeat key answers the first row and
      # stores no second row and no second intake job.
      id = post_form!(conn, form)
      assert ^id = post_form!(build_conn(), form)
      assert 1 == Repo.aggregate(CardApplication, :count)
      assert [%Oban.Job{}] = all_enqueued(worker: IntakeJob)

      assert {:ok, %{failure: 0, discard: 0}} = Drain.run()

      # The router's layer: the intake job's routing run a second time for
      # the same application, as an at-least-once queue may run it, is the
      # same message.
      assert {:ok, [{:duplicate, "card_applications"}]} = IntakeJob.route(id)

      assert ["created_and_delivered", "duplicate"] == ledger(id)
      assert [execution_id] = execution_ids(id)
      assert {%Execution{status: :completed}, _words} = execution(execution_id)
      assert ["newsletter", "patron_system"] == sends(id)
    end
  end

  describe "a step that fails for good" do
    # Sabotage: made `Delivery.deliver_failure/3` hand the failure back as
    # a done answer; the flow went on past the sort and this went red on
    # `:failed`. Reverted from a copy.
    test "a sort that fails for good ends the execution failed, with no send", %{conn: conn} do
      fail(SortApplication)
      id = post_form!(conn)

      # The intake job and the screen run; the sort's job is stored next.
      Oban.drain_queue(queue: :card_application_intake)
      Oban.drain_queue(queue: :statifier_invocations)
      execution_id = execution_id(id)
      :ok = last_attempt!(step_job(execution_id, "myapp:sort_application"))

      assert {:ok, %{discard: 1}} = Drain.run()

      assert {%Execution{status: :failed}, %{"screen" => "ok", "sort" => "unsorted"}} =
               execution(execution_id)

      assert [] == sends(id)
      assert "received" == status(id)
    end

    # Sabotage: made `Steps.execute/2` answer `:ok` for a `<cancel>`
    # instead of cancelling the timer; the screen's deadline stayed
    # scheduled and this went red on its cancelled state. Reverted from a
    # copy.
    test "a screen that fails for good before its bound ends the execution failed, with no send",
         %{conn: conn} do
      fail(ScreenApplication)
      id = post_form!(conn)

      Oban.drain_queue(queue: :card_application_intake)
      execution_id = execution_id(id)
      :ok = last_attempt!(step_job(execution_id, "myapp:screen_application"))

      assert {:ok, %{discard: 1}} = Drain.run()

      assert {%Execution{status: :failed}, %{"screen" => "unscreened"}} = execution(execution_id)
      assert %Oban.Job{state: "cancelled"} = deadline(execution_id, "deadline.screen")
      assert [%Oban.Job{}] = step_jobs(execution_id)
      assert [] == sends(id)
    end
  end

  describe "an answer after its bound" do
    # Sabotage: made the answer builder in `Delivery` skip its check that
    # the position still holds the invocation; the late answer was
    # stepped and this went red on the discard. Reverted from a copy.
    test "a screen answer arriving after the bound fired changes nothing", %{conn: conn} do
      fail(ScreenApplication)
      fail(CheckServiceArea)
      id = post_form!(conn)

      assert {:ok, %{failure: 1}} = Drain.run()
      execution_id = execution_id(id)
      screen = step_job(execution_id, "myapp:screen_application")

      # The screen's bound fires; the flow goes on, sends to the
      # newsletter list, and waits on the area check in the card lane.
      assert %Oban.Job{scheduled_at: screen_due} = deadline(execution_id, "deadline.screen")
      assert {:ok, _counts} = Drain.run(until: screen_due)
      assert %Oban.Job{state: "cancelled"} = Repo.reload!(screen)
      assert ["newsletter"] == sends(id)

      # The screen's answer, arriving now, is one nobody waits for.
      assert {:discarded, :active} =
               Delivery.deliver(execution_id, screen.args["invoke_id"], "screened_out")

      assert {%Execution{status: :active}, %{"screen" => "unscreened", "sort" => "both"}} =
               execution(execution_id)

      assert "sent" == status(id)

      # The area's bound fires and the card lane finishes as before.
      assert %Oban.Job{scheduled_at: area_due} = deadline(execution_id, "deadline.area")
      assert {:ok, _counts} = Drain.run(until: area_due)

      assert {%Execution{status: :completed},
              %{"screen" => "unscreened", "sort" => "both", "area" => "check_at_desk"}} =
               execution(execution_id)

      assert ["newsletter", "patron_system"] == sends(id)
      assert "sent" == status(id)
    end
  end
end
