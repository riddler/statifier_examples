defmodule StatifierExamples.Repo.Migrations.RenameStatifierPersistenceExecutions do
  @moduledoc """
  V06 of `statifier_persistence`'s DDL: the rename that makes `execution`
  the durable noun in the schema as well as in the API (its ADR-0011).

  On this app's databases - which were built by the four migrations before
  this one, back when the package called the thing a run - V06 renames
  `statifier_runs` to `statifier_executions`, both `run_id` columns to
  `execution_id`, and the indexes over them. In place, copying no data. On
  a database built from scratch at the pinned version there is nothing to
  rename, because V01 through V05 now create the execution names directly,
  and V06 records itself and does nothing. Both paths end at the same
  schema, which is what lets a developer with an existing
  `priv/repo/statifier_examples_dev.db` and a fresh clone run the same
  `mix ecto.migrate`.

  Its own migration with its own floor, for the reason every
  `statifier_persistence` migration here has one: every version before it
  has already run on every database this app has, so a version the package
  adds afterwards is picked up by a migration of its own rather than by
  widening one that is already recorded. The migration before this one is
  capped at `version: 5` in the same change, which is what leaves V06 to
  this one to apply.

  Both bounds are spelled, `from: 6` and `version: 6`, so the rollback
  covers exactly the span the migration covers. That matters more here than
  it did for V03: `down/1` skips V06's rename when a rollback continues on
  below version 6, because the tables are then dropped under their new
  names, and runs it when 6 is the last step - so a `down` that started
  from the newest version the package knew would roll this app's V06 back
  twice, once from here and once from wherever the rollback began.

  Order at deploy runs the other way from V05's. The code has to be on the
  new names before the tables are, not after: `StatifierExamples.Persistence`
  implements the package's renamed adapter callbacks
  (`insert_execution/2` and the rest), and the generated schema module it
  reads through is now `StatifierExamples.Persistence.Execution` over the
  `statifier_executions` table. A database left at V05 running that code
  selects a table that does not exist. This app deploys nowhere, so the
  pair lands in one change; a host that does should read ADR-0011's own
  note on it rather than this one.
  """

  use Ecto.Migration

  def up,
    do:
      StatifierPersistence.Ecto.Migrations.up(
        for: StatifierExamples.Persistence,
        from: 6,
        version: 6
      )

  def down,
    do:
      StatifierPersistence.Ecto.Migrations.down(
        for: StatifierExamples.Persistence,
        from: 6,
        version: 6
      )
end
