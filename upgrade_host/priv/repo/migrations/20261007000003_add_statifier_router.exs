defmodule UpgradeHost.Repo.Migrations.AddStatifierRouter do
  use Ecto.Migration

  # The router's tables, migrated though nothing calls the router yet, in
  # the layout a multi-tenant host gives them: its own table prefix, its
  # tenant column leading every table, the timestamps after it, and the
  # "C" collation on `execution_id`. Capped at version 2, the newest this
  # host's release ships, with the rollback capped to match.
  @layout [
    table_prefix: "routing_",
    leading_columns: [branch_id: {:text, null: true}],
    timestamps_position: :leading,
    column_collations: [execution_id: "C"]
  ]

  def up, do: StatifierRouter.Migrations.up([version: 2] ++ @layout)
  def down, do: StatifierRouter.Migrations.down([from: 2] ++ @layout)
end
