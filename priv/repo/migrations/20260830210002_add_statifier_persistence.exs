defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistence do
  @moduledoc """
  `statifier_persistence`'s own tables, delegated to its versioned
  migrations helper so the DDL cannot drift from the schemas
  `StatifierExamples.Persistence` generates.

  The call is CAPPED at `version: 2`, and the cap is what keeps a fresh
  clone and an already-migrated database on one path. Uncapped, this
  migration takes every version the package knows, so a fresh clone would
  reach V03 here while a database that ran this migration back when the
  package shipped V02 would not - and the second migration beside this
  one, which exists for that database, would then re-add a column the
  fresh clone already has. Capping here and adding V03 in its own
  migration gives both databases the same sequence of steps in the same
  order.

  V02's `metadata` column is inside the cap rather than optional. Taking
  V01 alone would leave the generated run schema selecting a column that
  does not exist - the schema carries `metadata` unconditionally - so
  "V01 only" is not a smaller version of this migration, it is a broken
  one. On SQLite the column is JSON text rather than `jsonb`, so the
  package's own containment query over it does not run and
  `StatifierExamples.Persistence` writes that query in Elixir instead
  (see its moduledoc).

  `down/1` IS capped to match, with the ceiling the package grew for
  exactly this shape. Until `statifier_persistence` 0.8.0
  `StatifierPersistence.Ecto.Migrations.down/1` took a `version:` floor
  and no ceiling, and always started from the newest version the package
  knew: this migration rolled back V03, V02 and V01, the V03 migration
  beside it rolled back V03 on its own, and because Ecto rolls migrations
  back newest first, `mix ecto.rollback --all` reached V03's `down` twice
  and the second one failed with `no such column: "outcome_blob"`.
  Measured on se-i4v, on this app's SQLite database, and reported upstream
  as the gap the reference embedder exists to surface rather than hidden
  behind two hand-written `ALTER`s here.

  0.8.0 is the fix (sp-8qq): `down/1` takes `from:`, the version it starts
  rolling back from, so a migration capped with `up(version: 2)` caps its
  rollback with `down(from: 2)`. The two options are a pair, and this
  migration now spells both. The ceiling matters more at 0.8.0 than it did
  at 0.7.2, because the package's newest version is now V04 - the
  concurrent rebuild of V03's `metadata` GIN index, a Postgres-only step
  and a no-op on this app's SQLite database, which no migration here takes.
  """

  use Ecto.Migration

  def up,
    do: StatifierPersistence.Ecto.Migrations.up(for: StatifierExamples.Persistence, version: 2)

  def down,
    do: StatifierPersistence.Ecto.Migrations.down(for: StatifierExamples.Persistence, from: 2)
end
