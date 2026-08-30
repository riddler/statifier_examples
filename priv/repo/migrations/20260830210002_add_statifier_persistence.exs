defmodule StatifierExamples.Repo.Migrations.AddStatifierPersistence do
  @moduledoc """
  `statifier_persistence`'s own tables, delegated to its versioned
  migrations helper so the DDL cannot drift from the schemas
  `StatifierExamples.Persistence` generates.

  The call takes every version the package knows, V02's `metadata`
  column included. Taking V01 alone would leave the generated run schema
  selecting a column that does not exist - the schema carries `metadata`
  unconditionally - so "V01 only" is not a smaller version of this
  migration, it is a broken one. On SQLite the column is JSON text
  rather than `jsonb`: it round-trips, and the package's containment
  query over it does not run (see `StatifierExamples.Persistence`).
  """

  use Ecto.Migration

  def up, do: StatifierPersistence.Ecto.Migrations.up(for: StatifierExamples.Persistence)
  def down, do: StatifierPersistence.Ecto.Migrations.down(for: StatifierExamples.Persistence)
end
