defmodule StatifierExamples.Repo.Migrations.RenameInviteOutcomeExecutionColumns do
  @moduledoc """
  The data plane's own table follows the engine's noun (se-20j).

  `invite_outcomes` is this app's table and the engine has never heard of
  it, so nothing upstream forces this rename. What forces it is that both
  columns hold a `statifier_persistence` execution id and nothing else:
  `run_id` is the chunk child's own execution, so a reader with a row can
  open the execution that wrote it, and `promoted_run_id` is the execution
  a waiting invitee was given. A host column that keeps calling an
  execution id a run id is exactly the per-host carve-out rule ADR-0011
  changed the name to stop hosts from having to write, and this app is the
  reference embedder for it.

  A rename rather than a rewrite of
  `20260905180001_create_invite_outcomes.exs`: that migration has already
  run on every database this app has, so editing it would move a fresh
  clone and leave everything else where it was.
  """

  use Ecto.Migration

  def change do
    rename(table(:invite_outcomes), :run_id, to: :execution_id)
    rename(table(:invite_outcomes), :promoted_run_id, to: :promoted_execution_id)
  end
end
