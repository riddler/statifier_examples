defmodule StatifierExamples.Repo.Migrations.AddStatifierRouterLocations do
  @moduledoc """
  `statifier_router`'s location table (its V04), which only a router
  configuration that sets `:basichttp` needs: `StatifierExamples.HoldDesk`
  keeps each execution's BasicHTTP location token there, beside its
  address row.

  The table is opt-in and outside the router's version walk, so it is its
  own migration after `20260925120001_add_statifier_router.exs`, with the
  same `depot_id` leading column that migration gives every router table.
  It references the address table, and Ecto's rollback undoes this
  migration first. `down_locations/1` drops the table only if it is
  there. It runs on SQLite, with no `:prefix`.
  """

  use Ecto.Migration

  @opts [leading_columns: [depot_id: {:text, null: true}]]

  def up, do: StatifierRouter.Migrations.up_locations(@opts)

  def down, do: StatifierRouter.Migrations.down_locations(@opts)
end
