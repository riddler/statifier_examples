defmodule StatifierExamples.MigrateWaitingTest do
  @moduledoc """
  `mix statifier_examples.migrate_waiting`, the path
  `docs/guides/migrating-waiting-executions.md` walks, against this app's own
  database and store.

  Not async: the batch takes every waiting execution on a chart, and the
  task steps through the application's named serialization strategy.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Mix.Tasks.StatifierExamples.MigrateWaiting
  alias StatifierExamples.{FirstWorkflow, Repo}
  alias StatifierPersistence.Storage

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: removed the `supports_content_hash_query?/1` delegation from
  # `StatifierExamples.Persistence`; the walk stopped at `:dry_run` with
  # `:content_hash_query_unsupported` and this went red. Reverted from a copy.
  test "walks the loans onto revision 2 and back, with every answer the guide quotes" do
    loans = ["loan_test_1", "loan_test_2"]

    assert {:ok, lines} = MigrateWaiting.walk(loans: loans)

    assert [
             "migrate waiting on statifier_persistence 0.21." <> _patch,
             "waiting      2 loan(s) on revision 1, sha256:" <> _old,
             "published    revision 2, sha256:" <> _new,
             "diff         breaking (5 unresolved) with the blocks mapping, " <>
               "breaking (0 unresolved) with the plan",
             "plan         the blocks mapping maps 16 state(s) and leaves 5 unmapped; " <>
               "the plan maps those to blk_on_loan",
             "dry run      blocks mapping alone: skipped 0, would_migrate 0, would_refuse 2; " <>
               "the plan: skipped 0, would_migrate 2, would_refuse 0",
             "applied      migrated 2, parked 0, refused 0, skipped 0",
             "drained      revision 1: active 0, needs_migration 0; " <>
               "revision 2: active 2, needs_migration 0",
             "timers       2 due-date timer(s) still scheduled, untouched by the move",
             "retire       revision 1: :chart_retirement_unsupported; " <>
               "this store cannot tombstone a chart",
             "rollback     the reverse plan, revision 2 to 1: " <>
               "skipped 0, would_migrate 2, would_refuse 0, " <>
               "then migrated 2, parked 0, refused 0, skipped 0",
             "tidied       cancelled the 2 loan(s) this run opened"
           ] = lines

    # The rollback put both loans back on revision 1 before the tidy.
    for loan <- loans do
      assert {:ok, %{status: :cancelled, content_hash: hash}} =
               Storage.fetch_execution(FirstWorkflow.store(), loan)

      assert ("waiting      2 loan(s) on revision 1, " <> hash <> ", each with its due-date timer") in lines
    end
  end

  # Sabotage: gave `StatifierExamples.Persistence` a
  # `supports_chart_retirement?/1` answering `true`; the `refute` went red.
  # Reverted from a copy.
  test "this app's store answers the content-hash query and carries no tombstone" do
    store = FirstWorkflow.store()

    assert Storage.content_hash_query_supported?(store)
    refute Storage.chart_retirement_supported?(store)
  end

  # Sabotage: made the task print none of the lines; this went red.
  # Reverted from a copy.
  test "the mix task prints every line the walk answers" do
    Mix.shell(Mix.Shell.Process)

    try do
      MigrateWaiting.run([])
    after
      Mix.shell(Mix.Shell.IO)
    end

    assert_received {:mix_shell, :info, ["migrate waiting on statifier_persistence " <> _vsn]}
    assert_received {:mix_shell, :info, ["tidied       cancelled the 2 loan(s) this run opened"]}
  end
end
