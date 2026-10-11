defmodule UpgradeHost.LoanTest do
  @moduledoc """
  One library loan, end to end, through every call the host makes: the
  chart compiled from the loan's block document and its event vocabulary,
  a durable create and steps, a
  timer that fires through Oban, two invocations answered through
  `Statifier.Invoke.Answer`, a host-side fail and the cascade after it,
  the position read back two ways, the metadata listing, and the spans.
  """

  use UpgradeHost.DataCase

  alias Statifier.{Chart, Event, Position}
  alias StatifierPersistence.{Driver, Execution, Executions, Storage}
  alias StatifierPersistence.Execution.Linkage
  alias StatifierBlocks.{Compiled, Provenance}
  alias UpgradeHost.{LoanWithNotice, Loans}
  alias UpgradeHost.Loans.{AssessFine, InvokeDelivery, LoanDocument, NotifyPatron}
  alias UpgradeHost.Spans

  @loan %{"copy" => "copy-2291", "patron" => "patron-1042"}

  setup do
    :ok = Spans.attach()
    :ok = Loans.register()
    :ok
  end

  describe "the chart" do
    # sabotage: compiled the document without terminate: true -> red, the
    # source carried no root_failed final.
    test "is the loan document's compile, and takes the loan's events and the two answers" do
      assert {:ok, %Compiled{scxml: scxml}} = LoanDocument.compile()
      assert Loans.source() == scxml
      assert Statifier.Machine.identity(Loans.machine()) == Loans.compiled().record.chart_identity
      assert {:ok, machine} = Statifier.compile(scxml)
      assert scxml =~ ~s(id="s_#{LoanDocument.block_id(:loan)}__root_failed")

      events = Chart.events(machine)

      for event <- [
            "loan.renew",
            "loan.returned",
            "statifier_blocks.wait." <> LoanDocument.block_id(:due),
            "done.invoke",
            "error.communication.invoke"
          ] do
        assert event in events
      end
    end

    test "takes every event the document accepts, and names an event it never takes" do
      accepts = LoanDocument.document().accepts
      assert accepts == ["loan.renew", "loan.returned"]

      assert %{unreachable: []} = Chart.check_accepts(Loans.machine(), accepts)
      assert %{unreachable: ["loan.lost"]} = Chart.check_accepts(Loans.machine(), ["loan.lost"])
    end
  end

  describe "the handler lookup" do
    # sabotage: the lookup built the step handler map from the document on
    # every call and kept nothing -> red, no map was kept for the node.
    # sabotage: the lookup dropped the kept map and built it again on every
    # call -> red, the fine's invocation named AssessFine over the kept map.
    test "reads each step's handler from a map kept once per node, not from the document" do
      key = {Loans, :step_handlers}
      fine = LoanDocument.block_id(:fine)
      notice = LoanDocument.block_id(:notice)
      fine_invocation = state_of(:fine) <> ".inv_1"
      notice_invocation = state_of(:notice) <> ".inv_1"

      assert {:ok, AssessFine} = Loans.handler_for_invocation(fine_invocation)
      assert :persistent_term.get(key, nil) == %{fine => AssessFine, notice => NotifyPatron}

      # The lookup answers from the kept map: a map that says otherwise is
      # what it answers, without the document being read again.
      kept = :persistent_term.get(key)
      on_exit(fn -> :persistent_term.put(key, kept) end)
      :persistent_term.put(key, %{fine => NotifyPatron})

      assert {:ok, NotifyPatron} = Loans.handler_for_invocation(fine_invocation)
      assert :error = Loans.handler_for_invocation(notice_invocation)
    end
  end

  describe "a loan" do
    # sabotage: the executor's cancel clause returned :ok without cancelling
    # -> red, two scheduled timers after the renewal.
    # sabotage: the invoke delivery's builder always built the answer -> red,
    # the redelivered fine answer was :delivered.
    # sabotage: the fine handler answered 300 -> red, the fine's amount was
    # 300.
    # sabotage: handler_for_invocation/1 answered NotifyPatron for every
    # invocation -> red, the fine's invocation named NotifyPatron.
    test "is renewed, comes due, is fined, the patron told, and the copy returned" do
      assert {:ok, %Execution{status: :active}, opened} =
               Loans.open("loan-1", "branch-eastside", @loan)

      # On loan: the wait is armed and the renewal handler listens.
      assert steps(opened) == [:due, :renew]
      assert [%Oban.Job{state: "scheduled"}] = jobs(:loan_timers)

      # A renewal re-enters the wait, which cancels the timer it had and
      # arms a fresh one.
      assert {:ok, %Execution{status: :active}, renewed} =
               Loans.deliver("loan-1", Event.external("loan.renew"))

      assert steps(renewed) == [:due, :renew]
      assert ["cancelled", "scheduled"] = :loan_timers |> jobs() |> states()

      # The loan comes due: the timer fires through Oban, and the fine is
      # assessed in an invoke job.
      assert %{success: 1} = drain(:loan_timers)
      overdue = position("loan-1")
      assert steps(overdue) == [:fine]
      [fine_invocation] = Map.values(overdue.active_invocations)
      assert {:ok, AssessFine} = Loans.handler_for_invocation(fine_invocation)

      assert %{success: 1} = drain(:loan_invocations)
      noticing = position("loan-1")
      assert steps(noticing) == [:notice]
      [notice_invocation] = Map.values(noticing.active_invocations)
      assert {:ok, NotifyPatron} = Loans.handler_for_invocation(notice_invocation)
      assert :error = Loans.handler_for_invocation("s_unknown.inv_1")

      assert %{success: 1} = drain(:loan_invocations)
      fined = position("loan-1")
      assert steps(fined) == [:loan]
      assert %{"amount" => 250, "copy" => "copy-2291"} = fined.datamodel["fine"]

      # The fine's answer, redelivered after the loan left the invocation, is
      # discarded by the position rather than stepped.
      assert {:discarded, :active} =
               InvokeDelivery.deliver("loan-1", fine_invocation, %{"amount" => 250}, [])

      assert {:ok, %Execution{status: :completed} = returned, _} =
               Loans.deliver("loan-1", Event.external("loan.returned"))

      assert Executions.ended?(returned)

      names = Spans.drain() |> Enum.map(& &1.name) |> MapSet.new()
      assert "statifier.macrostep" in names
      assert "statifier_persistence.execution.step" in names
      assert Enum.any?(names, &String.starts_with?(&1, "statifier_oban."))
    end

    test "returned while its fine is assessed cancels the job, and a late answer is discarded" do
      {:ok, _execution, _} = Loans.open("loan-2", "branch-eastside", @loan)
      assert %{success: 1} = drain(:loan_timers)
      assert [%Oban.Job{state: "available"}] = jobs(:loan_invocations)
      fine_invocation = invocation("loan-2")

      assert {:ok, %Execution{status: :completed}, _} =
               Loans.deliver("loan-2", Event.external("loan.returned"))

      assert [%Oban.Job{state: "cancelled"}] = jobs(:loan_invocations)

      assert {:discarded, :completed} =
               InvokeDelivery.deliver("loan-2", fine_invocation, %{"amount" => 250}, [])
    end

    test "whose fine fails for good ends failed, through the chart's own failed final" do
      {:ok, _execution, _} = Loans.open("loan-3", "branch-eastside", @loan)
      assert %{success: 1} = drain(:loan_timers)

      assert :delivered =
               InvokeDelivery.deliver_failure(
                 "loan-3",
                 invocation("loan-3"),
                 [reason: "run_failed", attempts: 20, detail: "no fine schedule"],
                 caller_context: nil
               )

      assert {:ok, %{status: :failed, failure: "failed_final"}} =
               Storage.fetch_execution(Loans.store(), "loan-3")
    end

    # sabotage: the return's transition targeted the waiting state -> red,
    # the loan did not complete.
    # sabotage: the executor's cancel_invoke clause returned :ok without
    # cancelling -> red, the notice job stayed available.
    # sabotage: the invoke delivery answered :delivered for a discarded
    # answer -> red, the late notice answer was :delivered.
    test "returned while the patron is notified cancels the job, and a late answer is discarded" do
      {:ok, _execution, _} = Loans.open("loan-9", "branch-eastside", @loan)
      assert %{success: 1} = drain(:loan_timers)
      assert %{success: 1} = drain(:loan_invocations)
      assert steps(position("loan-9")) == [:notice]
      assert ["available", "completed"] = :loan_invocations |> jobs() |> states()
      notice_invocation = invocation("loan-9")

      assert {:ok, %Execution{status: :completed} = returned, _} =
               Loans.deliver("loan-9", Event.external("loan.returned"))

      assert Executions.ended?(returned)
      assert ["cancelled", "completed"] = :loan_invocations |> jobs() |> states()

      assert {:discarded, :completed} =
               InvokeDelivery.deliver("loan-9", notice_invocation, %{"notice" => "n-1"}, [])
    end

    # sabotage: compiled the document without terminate: true -> red, the
    # loan did not end failed.
    # sabotage: the invoke delivery answered a failure as done -> red, the
    # loan did not end failed.
    test "whose notice fails for good ends failed, through the chart's own failed final" do
      {:ok, _execution, _} = Loans.open("loan-10", "branch-eastside", @loan)
      assert %{success: 1} = drain(:loan_timers)
      assert %{success: 1} = drain(:loan_invocations)
      assert steps(position("loan-10")) == [:notice]

      assert :delivered =
               InvokeDelivery.deliver_failure(
                 "loan-10",
                 invocation("loan-10"),
                 [reason: "run_failed", attempts: 20, detail: "no address on file"],
                 caller_context: nil
               )

      assert {:ok, %{status: :failed, failure: "failed_final"}} =
               Storage.fetch_execution(Loans.store(), "loan-10")
    end
  end

  describe "the host's own calls" do
    # sabotage: the timer delivery answered :delivered for a discarded loan
    # -> red, the due job succeeded instead of being cancelled.
    test "fail a loan, cascade the cancel over its children, and discard its timer" do
      store = Loans.store()
      {:ok, _execution, _} = Loans.open("loan-4", "branch-westside", @loan)

      assert {:ok, %Execution{status: :failed, failure: "copy_lost"}} =
               Executions.fail(store, "loan-4", "copy_lost")

      # A loan opens no subchart, so it has no children to cancel and no
      # parent to answer; the next test runs the cascade over a child.
      assert {:ok, 0} = Executions.cascade_cancel(store, Linkage.parent_match("loan-4"))
      assert {:ok, record} = Storage.fetch_execution(store, "loan-4")
      assert :no_linkage = Linkage.from_metadata(record.metadata)
      assert record.metadata == %{"branch_id" => "branch-westside", "loan_id" => "loan-4"}

      # The timer the loan armed still comes due, and its delivery finds the
      # loan ended: the job is cancelled rather than stepping a failed loan.
      assert %{cancelled: 1, success: 0} = drain(:loan_timers)
      assert {:ok, %{status: :failed}} = Storage.fetch_execution(store, "loan-4")
    end

    # sabotage: the cascade counted each child without cancelling it -> red,
    # the notice was still active after the cascade.
    # sabotage: Linkage.from_metadata/1 read a key the package never writes
    # -> red, the notice's linkage read :no_linkage.
    # sabotage: the driver's dispatch answered :pending without starting a
    # child -> red, the loan had no child.
    test "fail a loan whose notice runs as a child, and cascade the cancel over the child" do
      store = Loans.store()

      assert {:ok, %Execution{status: :active}, _} =
               Driver.create(LoanWithNotice.driver(), "loan-11",
                 metadata: %{"branch_id" => "branch-westside", "loan_id" => "loan-11"}
               )

      # The notice started as its own execution, linked to the loan.
      assert {:ok, [%{execution_id: notice_id}]} =
               Storage.list_executions_by_metadata(store, Linkage.parent_match("loan-11"))

      assert {:ok, record} = Storage.fetch_execution(store, notice_id)

      assert {:ok, %Linkage{parent_execution_id: "loan-11", child_index: 0} = linkage} =
               Linkage.from_metadata(record.metadata)

      assert linkage.invoke_id == LoanWithNotice.subchart_block_id()
      assert linkage.content_hash == record.content_hash
      assert notice_id == Linkage.child_execution_id("loan-11", linkage.invoke_id, 0)
      assert {:ok, ^linkage} = Driver.parent_link(store, notice_id)
      assert :no_parent = Driver.parent_link(store, "loan-11")

      # Failing the loan from outside steps no chart, so the notice is
      # still running; the cascade is what cancels it.
      assert {:ok, %Execution{status: :failed}} = Executions.fail(store, "loan-11", "copy_lost")
      assert {:ok, %{status: :active}} = Storage.fetch_execution(store, notice_id)

      assert {:ok, 1} = Executions.cascade_cancel(store, Linkage.parent_match("loan-11"))
      assert {:ok, %{status: :cancelled}} = Storage.fetch_execution(store, notice_id)
      assert {:ok, %{status: :failed}} = Storage.fetch_execution(store, "loan-11")

      # Run again, the cascade finds the notice already ended and writes
      # nothing.
      assert {:ok, 0} = Executions.cascade_cancel(store, Linkage.parent_match("loan-11"))
    end

    test "read a stored position back, through the guarded load and from the blob" do
      store = Loans.store()
      machine = Loans.machine()
      {:ok, _execution, opened} = Loans.open("loan-5", "branch-eastside", @loan)

      assert {:ok, loaded} = Storage.load_execution_position(store, "loan-5", machine)
      assert {:ok, %{position_blob: blob}} = Storage.fetch_execution(store, "loan-5")
      assert {:ok, decoded} = Position.from_binary(blob, machine)

      assert leaves(loaded) == leaves(opened)
      assert decoded.configuration == loaded.configuration
      assert decoded.datamodel["copy"] == "copy-2291"
    end

    test "list the loans at a branch through their metadata" do
      {:ok, _execution, _} = Loans.open("loan-6", "branch-eastside", @loan)
      {:ok, _execution, _} = Loans.open("loan-7", "branch-westside", @loan)

      assert {:ok, [%{execution_id: "loan-6"}]} = Loans.by_branch("branch-eastside")
    end

    # The bridge renders a datamodel value as a string under a
    # `new_value`, `prior_value` or `datamodel` key, and only when
    # record_datamodel_values is true; every other numeric attribute (a
    # duration, a count) is an integer and is not what this test is about.
    # sabotage: set up the bridges with record_datamodel_values: true ->
    # survived: at these versions no span or span event on this host's
    # durable path carries a datamodel-value key, so this pins that absence.
    # Re-run at opentelemetry_statifier 0.8.0 and 0.9.1: survived at both.
    test "keep datamodel values out of every span and span event" do
      {:ok, _execution, _} = Loans.open("loan-8", "branch-eastside", @loan)
      assert %{success: 1} = drain(:loan_timers)
      assert %{success: 1} = drain(:loan_invocations)

      spans = Spans.drain()
      assert Enum.any?(spans, &(&1.events != []))

      for span <- spans,
          attributes <- [span.attributes | Enum.map(span.events, &elem(&1, 1))],
          {key, value} <- attributes do
        refute String.ends_with?(to_string(key), [".new_value", ".prior_value", ".datamodel"])
        refute inspect(value) =~ "patron-1042"
        refute inspect(value) =~ "copy-2291"
        refute is_binary(value) and value =~ ~r/\b250\b/
      end
    end
  end

  defp leaves(machine_state),
    do: machine_state |> Statifier.active_leaf_states() |> Enum.sort()

  # The document blocks the loan is in, by the names `LoanDocument` gives
  # them: each active leaf state mapped back through the compile's
  # provenance to the block that emitted it.
  defp steps(machine_state) do
    names = LoanDocument.names()

    Loans.compiled().provenance
    |> Provenance.owners_of_states(Enum.to_list(Statifier.active_leaf_states(machine_state)))
    |> Enum.map(&Map.fetch!(names, &1.block_id))
    |> Enum.sort()
  end

  # The state the block `name` emitted as its own, read from the compile's
  # provenance.
  defp state_of(name) do
    block_id = LoanDocument.block_id(name)

    [state_id] =
      for {state_id, %{block_id: ^block_id, role: nil}} <-
            Loans.compiled().provenance.by_state_id,
          do: state_id

    state_id
  end

  # The one live invocation of a loan, by its generated invoke id.
  defp invocation(loan_id) do
    [invoke_id] = loan_id |> position() |> Map.fetch!(:active_invocations) |> Map.values()
    invoke_id
  end

  defp position(loan_id) do
    {:ok, machine_state} =
      Storage.load_execution_position(Loans.store(), loan_id, Loans.machine())

    machine_state
  end

  defp drain(queue),
    do: Oban.drain_queue(UpgradeHost.Oban, queue: queue, with_scheduled: true)

  defp jobs(queue) do
    queue = to_string(queue)
    Repo.all(from(j in Oban.Job, where: j.queue == ^queue, order_by: j.id))
  end

  defp states(jobs), do: jobs |> Enum.map(& &1.state) |> Enum.sort()
end
