defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistenceInputLog do
  @moduledoc """
  V04 and V05 of `statifier_persistence`'s DDL. V05 is the one this app
  wants: the per-run input log table its ADR-0010 adds - `run_id`, `seq`,
  `door`, `input_blob`, with a unique index on `(run_id, seq)` - which is
  what makes a stored run replayable and so what the editor page's Run
  pane reads a run back through (`StatifierExamples.Charts.Replay`).

  Its own migration with its own floor, for the reason V03's has one:
  every migration before it has already run on every database this app
  has, so a version the package adds afterwards is picked up by a
  migration of its own rather than by widening one that is already
  recorded. The migration before this one is ceilinged at `version: 3` in
  the same change, which is what leaves V04 to this one to apply.

  V04 comes along because it is the version in between and skipping a
  version is not a thing this API can do - and it costs nothing here. It
  rebuilds V03's `metadata` GIN index with `CREATE INDEX CONCURRENTLY`,
  which is a Postgres spelling; V03's migration already declined to create
  that index at all on this app's SQLite database, and inside a
  transaction V04 skips the rebuild and leaves whatever V03 left. So on
  this database V04 is a no-op, and on Postgres it is the rebuild it
  always was.

  V05 needs no such declining. It creates one ordinary table and one
  unique index, with no adapter check and no `jsonb`, so SQLite takes it
  on exactly the terms Postgres does - which is what lets this app be the
  reference embedder for a facility whose whole point is a replay.

  Order matters at deploy the way V03's did, and in the same direction:
  the table has to exist before the code that appends to it. Nothing in
  `statifier_persistence` writes an input unless the adapter exports
  `append_input/3`, and `StatifierExamples.Persistence` starts exporting
  it in the same change as this migration, so a database left at V03
  running that code would fail every step of every durable run rather
  than only the log write - the append is inside the run's serialized
  unit, and a failed append fails the step (ADR-0010 decision 5). The
  reverse order is safe: a V05 table nobody appends to is an empty table.
  """

  use Ecto.Migration

  def up,
    do: StatifierPersistence.Ecto.Migrations.up(for: StatifierExamples.Persistence, from: 4)

  def down,
    do: StatifierPersistence.Ecto.Migrations.down(for: StatifierExamples.Persistence, version: 4)
end
