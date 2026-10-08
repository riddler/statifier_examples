defmodule UpgradeHost.Repo.Migrations.RenameStatifierRouterSubscriptionIndex do
  use Ecto.Migration

  # The router's V03, which renames the subscription table's unique index,
  # as a migration of its own after the first one, which stops at V02.
  # The same table prefix and layout as that migration: V03 creates no
  # table, so the layout options build nothing, and passing them keeps one
  # options list for every router migration this host writes. The rollback
  # undoes V03 alone.
  @layout [
    table_prefix: "routing_",
    leading_columns: [branch_id: {:text, null: true}],
    timestamps_position: :leading,
    column_collations: [execution_id: "C"]
  ]

  def up, do: StatifierRouter.Migrations.up([from: 3] ++ @layout)
  def down, do: StatifierRouter.Migrations.down([from: 3, version: 3] ++ @layout)
end
