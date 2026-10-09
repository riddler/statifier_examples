defmodule StatifierExamples.FormPost.StepsTest do
  @moduledoc """
  The card application's three steps: each is handed the application's id,
  reads the stored row back through the one reader under the library
  system, and answers one word. No field value the visitor typed reaches
  the answer, the job's arguments, the job's errors or the telemetry the
  invoke path emits.
  """

  # Not async: writes to the repo, and the hook tests set application env.
  use StatifierExamplesWeb.ConnCase, async: false
  # The engine and notifier are named because `Oban.Testing` builds its
  # own config, whose defaults are Postgres'; this app's Oban is SQLite's.
  use Oban.Testing,
    repo: StatifierExamples.Repo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias Statifier.Effect.Invoke
  alias StatifierExamples.FormPost.CardApplications.Reader

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplications,
    CheckServiceArea,
    ScreenApplication,
    SortApplication,
    Steps
  }

  alias StatifierExamples.Repo
  alias StatifierOban.Invoke.{Handler, Worker}

  # A delivery module that hands the job's answer back to the test
  # process: `perform_job/3` runs the job in that process.
  defmodule RecordingDelivery do
    @moduledoc false
    @behaviour StatifierOban.Invoke.Delivery

    @impl StatifierOban.Invoke.Delivery
    def deliver(scope, invoke_id, donedata) do
      send(self(), {:delivered, scope, invoke_id, donedata})
      :delivered
    end

    @impl StatifierOban.Invoke.Delivery
    def deliver_failure(scope, invoke_id, failure) do
      send(self(), {:delivered_failure, scope, invoke_id, failure})
      :delivered
    end
  end

  @values ["Juniper Ashby", "juniper.ashby@example.com", "555-0163"]

  setup do
    on_exit(fn ->
      Application.delete_env(:statifier_examples, ScreenApplication)
      Application.delete_env(:statifier_examples, CheckServiceArea)
      Application.delete_env(:statifier_examples, SortApplication)
    end)

    :ok
  end

  defp store!(street_address, scope \\ "riverbend", wants \\ %{}) do
    form =
      Map.merge(
        %{
          "name" => "Juniper Ashby",
          "email" => "juniper.ashby@example.com",
          "phone" => "555-0163",
          "street_address" => street_address,
          "wants_card" => "true",
          "wants_newsletter" => "true",
          "idempotency_key" => "form-#{System.unique_integer([:positive])}"
        },
        wants
      )

    {:ok, %CardApplication{id: id}, :created} = CardApplications.receive_application(scope, form)

    id
  end

  defp invoke(type, params) do
    %Invoke{
      type: type,
      params: params,
      invoke_id: "inv_#{System.unique_integer([:positive])}",
      state_index: 0,
      invoke_index: 0,
      macrostep: 1,
      microstep: 1,
      round: 0
    }
  end

  defp screen(id), do: ScreenApplication.run(invoke("myapp:screen_application", app(id)))
  defp area(id), do: CheckServiceArea.run(invoke("myapp:check_service_area", app(id)))
  defp sort(id), do: SortApplication.run(invoke("myapp:sort_application", app(id)))
  defp app(id), do: %{"application_id" => id}

  # Every field value the fixture posts, the street address included,
  # checked against the inspected term.
  defp refute_values(term, street_address) do
    text = inspect(term, limit: :infinity, printable_limit: :infinity)

    for value <- [street_address | @values] do
      refute text =~ value, "#{inspect(value)} reached #{text}"
    end
  end

  describe "the reader" do
    # Sabotage: dropped the `a.scope == ^scope` filter from `Reader.fetch/2`;
    # this went red on the other library system's `:not_found`. Reverted.
    test "reads an application under its own library system only" do
      id = store!("12 Millrace Lane")

      assert {:ok, %CardApplication{id: ^id, name: "Juniper Ashby"}} =
               Reader.fetch("riverbend", id)

      assert {:error, :not_found} = Reader.fetch("eastbank", id)
      assert {:error, :not_found} = Reader.fetch("riverbend", id + 1_000)
    end

    # Sabotage: made `Steps.library_system/0` answer "eastbank"; this went
    # red on the stored row's scope. Reverted.
    test "the steps read under the library system the form's controller stores under", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/form-post/card-applications", %{
          "card_application" => %{
            "name" => "Juniper Ashby",
            "email" => "juniper.ashby@example.com",
            "street_address" => "12 Millrace Lane",
            "wants_card" => "true",
            "idempotency_key" => "form-e5a1"
          }
        })

      assert %{"application_id" => id} = json_response(conn, 202)
      assert %CardApplication{scope: scope} = Repo.get!(CardApplication, id)
      assert scope == Steps.library_system()
    end
  end

  describe "myapp:screen_application" do
    # Sabotage: made the screen answer "ok" for every address; this went
    # red on the post office box's "screened_out". Reverted.
    test "answers ok for a home address and screened_out for a post office box" do
      assert {:ok, "ok"} = screen(store!("12 Millrace Lane"))
      assert {:ok, "ok"} = screen(store!("7 Boxwood Close"))
      assert {:ok, "screened_out"} = screen(store!("PO Box 14"))
      assert {:ok, "screened_out"} = screen(store!("P.O. Box 902"))
      assert {:ok, "screened_out"} = screen(store!("p o box 3, Ferry Street"))
    end
  end

  describe "myapp:check_service_area" do
    # Sabotage: made the area check answer "inside" for every address;
    # this went red on the first "outside". Reverted.
    test "answers inside for a Riverbend street and outside for any other" do
      assert {:ok, "inside"} = area(store!("12 Millrace Lane"))
      assert {:ok, "inside"} = area(store!("  40 WILLOW BEND ROAD "))
      assert {:ok, "outside"} = area(store!("8 Quarry Road"))
      assert {:ok, "outside"} = area(store!("3 Ferry Street Extension"))
    end
  end

  describe "myapp:sort_application" do
    # Sabotage: made the sort answer "card" for a row that wants both;
    # this went red on "both". Reverted from a copy.
    test "answers both for an application that asked for a card and the newsletter" do
      assert {:ok, "both"} = sort(store!("12 Millrace Lane"))
    end

    # Sabotage: made the sort read `wants_newsletter` for the card; this
    # went red on "card". Reverted from a copy.
    test "answers card for an application that asked for a card only" do
      id = store!("12 Millrace Lane", "riverbend", %{"wants_newsletter" => "false"})
      assert {:ok, "card"} = sort(id)
    end

    # Sabotage: dropped the newsletter clause from the sort, so a
    # newsletter-only row fell through to "neither"; this went red on
    # "newsletter". Reverted from a copy.
    test "answers newsletter for an application that asked for the newsletter only" do
      id = store!("12 Millrace Lane", "riverbend", %{"wants_card" => "false"})
      assert {:ok, "newsletter"} = sort(id)
    end

    # The form refuses an application that asks for neither, so the row is
    # stored past it: the sort answers for what is stored.
    #
    # Sabotage: made the sort's last clause answer "newsletter"; this went
    # red on "neither". Reverted from a copy.
    test "answers neither for a stored row that asked for neither" do
      %CardApplication{id: id} =
        Repo.insert!(%CardApplication{
          scope: "riverbend",
          name: "Juniper Ashby",
          email: "juniper.ashby@example.com",
          street_address: "12 Millrace Lane",
          wants_card: false,
          wants_newsletter: false,
          idempotency_key: "form-#{System.unique_integer([:positive])}"
        })

      assert {:ok, "neither"} = sort(id)
    end
  end

  describe "what a step is handed" do
    # Sabotage: made `Steps.application_id/1` take the id out of params of
    # any size; this went red on the extra param's refusal. Reverted.
    test "params beyond the id are refused, and the refusal names keys only" do
      id = store!("12 Millrace Lane")

      for handler <- [ScreenApplication, SortApplication, CheckServiceArea] do
        params = %{"application_id" => id, "name" => "Juniper Ashby"}

        assert {:error, {:params_not_an_application_id, ["application_id", "name"]} = reason} =
                 handler.run(invoke(handler.invoke_type(), params))

        refute_values(reason, "12 Millrace Lane")

        assert {:error, {:params_not_an_application_id, ["application_id"]}} =
                 handler.run(invoke(handler.invoke_type(), %{"application_id" => "#{id}"}))
      end
    end

    # Sabotage: made the screen read with `Repo.get/2`, by id alone; this
    # went red on the other library system's not-found. Reverted.
    test "an id another library system stored, or no application, is not found" do
      other = store!("12 Millrace Lane", "eastbank")

      assert {:error, {:application_not_found, ^other}} = screen(other)
      assert {:error, {:application_not_found, ^other}} = area(other)
      assert {:error, {:application_not_found, ^other}} = sort(other)
      assert {:error, {:application_not_found, 0}} = screen(0)
    end
  end

  describe "the delay and failure hook" do
    # Sabotage: made `Steps.hooked/2` ignore `:fail`; this went red on the
    # failure hook's error. Reverted.
    test "fail makes each step answer an error" do
      id = store!("12 Millrace Lane")

      Application.put_env(:statifier_examples, ScreenApplication, fail: true)
      assert {:error, :failure_hook} = screen(id)
      assert {:ok, "inside"} = area(id)

      Application.put_env(:statifier_examples, CheckServiceArea, fail: true)
      assert {:error, :failure_hook} = area(id)
    end

    # Sabotage: made `Steps.hooked/2` ignore `:delay_ms`; this went red on
    # the elapsed time. Reverted.
    test "delay_ms makes a step take at least that long" do
      id = store!("12 Millrace Lane")

      Application.put_env(:statifier_examples, ScreenApplication, delay_ms: 120)
      {elapsed_us, {:ok, "ok"}} = :timer.tc(fn -> screen(id) end)
      assert elapsed_us >= 120_000

      {elapsed_us, {:ok, "inside"}} = :timer.tc(fn -> area(id) end)
      assert elapsed_us < 120_000
    end
  end

  describe "through the invoke job" do
    setup do
      ref = make_ref()
      events = [:enqueued, :delivered, :failed, :enqueue_rejected]

      :telemetry.attach_many(
        "#{inspect(ref)}",
        Enum.map(events, &[:statifier_oban, :invoke, &1]),
        fn event, measurements, metadata, test_pid ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        self()
      )

      on_exit(fn -> :telemetry.detach("#{inspect(ref)}") end)

      :ok
    end

    defp ctx, do: %{session_id: "exec_card_#{System.unique_integer([:positive])}"}

    defp enqueue!(handler, id) do
      invoke = invoke(handler.invoke_type(), app(id))
      :ok = Handler.perform_start(handler, invoke, ctx())
      assert [%Oban.Job{} = job] = all_enqueued(worker: Worker)
      {invoke, job}
    end

    defp run_job(%Oban.Job{args: args}, opts \\ []) do
      perform_job(
        Worker,
        args,
        [meta: %{"delivery" => Atom.to_string(RecordingDelivery)}] ++ opts
      )
    end

    # Sabotage: made the screen answer `%{"word" => "ok", "street_address"
    # => street_address}`; this went red on the delivered answer's match.
    # Reverted.
    test "each step's answer is the word, and no value is on the job or its telemetry" do
      for {handler, street_address, word} <- [
            {ScreenApplication, "12 Millrace Lane", "ok"},
            {ScreenApplication, "PO Box 14", "screened_out"},
            {CheckServiceArea, "12 Millrace Lane", "inside"},
            {CheckServiceArea, "8 Quarry Road", "outside"},
            {SortApplication, "12 Millrace Lane", "both"}
          ] do
        id = store!(street_address)
        {invoke, job} = enqueue!(handler, id)
        invoke_id = invoke.invoke_id

        refute_values(job.args, street_address)
        refute_values(job.meta, street_address)

        assert :ok = run_job(job)
        assert_received {:delivered, _scope, ^invoke_id, ^word}

        assert_received {:telemetry, [:statifier_oban, :invoke, :enqueued], _, enqueued}
        assert_received {:telemetry, [:statifier_oban, :invoke, :delivered], _, delivered}
        refute_values({enqueued, delivered}, street_address)

        Repo.delete_all(Oban.Job)
      end
    end

    # Sabotage: made the area check's hooked failure carry the stored
    # street address; this went red on the terminal failure's detail.
    # Reverted.
    test "a step that fails for good fails with no value in its error or telemetry" do
      id = store!("12 Millrace Lane")
      Application.put_env(:statifier_examples, CheckServiceArea, fail: true)
      {invoke, job} = enqueue!(CheckServiceArea, id)
      invoke_id = invoke.invoke_id

      result = run_job(job, attempt: 20, max_attempts: 20)

      assert_received {:delivered_failure, _scope, ^invoke_id, failure}
      refute_values(failure, "12 Millrace Lane")
      assert_received {:telemetry, [:statifier_oban, :invoke, :failed], _, failed}
      refute_values(failed, "12 Millrace Lane")
      refute_values(result, "12 Millrace Lane")

      assert {:error, {:run_failed, :failure_hook}} = result
      assert failure[:reason] == "run_failed"
      assert failure[:detail] =~ "failure_hook"
    end
  end
end
