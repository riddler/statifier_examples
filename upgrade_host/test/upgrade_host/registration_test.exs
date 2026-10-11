defmodule UpgradeHost.RegistrationTest do
  @moduledoc """
  Patron registration through the router's webhook front, the host's
  first binding: a form post the host accepts and routes from a job, the
  execution it creates, a resubmission answered from the dedupe store, the
  confirmation that ends the registration, the sweep that reaps its
  address, and the patron's next registration opening a new execution.
  Every delivery runs inside the host's tenancy context, and nothing the
  form posted reaches the router's rows or the execution.
  """

  use UpgradeHost.DataCase

  alias StatifierPersistence.{Execution, Storage}
  alias StatifierRouter.Schema.{Address, Ledger}
  alias UpgradeHost.Registrations
  alias UpgradeHost.Registrations.Patron

  @branch "branch-eastside"
  @form %{"name" => "Ada Quill", "email" => "ada.quill@example.com"}
  @horizon_ms 3_600_000

  # sabotage: dropped `around_delivery: Seams` from the router
  # configuration -> red, the job's create raised with no branch set.
  # sabotage: the engine's create stamped a branch other than the scope ->
  # red, the execution's metadata named another branch.
  # sabotage: Registrations.reap/2 passed `now: DateTime.utc_now()` to the
  # address reap -> red, the ended registration's row was never deleted.
  # sabotage: FormPost kept the execution id only on `:delivered` -> red,
  # the patron row named no execution.
  test "a form post creates the registration, a resubmission is a duplicate, and the ended registration's address is reaped" do
    # The host answers the post before anything is routed.
    assert {:ok, patron_id} = Registrations.submit(@branch, @form)
    assert [] = addresses()
    assert [%Oban.Job{args: args}] = jobs()
    assert args == %{"branch_id" => @branch, "patron_id" => patron_id}

    # The job routes it: the message creates the patron's registration.
    assert %{success: 1} = drain()

    assert [%Address{scope: @branch, key: ^patron_id, execution_id: first} = address] =
             addresses()

    assert address.document == "patron_registration"
    assert %Patron{registration_execution_id: ^first} = Repo.get!(Patron, patron_id)

    assert {:ok, %{status: :active, metadata: %{"branch_id" => @branch}}} =
             Storage.fetch_execution(Registrations.store(), first)

    assert active(first) == ["awaiting_confirmation"]
    assert ledger() == [{"created_and_delivered", patron_id, first}]

    # The same patron posts again: the same patron row, the same message,
    # answered from the dedupe store; nothing reaches the execution.
    assert {:ok, ^patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    assert [%Address{execution_id: ^first}] = addresses()
    assert ledger() == [{"created_and_delivered", patron_id, first}, {"duplicate", patron_id, ""}]

    # A sweep while the registration runs leaves its address as it is.
    now = DateTime.utc_now()
    assert {:ok, %{addresses: %{stamped: 0, deleted: 0}}} = Registrations.reap(now)

    # The patron confirms, and the registration ends.
    assert {:ok, %Execution{status: :completed}, _state} =
             Registrations.confirm(@branch, patron_id)

    # The next sweep sees it ended and keeps the row for the horizon; the
    # sweep after the horizon deletes it, and the expired dedupe row.
    assert {:ok, %{addresses: %{stamped: 1, deleted: 0}, dedupe: 0}} = Registrations.reap(now)
    assert [%Address{terminal_seen_at: %DateTime{}}] = addresses()

    later = DateTime.add(now, @horizon_ms + 1, :millisecond)
    assert {:ok, %{addresses: %{stamped: 0, deleted: 1}, dedupe: 1}} = Registrations.reap(later)
    assert [] = addresses()

    # The patron registers again: a new execution at the same address.
    assert {:ok, ^patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    assert [%Address{key: ^patron_id, execution_id: second}] = addresses()
    assert second != first
    assert %Patron{registration_execution_id: ^second} = Repo.get!(Patron, patron_id)
    assert {:ok, %{status: :active}} = Storage.fetch_execution(Registrations.store(), second)
    assert {"created_and_delivered", patron_id, second} == List.last(ledger())
  end

  # sabotage: Registrations.reap/2 swept one page and ignored `next` ->
  # red, the sweep stamped fewer than four rows.
  # sabotage: the sweep kept only the last page's counts -> red, it
  # answered fewer than four stamped rows.
  # sabotage: the sweep dropped `:limit` from each page's options -> red,
  # it read one page, not three.
  @tag timeout: 10_000
  test "the sweep pages through the address table, so every ended registration's address is reaped" do
    # Five patrons register; four confirm, and one registration still runs.
    patrons =
      for n <- 1..5 do
        form = %{"name" => "Patron #{n}", "email" => "patron.#{n}@example.com"}
        assert {:ok, patron_id} = Registrations.submit(@branch, form)
        patron_id
      end

    assert %{success: 5} = drain()
    assert length(addresses()) == 5

    {running, ended} = List.pop_at(patrons, 2)

    for patron_id <- ended do
      assert {:ok, %Execution{status: :completed}, _state} =
               Registrations.confirm(@branch, patron_id)
    end

    # Two rows a page: the sweep reads three pages, and the first sweep to
    # see the four registrations ended stamps all four rows.
    now = DateTime.utc_now()

    assert {:ok, %{addresses: %{stamped: 4, deleted: 0, pages: 3}}} =
             Registrations.reap(now, limit: 2)

    assert Enum.count(addresses(), &match?(%Address{terminal_seen_at: %DateTime{}}, &1)) == 4

    # A horizon later the next sweep deletes all four, and keeps the row of
    # the registration that still runs.
    later = DateTime.add(now, @horizon_ms + 1, :millisecond)

    assert {:ok, %{addresses: %{stamped: 0, deleted: 4, pages: 3}}} =
             Registrations.reap(later, limit: 2)

    assert [%Address{key: ^running, terminal_seen_at: nil}] = addresses()
  end

  # sabotage: routed the patron's email in the post's data and added it to
  # the binding's projection -> red, the email in the input log's row.
  # Routing it in the data alone stays green: the binding projects
  # `patron_id` only, so nothing else of the post is stored.
  test "no value the form posted reaches the router's rows or the execution" do
    assert {:ok, patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    assert {:ok, ^patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()

    assert {:ok, %Execution{status: :completed}, _state} =
             Registrations.confirm(@branch, patron_id)

    [%Address{execution_id: execution_id}] = addresses()

    # The datamodel holds the patron's id, and nothing the form posted.
    datamodel = datamodel(execution_id)
    assert datamodel["patron_id"] == patron_id
    for {_name, value} <- datamodel, do: refute(value in Map.values(@form))

    # Every row the router and the store wrote, read as the database
    # renders it (a binary column as hex), carries the patron's id and
    # none of the form's values. The patron's own row holds those.
    rows = rows(~w(routing_addresses routing_dedupe routing_routing_ledger
                   routing_subscriptions statifier_executions statifier_positions
                   statifier_inputs oban_jobs))

    assert Enum.any?(rows, &String.contains?(&1, patron_id))
    assert Enum.any?(rows, &String.contains?(&1, Base.encode16(patron_id, case: :lower)))

    for value <- Map.values(@form), row <- rows do
      refute String.contains?(row, value), "a form value in #{row}"
      refute String.contains?(row, Base.encode16(value, case: :lower)), "a form value in #{row}"
    end

    assert %Patron{name: "Ada Quill", email: "ada.quill@example.com"} =
             Repo.get!(Patron, patron_id)
  end

  # sabotage: Seams.around_delivery/3 called `work` outside
  # Tenancy.run/2 -> red, the job's create raised with no branch set.
  # sabotage: the engine's step read the branch with `current/0` -> red,
  # the step outside the context raised nothing.
  test "every delivery runs inside the branch's tenancy context, which the create and the step read" do
    assert {:ok, _patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    [%Address{execution_id: execution_id}] = addresses()

    # The create ran inside the context: the branch it stamped is the scope.
    assert {:ok, %{metadata: %{"branch_id" => @branch}}} =
             Storage.fetch_execution(Registrations.store(), execution_id)

    # Another patron's post through a configuration with no wrapper reaches
    # the host's create with no branch set, and the create refuses it.
    config = %{Registrations.router_config() | around_delivery: nil}
    other = "patron_unwrapped"

    assert_raise RuntimeError, ~r/no branch is set/, fn ->
      StatifierRouter.Webhook.handle(config, %{
        scope: @branch,
        source: Registrations.source(),
        raw_body: other,
        provider_id: other,
        data: %{"patron_id" => other}
      })
    end

    # The step reads it too: outside the context it refuses.
    assert_raise RuntimeError, ~r/no branch is set/, fn ->
      Registrations.Seams.step(
        Registrations.store(),
        execution_id,
        Registrations.machine(),
        Statifier.Event.external("registration.confirmed"),
        executor: Registrations.Seams
      )
    end
  end

  defp drain, do: Oban.drain_queue(UpgradeHost.Oban, queue: :registrations)

  defp jobs, do: Repo.all(from(j in Oban.Job, where: j.queue == "registrations"))

  defp addresses do
    config = Registrations.router_config()
    Repo.all(from(a in StatifierRouter.Config.queryable(config, Address), order_by: a.id))
  end

  defp ledger do
    config = Registrations.router_config()

    Repo.all(
      from(l in StatifierRouter.Config.queryable(config, Ledger),
        order_by: l.id,
        select: {l.outcome, l.key, l.execution_id}
      )
    )
    |> Enum.map(fn {outcome, key, execution_id} -> {outcome, key || "", execution_id || ""} end)
  end

  defp active(execution_id) do
    {:ok, state} =
      Storage.load_execution_position(
        Registrations.store(),
        execution_id,
        Registrations.machine()
      )

    state |> Statifier.active_leaf_states() |> Enum.to_list() |> Enum.sort()
  end

  defp datamodel(execution_id) do
    {:ok, state} =
      Storage.load_execution_position(
        Registrations.store(),
        execution_id,
        Registrations.machine()
      )

    state.datamodel
  end

  defp rows(tables) do
    for table <- tables,
        %{rows: rows} = Repo.query!("SELECT t::text FROM #{table} t"),
        [row] <- rows,
        do: row
  end
end
