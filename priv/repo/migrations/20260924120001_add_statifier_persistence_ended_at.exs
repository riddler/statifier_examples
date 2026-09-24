defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistenceEndedAt do
  @moduledoc """
  V08 of `statifier_persistence`'s DDL: the nullable `ended_at` column on
  the executions table and an index on it (the package's 0.17.0).

  This app takes V08 because the package's generated execution schema
  selects `ended_at` on every execution read from 0.17.0 on, so a database
  left at V07 fails the first read of a stored execution. V08 backfills
  nothing: an execution that was already terminal before it ran reads
  `ended_at` as `nil` until a later terminal write stamps it. Unlike V07,
  every statement in it runs on SQLite.

  Its own migration with its own floor, for the reason every
  `statifier_persistence` migration here has one: the migration before this
  one is capped at `version: 7`, and both bounds are spelled here, `from: 8`
  and `version: 8`, so the rollback covers exactly the span the migration
  covers.
  """

  use Ecto.Migration

  def up,
    do:
      StatifierPersistence.Ecto.Migrations.up(
        for: StatifierExamples.Persistence,
        from: 8,
        version: 8
      )

  def down,
    do:
      StatifierPersistence.Ecto.Migrations.down(
        for: StatifierExamples.Persistence,
        from: 8,
        version: 8
      )
end
