defmodule UpgradeHost.ChartRevisionTest do
  @moduledoc """
  A loan on loan moved onto a revised loan document, the way a host moves
  its live executions when the library changes the loan: through
  `StatifierPersistence.Executions.migrate/4`, with a plan from the chart
  the loan is pinned to onto the revised chart.

  Two revisions. One lengthens the loan period, which keeps every state
  the loan is in; the other withdraws renewals, which removes the renewal
  handler and the parallel region it ran beside, so the plan drops the
  states the loan is in there.

  What this pins is the migrated point the OpenTelemetry bridge exports:
  its `statifier_persistence.dropped` attribute is a sorted string array
  of the dropped state ids, and it is absent when a migration drops
  nothing.
  """

  use UpgradeHost.DataCase

  alias Statifier.Machine
  alias StatifierBlocks.{Compiled, Edit}
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierPersistence.Migration.Plan
  alias UpgradeHost.Loans
  alias UpgradeHost.Loans.LoanDocument
  alias UpgradeHost.Spans

  @loan %{"copy" => "copy-2291", "patron" => "patron-1042"}

  @migrated "statifier_persistence.execution.migrated"
  @dropped "statifier_persistence.dropped"

  setup do
    :ok = Spans.attach()
    :ok = Loans.register()
    :ok
  end

  # sabotage: the bridge rendered dropped with inspect/1, its shape before
  # opentelemetry_statifier 0.8 -> red, the point carried "[]".
  test "a loan moved onto a longer loan period drops nothing, and the point carries no dropped" do
    {:ok, _execution, _} = Loans.open("loan-r1", "branch-eastside", @loan)

    to = revise({:update_config, LoanDocument.block_id(:due), %{"duration" => "21d"}})
    {:ok, plan} = Plan.new(from: hash(Loans.machine()), to: hash(to))

    assert {:ok, %Execution{status: :active}, %{dropped: []}} = migrate("loan-r1", plan, to)

    assert [attributes] = migrated_points()
    assert attributes["statifier_persistence.execution_id"] == "loan-r1"
    refute Map.has_key?(attributes, @dropped)
  end

  # sabotage: the bridge rendered dropped with inspect/1 -> red, a string
  # where the array was. The bridge sorting dropped is not pinned here: the
  # migration already reports the dropped states in sorted order.
  test "a loan moved onto a loan without renewals drops the renewal states, as a sorted array" do
    {:ok, _execution, _} = Loans.open("loan-r2", "branch-eastside", @loan)

    to = revise({:remove, LoanDocument.block_id(:renew)})
    period = "s_" <> LoanDocument.block_id(:period)
    renew = "s_" <> LoanDocument.block_id(:renew)

    # Every state of the loan chart the revision no longer has: the
    # parallel region the renewal handler ran beside, its body and the
    # body's final and history, and the renewal handler's own states.
    gone = [
      period <> "__run",
      period <> "__body",
      period <> "__body_done",
      period <> "__history",
      renew,
      renew <> "__armed",
      renew <> "__o_done"
    ]

    {:ok, plan} = Plan.new(from: hash(Loans.machine()), to: hash(to), drop: gone)

    # The dropped states the loan was in, in its configuration.
    in_configuration =
      Enum.sort([period <> "__run", period <> "__body", renew, renew <> "__armed"])

    assert {:ok, %Execution{status: :active}, %{dropped: dropped}} =
             migrate("loan-r2", plan, to)

    assert Enum.sort(dropped) == in_configuration

    assert [attributes] = migrated_points()
    assert attributes[@dropped] == in_configuration
  end

  # The loan document with one more edit, compiled the way the host
  # compiles the loan, and saved under its content hash before any loan is
  # moved onto it.
  defp revise(edit) do
    {:ok, revised, _inverse} = Edit.apply(LoanDocument.document(), edit)
    {:ok, %Compiled{scxml: scxml, record: record}} = LoanDocument.compile(revised)
    {:ok, machine} = Statifier.compile(scxml, chart_name: record.document_id)
    assert hash(machine) != hash(Loans.machine())
    :ok = Storage.save_chart(Loans.store(), machine, scxml)
    machine
  end

  defp migrate(loan_id, plan, to) do
    Executions.migrate(Loans.store(), loan_id, plan,
      from_machine: Loans.machine(),
      to_machine: to
    )
  end

  defp hash(machine), do: Machine.identity(machine).content_hash

  # The migrated point's attributes. A migration outside a batch and outside
  # any step opens no span around the point, so the bridge exports it as a
  # zero-duration span of its own.
  defp migrated_points do
    for %{name: @migrated, attributes: attributes} <- Spans.drain(), do: attributes
  end
end
