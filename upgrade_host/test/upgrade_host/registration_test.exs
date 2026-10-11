defmodule UpgradeHost.RegistrationTest do
  @moduledoc """
  Patron registration through the router's webhook front, the host's
  first binding: a form post the host accepts and routes from a job, the
  execution it creates, a resubmission answered from the dedupe store, the
  confirmation that ends the registration, the sweep that reaps its
  address, the patron's next registration opening a new execution, and a
  post the router answers with an error, rolled back and retried.
  Every delivery runs inside the host's tenancy context, and nothing the
  form posted reaches the router's rows or the execution.
  """

  use UpgradeHost.DataCase

  alias StatifierPersistence.{Execution, Storage}
  alias StatifierRouter.Schema.{Address, Dedupe, Ledger}
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

  # sabotage: Seams.around_delivery/3 called `work` outside
  # Tenancy.run/2 -> red, the job that opens the registration failed.
  # sabotage: Seams.around_delivery/3 ran `work` as another branch -> red,
  # the step read that branch, not the scope.
  # sabotage: Seams.step/5 did not read the context -> red, no read of
  # the branch came from the step.
  test "a post the binding routes to the live registration steps it inside the branch's tenancy context" do
    assert {:ok, patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    [%Address{execution_id: execution_id}] = addresses()

    # A later post from the same patron, as a new message: not a
    # duplicate, so the binding routes it to the registration the address
    # names, and the router steps that execution through the host's
    # `on_step`, inside its `around_delivery`. The registration already
    # waits for confirmation, so the step selects no transition and the
    # router records the post as unmatched; the step has run all the same.
    post = %{
      scope: @branch,
      source: Registrations.source(),
      raw_body: patron_id,
      provider_id: "#{patron_id}-again",
      data: %{"patron_id" => patron_id}
    }

    {answer, reads} =
      tenancy_reads(fn -> StatifierRouter.Webhook.handle(Registrations.router_config(), post) end)

    assert {:ok, [{:dropped, "registration_form_to_patron", :unmatched_event}]} = answer
    assert {"dropped: unmatched_event", patron_id, execution_id} == List.last(ledger())
    assert active(execution_id) == ["awaiting_confirmation"]

    # The step read the context, and the context was the post's scope.
    assert reads == [{{Registrations.Seams, :step, 5}, @branch}]

    # The same post through a configuration with no wrapper reaches the
    # step with no branch set, and the step refuses it.
    config = %{Registrations.router_config() | around_delivery: nil}

    {raised, stacktrace} =
      try do
        StatifierRouter.Webhook.handle(config, %{post | provider_id: "#{patron_id}-unwrapped"})
        flunk("the unwrapped step did not raise")
      rescue
        error in RuntimeError -> {error, __STACKTRACE__}
      end

    assert raised.message =~ "no branch is set"
    assert Enum.any?(stacktrace, &match?({Registrations.Seams, :step, 5, _location}, &1))
  end

  # sabotage: FormPost answered the 500 with `{:error, reason}` instead of
  # `Repo.rollback/1` -> red, the job completed on its first attempt.
  # sabotage: FormPost's worker set `max_attempts: 1` -> red, the failed
  # job was discarded, not scheduled again.
  # sabotage: FormPost routed the post outside its transaction, and the
  # router's delivery released its savepoint on an error -> red, the
  # failed attempt's dedupe row stayed written. The router's release alone
  # stays green: FormPost's rollback undoes the attempt.
  test "a post the router answers with an error is rolled back, leaves nothing written, and is retried" do
    assert {:ok, patron_id} = Registrations.submit(@branch, @form)
    assert %{success: 1} = drain()
    [%Address{execution_id: execution_id}] = addresses()

    # A sweep a horizon on expires the post's dedupe row, so the patron's
    # next post of the form is a new message for the live registration.
    later = DateTime.add(DateTime.utc_now(), @horizon_ms + 1, :millisecond)
    assert {:ok, %{dedupe: 1, addresses: %{stamped: 0, deleted: 0}}} = Registrations.reap(later)

    # The host has moved to a new revision of the registration chart, and
    # its chart resolver no longer answers the revision this registration
    # started on: the router cannot step it, and answers an error.
    started_on = Registrations.machine()
    revised = revised_machine()
    on_exit(fn -> :persistent_term.put({Registrations, :machine}, started_on) end)
    :persistent_term.put({Registrations, :machine}, revised)

    assert %{dedupe: 0} = before = written(execution_id)
    assert {:ok, ^patron_id} = Registrations.submit(@branch, @form)

    # The job reads the error as a 500: the attempt did not settle, so
    # the job fails and Oban schedules it again.
    assert %{failure: 1, success: 0} = drain()
    assert [_first, %Oban.Job{state: "retryable", attempt: 1, errors: [error]} = job] = jobs()
    assert error["error"] =~ "chart_not_resolved"

    # Nothing of the attempt is written: no dedupe row claims the message,
    # no ledger row records it, the input log holds no event for it, and
    # the registration still waits where it was.
    assert written(execution_id) == before
    :persistent_term.put({Registrations, :machine}, started_on)
    assert active(execution_id) == ["awaiting_confirmation"]

    # The host answers the revision again, and the retry settles: the
    # same job, on its second attempt, routes the post to the
    # registration, which records it as unmatched (it already waits for
    # confirmation), and the message is now claimed.
    assert %{success: 1, failure: 0} = drain(with_scheduled: true)
    assert [_first, %Oban.Job{id: id, state: "completed", attempt: 2}] = jobs()
    assert id == job.id
    assert {"dropped: unmatched_event", patron_id, execution_id} == List.last(ledger())
    assert %{dedupe: 1} = written(execution_id)
  end

  # The registration chart with one more way out of it: a revision whose
  # content hash is not the one an execution of the original records.
  defp revised_machine do
    scxml =
      String.replace(
        Registrations.scxml(),
        ~s(<transition event="registration.confirmed" target="registered"/>),
        ~s(<transition event="registration.confirmed" target="registered"/>
      <transition event="registration.withdrawn" target="withdrawn"/>)
      )
      |> String.replace(~s(<final id="registered"/>), ~s(<final id="registered"/>
    <final id="withdrawn"/>))

    {:ok, machine} = Statifier.compile(scxml, chart_name: Registrations.document())

    refute Statifier.Machine.identity(machine).content_hash ==
             Statifier.Machine.identity(Registrations.machine()).content_hash

    machine
  end

  # What the router and the store have written for the registration: the
  # dedupe rows, the ledger rows and the execution's input log.
  defp written(execution_id) do
    config = Registrations.router_config()

    %{
      dedupe: Repo.aggregate(StatifierRouter.Config.queryable(config, Dedupe), :count),
      ledger: ledger(),
      inputs:
        Repo.one!(
          from(i in "statifier_inputs", where: i.execution_id == ^execution_id, select: count())
        )
    }
  end

  # Runs `fun` in this process with every call of
  # `UpgradeHost.Tenancy.current!/0` traced to a collector, and answers what
  # `fun` answered beside each read: the function that read the context and
  # the branch the read answered.
  defp tenancy_reads(fun) do
    mfa = {UpgradeHost.Tenancy, :current!, 0}
    collector = spawn_link(fn -> collect([]) end)
    :erlang.trace_pattern(mfa, [{:_, [], [{:return_trace}, {:message, {:caller}}]}], [:local])
    :erlang.trace(self(), true, [:call, {:tracer, collector}])

    answer =
      try do
        fun.()
      after
        :erlang.trace(self(), false, [:call])
        :erlang.trace_pattern(mfa, false, [:local])
      end

    # Every trace message has reached the collector before it is asked.
    ref = :erlang.trace_delivered(self())
    assert_receive {:trace_delivered, _pid, ^ref}
    send(collector, {:reads, self()})
    assert_receive {:reads, messages}

    {answer, pair_reads(messages)}
  end

  defp collect(messages) do
    receive do
      {:reads, from} -> send(from, {:reads, Enum.reverse(messages)})
      message -> collect([message | messages])
    end
  end

  defp pair_reads([
         {:trace, _caller_pid, :call, {UpgradeHost.Tenancy, :current!, []}, caller},
         {:trace, _return_pid, :return_from, {UpgradeHost.Tenancy, :current!, 0}, branch}
         | rest
       ]),
       do: [{caller, branch} | pair_reads(rest)]

  defp pair_reads([]), do: []

  defp drain(opts \\ []),
    do: Oban.drain_queue(UpgradeHost.Oban, [queue: :registrations] ++ opts)

  defp jobs, do: Repo.all(from(j in Oban.Job, where: j.queue == "registrations", order_by: j.id))

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
