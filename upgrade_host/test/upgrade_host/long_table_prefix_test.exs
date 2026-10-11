defmodule UpgradeHost.LongTablePrefixTest do
  @moduledoc """
  The router's V03 over a subscription index Postgres truncated.

  The host's own router migrations use the "routing_" table prefix, under
  which V02's unique index name is 61 bytes and fits in the 63 Postgres
  keeps, so the rename `UpgradeHost.MigrationsTest` reads back started from
  a whole name. A branch library whose host gives its routing tables a
  longer prefix, "library_routing_", gets a 69-byte name from V02, and
  Postgres creates that index under its first 63 bytes. This test walks
  that case: V02 under the long prefix, the truncated name read back, then
  V03 as a migration of its own, mirroring the host's
  `20261008000001_rename_statifier_router_subscription_index.exs` (which
  keeps its "routing_" prefix, so it cannot be run under this one), and
  the renamed index read back.

  The tables go into a Postgres schema of their own, "library_branch", so
  they never meet the host's tables in "public", and the test's sandboxed
  transaction rolls the schema, the tables and the migrations' rows back
  when it ends.
  """

  use UpgradeHost.DataCase

  @schema "library_branch"
  @table_prefix "library_routing_"
  @subscriptions "library_routing_subscriptions"

  # The host's router layout, under the long prefix and in the schema
  # above.
  @layout [
    table_prefix: @table_prefix,
    prefix: @schema,
    leading_columns: [branch_id: {:text, null: true}],
    timestamps_position: :leading,
    column_collations: [execution_id: "C"]
  ]

  defmodule AddRouter do
    @moduledoc false
    use Ecto.Migration

    def up, do: StatifierRouter.Migrations.up([version: 2] ++ layout())
    def down, do: StatifierRouter.Migrations.down([from: 2] ++ layout())

    def layout, do: UpgradeHost.LongTablePrefixTest.layout()
  end

  defmodule RenameSubscriptionIndex do
    @moduledoc false
    use Ecto.Migration

    def up, do: StatifierRouter.Migrations.up([from: 3] ++ layout())
    def down, do: StatifierRouter.Migrations.down([from: 3, version: 3] ++ layout())

    def layout, do: UpgradeHost.LongTablePrefixTest.layout()
  end

  @doc false
  def layout, do: @layout

  # What this asserts is that the name V03 renames from finds the index
  # Postgres holds; Postgres cuts a longer name in the ALTER INDEX itself,
  # so V03 spelling the name already cut (no notice) is not observed here.
  # sabotage: set V03's @max_identifier_bytes to 62 in the router's
  # deps/ source and recompiled it -> red, the index still under the
  # truncated name, which the rename no longer found.
  test "V03 renames the subscription index V02 left under a truncated name" do
    v02_name = "#{@subscriptions}_execution_id_binding_id_invoke_id_index"
    assert byte_size(v02_name) == 69

    migrate(:up, 20_991_231_000_001, AddRouter)

    truncated = binary_part(v02_name, 0, 63)
    assert truncated == "library_routing_subscriptions_execution_id_binding_id_invoke_id"
    assert [{^truncated, definition}] = unique_indexes(@subscriptions)
    assert definition =~ "(execution_id, binding_id, invoke_id)"

    migrate(:up, 20_991_231_000_002, RenameSubscriptionIndex)

    assert [{"library_routing_subscriptions_invocation_index", definition}] =
             unique_indexes(@subscriptions)

    assert definition =~ "(execution_id, binding_id, invoke_id)"

    migrate(:down, 20_991_231_000_002, RenameSubscriptionIndex)

    assert [{^truncated, _definition}] = unique_indexes(@subscriptions)
  end

  # Ecto's migrator holds a lock on a second connection while it migrates,
  # which the sandbox's one shared connection cannot give it; without the
  # lock the migrations run on that connection, inside the test's
  # transaction.
  defp migrate(direction, version, migration) do
    result = apply(Ecto.Migrator, direction, [Repo, version, migration, opts()])
    assert result == :ok
  end

  defp opts, do: [log: false, migration_lock: false]

  # The table's unique indexes other than its primary key, in the test's
  # schema, as {name, definition}.
  defp unique_indexes(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT i.relname, pg_get_indexdef(x.indexrelid) FROM pg_index x " <>
          "JOIN pg_class i ON i.oid = x.indexrelid " <>
          "JOIN pg_class t ON t.oid = x.indrelid " <>
          "JOIN pg_namespace n ON n.oid = t.relnamespace " <>
          "WHERE n.nspname = $1 AND t.relname = $2 " <>
          "AND x.indisunique AND NOT x.indisprimary ORDER BY i.relname",
        [@schema, table]
      )

    Enum.map(rows, &List.to_tuple/1)
  end
end
