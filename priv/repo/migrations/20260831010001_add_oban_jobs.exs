defmodule StatifierExamples.Repo.Migrations.AddObanJobs do
  @moduledoc """
  Oban's own table, delegated to its versioned migration helper so the DDL
  cannot drift from the engine this app runs.

  `Oban.Migrations.up/0` dispatches on the repo's adapter, so on SQLite it
  is `Oban.Migrations.SQLite`'s single version: one `oban_jobs` table with
  `args` and `meta` as JSON text, and one index on the columns the Lite
  engine's staging query reads. There is no `oban_peers` table and no
  trigger, because neither exists on this engine.

  The table is this app's, not `statifier_oban`'s: that package never owns
  an Oban instance (its ADR-0002), so the schema it inserts into belongs to
  the host that supplies one.
  """

  use Ecto.Migration

  def up, do: Oban.Migrations.up()

  def down, do: Oban.Migrations.down()
end
