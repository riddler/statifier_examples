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

  `down/1` is NOT capped to match, because it cannot be:
  `StatifierPersistence.Ecto.Migrations.down/1` takes a `version:` floor
  and no ceiling, and always starts from the newest version the package
  knows. So this one rolls back V03, V02 and V01, while the V03 migration
  beside it rolls back V03 on its own - and Ecto rolls migrations back
  newest first, so `mix ecto.rollback --all` reaches V03's `down` twice
  and the second one fails: `no such column: "outcome_blob"`. Measured on
  se-i4v, on this app's SQLite database.

  That is left standing rather than worked around. Hand-writing the two
  `ALTER`s here would hide an upstream gap the reference embedder exists
  to surface: `up/1` grew `from:` so a host could take a later version in
  a later migration, and `down/1` has no ceiling to undo one. Filed
  against `statifier_persistence`. Nothing in this app's own flows reaches
  it - `mix ecto.reset` drops and re-creates rather than rolling back -
  and rolling back only the V03 migration (`mix ecto.rollback --step 1`)
  is correct.
  """

  use Ecto.Migration

  def up,
    do: StatifierPersistence.Ecto.Migrations.up(for: StatifierExamples.Persistence, version: 2)

  def down, do: StatifierPersistence.Ecto.Migrations.down(for: StatifierExamples.Persistence)
end
