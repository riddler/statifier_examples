defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistenceOutcomeBlob do
  @moduledoc """
  V03 of `statifier_persistence`'s DDL: the runs table's nullable
  `outcome_blob` column, and - on Postgres only - a GIN index over
  `metadata`.

  Its own migration rather than a wider cap on the one before it, because
  the one before it has already run on every database this app has: a
  version the package added after that migration was recorded is picked up
  with a `from:` migration of its own, which is what the package's README
  prescribes. The migration before this one is capped at `version: 2` so a
  fresh clone arrives here having taken exactly V01 and V02, and this
  migration is the only place V03 is applied on either path.

  Order matters at deploy: V03 comes before the code that needs it.
  `outcome_blob` is an unconditional field on the generated runs schema
  from 0.7.0 on, so that code against a V02 database fails every query
  that touches the runs table, not only the fan-out write the column was
  added for. The reverse order is safe - V03 under 0.6.x is a column
  nobody writes.

  CEILINGED at `version: 3` on 2026-09-06 (se-dh0), and the ceiling is a
  correction rather than a tidy. `from: 3` alone means "V03 and everything
  the package has added since", so the moment `statifier_persistence` grew
  a V04 and a V05 this migration began applying three versions on a fresh
  clone while an already-migrated database - which took exactly V03 the day
  this file was written - took none of them. That is the drift the
  paragraph above says a later version avoids by arriving in a migration of
  its own, and the ceiling is what makes the sentence true of this file
  too. `up(version: 3)` pairs with `down(from: 3)`, the same pairing the
  V01+V02 migration spells one file up.

  On this app's SQLite database the GIN index is skipped: `GIN` and
  `jsonb_path_ops` are Postgres spellings, so `V03.up/1` creates the index
  only on `Ecto.Adapters.Postgres`. The column is created on every adapter.
  In 0.7.0 the index was unconditional and `ecto_sqlite3` raised on it,
  which rolled the whole migration back and took the column with it
  (sp-11w); 0.7.1 is the fix. `~> 0.7` in `mix.exs` permits 0.7.0 as well,
  so what says this app is on 0.7.1 is `mix.lock`, and `mix_deps_test.exs`
  asserts it there.
  """

  use Ecto.Migration

  def up,
    do:
      StatifierPersistence.Ecto.Migrations.up(
        for: StatifierExamples.Persistence,
        from: 3,
        version: 3
      )

  def down,
    do:
      StatifierPersistence.Ecto.Migrations.down(
        for: StatifierExamples.Persistence,
        from: 3,
        version: 3
      )
end
