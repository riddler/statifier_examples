defmodule UpgradeHost.MigrationsTest do
  @moduledoc """
  The tables as the host's migrations lay them out, read back from the
  database's own catalog: the router's tables under the host's prefix
  with its branch column and timestamps leading, and `execution_id` in
  the "C" collation in both packages' tables.
  """

  use UpgradeHost.DataCase

  @router_tables ~w(routing_addresses routing_dedupe routing_routing_ledger routing_subscriptions)

  test "every router table opens with the host's branch column" do
    for table <- @router_tables do
      assert ["id", "branch_id" | _rest] = columns(table), "#{table} does not open with branch_id"
    end
  end

  # sabotage: dropped `timestamps_position: :leading` from the router
  # migration's layout and re-migrated -> red, inserted_at at the end.
  test "the router tables carrying inserted_at have it right after the branch column" do
    for table <- @router_tables -- ["routing_dedupe"] do
      assert ["id", "branch_id", "inserted_at" | _rest] = columns(table)
    end
  end

  test "execution_id is in the C collation wherever either package declares it" do
    for table <- ~w(routing_addresses routing_routing_ledger routing_subscriptions
                    statifier_executions statifier_inputs) do
      assert collation(table, "execution_id") == "C", "#{table}.execution_id"
    end
  end

  test "the persistence tables open with the branch column and their timestamps" do
    for table <- ~w(statifier_charts statifier_positions statifier_executions statifier_inputs) do
      assert ["id", "branch_id", "inserted_at", "updated_at" | _rest] = columns(table)
    end
  end

  defp columns(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT column_name FROM information_schema.columns " <>
          "WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position",
        [table]
      )

    List.flatten(rows)
  end

  defp collation(table, column) do
    %{rows: [[collation]]} =
      Repo.query!(
        "SELECT collation_name FROM information_schema.columns " <>
          "WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2",
        [table, column]
      )

    collation
  end
end
