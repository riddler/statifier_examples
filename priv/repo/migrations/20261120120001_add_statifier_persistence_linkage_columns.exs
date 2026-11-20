defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistenceLinkageColumns do
  @moduledoc """
  V09 of `statifier_persistence`'s DDL: six nullable `linkage_*` columns on
  the executions table and two indexes over them (the package's 0.26.0).

  The columns are where the package's Ecto adapter stores a durable
  subchart child's linkage on a backend that is not Postgres, for a host
  that sets `linkage_columns: true` on `use StatifierPersistence.Ecto`.
  `StatifierExamples.Persistence` does not set it: its generated execution
  schema names none of the six columns, so every read and write it makes
  is the one it made at V08, and a durable child's linkage stays under the
  package's reserved key in `metadata`, where this app's own listing
  callbacks read it. The package's upgrading page says a host in exactly
  that shape may run V09 or leave it. This app runs it now so that the
  database is already at the version the option needs on the day a host
  here turns it on, rather than adding the migration in the same change.
  V09 reads and writes no row and backfills nothing, and every statement
  in it runs on SQLite.

  Its own migration with its own floor, for the reason every
  `statifier_persistence` migration here has one: the migration before this
  one is capped at `version: 8`, and both bounds are spelled here, `from: 9`
  and `version: 9`, so the rollback covers exactly the span the migration
  covers.
  """

  use Ecto.Migration

  def up,
    do:
      StatifierPersistence.Ecto.Migrations.up(
        for: StatifierExamples.Persistence,
        from: 9,
        version: 9
      )

  def down,
    do:
      StatifierPersistence.Ecto.Migrations.down(
        for: StatifierExamples.Persistence,
        from: 9,
        version: 9
      )
end
