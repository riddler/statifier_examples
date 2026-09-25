defmodule StatifierExamples.Repo.Migrations.AddStatifierRouter do
  @moduledoc """
  `statifier_router`'s four tables - the address table, the dedupe table,
  the routing ledger (its V01) and the subscription table (its V02) - with
  this app's own `depot_id` column placed immediately after `id` on every
  one of them (the package's 0.6.0 `:leading_columns` option).

  The routed first-workflow recipe (`docs/guides/first-workflow-routed.md`)
  routes parcel scans into executions through these tables, and reads the
  column's position back to check it.

  The column is nullable and has no default, as the option asks: the
  package's schemas do not declare it, so every row the package inserts
  leaves it `NULL`. A default or a `NOT NULL` would belong to a later
  migration of this app's own. The same options list is handed to both
  directions; `down/1` ignores the layout options.

  Every statement in V01 and V02 runs on SQLite. Neither version is given
  a `:prefix`: that is a Postgres schema, and SQLite has none.
  """

  use Ecto.Migration

  @opts [leading_columns: [depot_id: {:text, null: true}]]

  def up, do: StatifierRouter.Migrations.up(@opts)

  def down, do: StatifierRouter.Migrations.down(@opts)
end
