defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistenceChartRetirement do
  @moduledoc """
  V07 of `statifier_persistence`'s DDL: the columns a chart retirement
  writes (its ADR-0012). An index on `executions(content_hash)`, and the
  nullable `retired_at` and `retired_by` columns on `charts`.

  This app retires no chart. It takes V07 because the package's generated
  chart schema selects both new columns on every chart read from 0.13.0 on,
  so a database left at V06 fails the first read of a stored chart - and
  0.13.0 is the release this app resolves, because `statifier_router`
  0.3.0 requires it.

  V07's other change, making the two chart blob columns nullable, is a
  Postgres statement and is skipped on this app's SQLite database, as the
  package's own moduledoc for the version says. A retirement therefore
  cannot run here; nothing here asks for one.

  Its own migration with its own floor, for the reason every
  `statifier_persistence` migration here has one: every version before it
  has already run on every database this app has, so a version the package
  adds afterwards is picked up by a migration of its own rather than by
  widening one that is already recorded. The migration before this one is
  already capped at `version: 6`, and both bounds are spelled here, `from:
  7` and `version: 7`, so the rollback covers exactly the span the
  migration covers.
  """

  use Ecto.Migration

  def up,
    do:
      StatifierPersistence.Ecto.Migrations.up(
        for: StatifierExamples.Persistence,
        from: 7,
        version: 7
      )

  def down,
    do:
      StatifierPersistence.Ecto.Migrations.down(
        for: StatifierExamples.Persistence,
        from: 7,
        version: 7
      )
end
