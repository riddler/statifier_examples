defmodule StatifierExamples.FormPost.IntakeJobTest do
  @moduledoc """
  The card application intake job: it hands a stored application's id to
  `statifier_router`'s webhook front under the form's router
  configuration, inside the library system the application was stored
  under, and nothing the visitor typed reaches the router.

  The card application document is another change's; these tests route to
  a stand-in of the same id, `test/fixtures/form_post/card_application_stand_in.json`,
  named through `StatifierExamples.FormPost.PublishedCharts`' test knob.

  Not async: writes to the repo, steps through the application's named
  serialization strategy and sets the application environment.
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
    IntakeJob,
    PublishedCharts,
    Router,
    Scope,
    Stepper
  }

  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.{Address, Dedupe, Ledger}

  @stand_in Path.expand("../../fixtures/form_post/card_application_stand_in.json", __DIR__)

  @values ["Linnea Brook", "linnea.brook@example.com", "555-0177", "41 Weir Street"]

  setup do
    :ok = Sandbox.checkout(Repo)

    previous = Application.get_env(:statifier_examples, PublishedCharts)
    Application.put_env(:statifier_examples, PublishedCharts, document: @stand_in)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:statifier_examples, PublishedCharts)
        env -> Application.put_env(:statifier_examples, PublishedCharts, env)
      end
    end)

    :ok
  end

  defp register! do
    {:ok, machine, scxml} = PublishedCharts.runtime_chart()
    :ok = Storage.save_chart(FirstWorkflow.store(), machine, scxml)
  end

  defp store!(scope \\ "riverbend") do
    [name, email, phone, street] = @values

    {:ok, %CardApplication{id: id}, :created} =
      CardApplications.receive_application(scope, %{
        "name" => name,
        "email" => email,
        "phone" => phone,
        "street_address" => street,
        "wants_card" => "true",
        "wants_newsletter" => "true",
        "idempotency_key" => "form-#{System.unique_integer([:positive])}"
      })

    id
  end

  defp addresses(id) do
    key = Integer.to_string(id)

    Repo.all(
      from(a in Config.queryable(Router.config(), Address),
        where: a.document == ^Router.document_id() and a.key == ^key
      )
    )
  end

  defp ledger(id) do
    key = Integer.to_string(id)

    Repo.all(
      from(l in Config.queryable(Router.config(), Ledger),
        where: l.binding_id == ^Router.binding_id() and l.key == ^key,
        order_by: l.id
      )
    )
  end

  defp dedupe(id) do
    message_id = Integer.to_string(id)

    Repo.all(
      from(d in Config.queryable(Router.config(), Dedupe),
        where: d.binding_id == ^Router.binding_id() and d.message_id == ^message_id
      )
    )
  end

  defp execution(execution_id) do
    {:ok, record} = Storage.fetch_execution(FirstWorkflow.store(), execution_id)
    Execution.from_record(record)
  end

  # Every column of every row, as one string, for the ids-only check.
  defp dumped(rows), do: inspect(rows, limit: :infinity, printable_limit: :infinity)

  describe "one stored application" do
    # Sabotage: made `IntakeJob.request/2` hand the router the scope
    # "elsewhere" instead of the row's; the address was written under that
    # scope and this went red on the address's scope. Reverted from a copy.
    test "routes to one execution, created and delivered under its library system" do
      register!()
      id = store!()

      assert :ok = perform_job(IntakeJob, %{"application_id" => id})

      assert [%Address{scope: "riverbend", execution_id: execution_id}] = addresses(id)
      assert %Execution{status: :active} = execution(execution_id)
      assert [%Ledger{outcome: "created_and_delivered"}] = ledger(id)

      assert {:ok,
              [%{door: "step", event: %Statifier.Event{name: "application.received"} = event}]} =
               Executions.inputs(FirstWorkflow.store(), execution_id)

      assert event.data == %{"application_id" => id}
    end

    # Sabotage: made `IntakeJob.request/2` add a fresh suffix to the
    # provider id; the second routing was a new message, delivered to the
    # same execution, and this went red on the duplicate. Setting the binding's
    # `create:` to `:always_new` went red on the address row. Each reverted
    # from a copy.
    test "routed twice is a duplicate the second time, and no second execution" do
      register!()
      id = store!()

      assert {:ok, [{:created_and_delivered, "card_applications", execution_id}]} =
               IntakeJob.route(id)

      assert {:ok, [{:duplicate, "card_applications"}]} = IntakeJob.route(id)
      assert :ok = perform_job(IntakeJob, %{"application_id" => id})

      assert [%Address{execution_id: ^execution_id}] = addresses(id)
      assert {:ok, [_one_input]} = Executions.inputs(FirstWorkflow.store(), execution_id)

      assert ["created_and_delivered", "duplicate", "duplicate"] ==
               Enum.map(ledger(id), & &1.outcome)
    end

    # Sabotage: made `IntakeJob.request/2` put the posted email address in
    # the event's data beside the id (read back through the reader); this
    # went red on the request's data. Reverted from a copy.
    test "the job's arguments, the request and every router row carry the id and no value" do
      register!()
      id = store!()

      assert [%Oban.Job{args: %{"application_id" => ^id} = args}] =
               all_enqueued(worker: IntakeJob)

      assert map_size(args) == 1

      assert %{
               scope: "riverbend",
               source: "card_application_form",
               provider_id: provider_id,
               raw_body: provider_id,
               data: %{"application_id" => ^id} = data
             } = request = IntakeJob.request("riverbend", id)

      assert provider_id == Integer.to_string(id)
      assert map_size(data) == 1
      assert map_size(request) == 5

      assert :ok = perform_job(IntakeJob, %{"application_id" => id})

      assert [%Dedupe{}] = dedupe(id)
      [%Address{execution_id: execution_id}] = addresses(id)
      {:ok, inputs} = Executions.inputs(FirstWorkflow.store(), execution_id)
      rows = dumped([addresses(id), ledger(id), dedupe(id), inputs])

      for value <- @values do
        refute rows =~ value
      end

      # The positive arm: the host's own row does hold the values.
      stored = dumped(Repo.get!(CardApplication, id))
      assert Enum.all?(@values, &(stored =~ &1))
    end
  end

  describe "the job's answer" do
    # Sabotage: made `perform/1` answer `:ok` for every router answer; a
    # document never registered left the job green with nothing routed,
    # and this went red on the `{:error, _}`. Reverted from a copy.
    test "a router error is an error Oban retries, and a later run delivers" do
      id = store!()

      assert {:error, {:unresolved_document, "bdoc_card_application", :not_published}} =
               perform_job(IntakeJob, %{"application_id" => id})

      assert [] = addresses(id)

      register!()

      assert :ok = perform_job(IntakeJob, %{"application_id" => id})
      assert [%Address{}] = addresses(id)
    end

    # Sabotage: made `route/1` route a missing row under "riverbend"; the
    # job routed the id and answered `:ok` instead of cancelling, and this
    # went red on the `{:cancel, _}`. Reverted from a copy.
    test "an application no longer stored is cancelled, with nothing routed" do
      register!()
      id = store!()
      Repo.delete_all(from(a in CardApplication, where: a.id == ^id))

      assert {:cancel, {:application_not_found, ^id}} =
               perform_job(IntakeJob, %{"application_id" => id})

      assert [] = ledger(id)
    end
  end

  describe "the library system around every door" do
    # Sabotage: dropped `around_delivery:` from the router configuration;
    # the stepper found no library system, the delivery answered its
    # refusal, and this went red on the job's `:ok`. Reverted from a copy.
    test "the router runs the delivery inside the application's library system" do
      register!()
      id = store!("riverbend")

      assert {:error, :no_library_system} = Scope.fetch()
      assert :ok = perform_job(IntakeJob, %{"application_id" => id})
      assert {:error, :no_library_system} = Scope.fetch()

      assert %Config{around_delivery: Scope, on_create: Stepper, on_step: Stepper} =
               Router.config()
    end

    # Sabotage: made `Stepper.create/4` skip its `Scope.fetch/0`, then
    # `Stepper.step/5` skip its own; each call outside any library system
    # reached persistence, and this went red on its refusal. Each reverted
    # from a copy.
    test "the execution door refuses to create or step outside a library system" do
      {:ok, machine, _scxml} = PublishedCharts.runtime_chart()
      opts = [executor: &Router.execute/2]

      assert {:error, :no_library_system} =
               Stepper.create(
                 FirstWorkflow.store(),
                 "form_post_no_scope",
                 machine,
                 opts
               )

      assert {:ok, %Execution{}, _state} =
               Scope.around_delivery("riverbend", :route, fn ->
                 Stepper.create(
                   FirstWorkflow.store(),
                   "form_post_in_scope",
                   machine,
                   opts
                 )
               end)

      event = Statifier.Event.external("application.received")

      assert {:error, :no_library_system} =
               Stepper.step(FirstWorkflow.store(), "form_post_in_scope", machine, event, opts)

      assert {:ok, %Execution{}, _state} =
               Scope.around_delivery("riverbend", :route, fn ->
                 Stepper.step(FirstWorkflow.store(), "form_post_in_scope", machine, event, opts)
               end)
    end

    # Sabotage: made `Scope.around_delivery/3` leave its library system
    # held after the work; this went red on the read after the wrapper
    # returned. Making it skip the restore when the work raises went red on
    # the read after the raise. Each reverted from a copy.
    test "the wrapper runs the work once and restores what it found" do
      assert {:ok, "riverbend"} =
               Scope.around_delivery("riverbend", :route, fn ->
                 send(self(), :ran)
                 Scope.fetch()
               end)

      assert_received :ran
      refute_received :ran
      assert {:error, :no_library_system} = Scope.fetch()

      assert_raise RuntimeError, fn ->
        Scope.around_delivery("riverbend", :route, fn -> raise "the work failed" end)
      end

      assert {:error, :no_library_system} = Scope.fetch()

      assert {{:ok, "eastbank"}, {:ok, "riverbend"}} =
               Scope.around_delivery("riverbend", :route, fn ->
                 inner = Scope.around_delivery("eastbank", :route, fn -> Scope.fetch() end)
                 {inner, Scope.fetch()}
               end)
    end
  end
end
