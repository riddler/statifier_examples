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
  alias StatifierPersistence.{Driver, Storage}

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: made the walk expect one publish warning, then 15 mapped
  # states, then a :mapped class for the plan diff (three runs); each run
  # stopped the walk at that step and this went red. Reverted from a copy.
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

  # Sabotage: removed the `expect/3` check after the blocks-only dry run;
  # the walk went on past a preview of three loans and this went red.
  # Reverted from a copy.
  test "a batch that answers with other counts than the guide's stops the walk at its step" do
    assert {:ok, lines} = MigrateWaiting.walk(loans: ["loan_first_1", "loan_first_2"])
    ["waiting      2 loan(s) on revision 1, " <> rest] = Enum.filter(lines, &(&1 =~ ~r/^waiting/))
    [old_hash | _] = String.split(rest, ",")

    # A third loan waiting on revision 1 that this walk did not open: every
    # batch now answers `{:ok, report}` with three executions in it.
    store = FirstWorkflow.store()
    {:ok, chart} = Storage.fetch_chart(store, old_hash)
    {:ok, machine} = Statifier.compile(chart.chart_blob)

    assert {:ok, %{status: :active}, _state} =
             store |> FirstWorkflow.driver(machine) |> Driver.create("loan_not_this_run")

    assert {:error, :dry_run, {:unexpected, %{would_refuse: 3, would_migrate: 0}}} =
             MigrateWaiting.walk(loans: ["loan_second_1", "loan_second_2"])
  end

  # Sabotage: made `expect/3` answer `:ok` whatever the counts; this went
  # red on its first row. Reverted from a copy.
  test "each step is held to the counts the guide shows for it" do
    report = fn counts -> %{from: "a", to: "b", dry_run: false, results: [], counts: counts} end

    for {step, answer, expected} <- [
          {:published, %{warnings: 1}, %{warnings: 0}},
          {:mapped, %{kept: 21, unmapped: 0}, %{kept: 16, unmapped: 5}},
          {:diff, %{class: :mapped, unresolved: 0}, %{class: :breaking, unresolved: 0}},
          {:diff, %{class: :breaking, unresolved: 4}, %{class: :breaking, unresolved: 5}},
          {:dry_run, report.(%{would_migrate: 1, would_refuse: 1, skipped: 0}),
           %{would_migrate: 0, would_refuse: 2}},
          {:dry_run, report.(%{would_migrate: 1, would_refuse: 1, skipped: 0}),
           %{would_migrate: 2, would_refuse: 0}},
          {:applied, report.(%{migrated: 0, refused: 2, parked: 0, skipped: 0}),
           %{migrated: 2, refused: 0, parked: 0}},
          {:drained, %{active: 1, needs_migration: 0, completed: 0},
           %{active: 0, needs_migration: 0}},
          {:drained, %{active: 2, needs_migration: 1, completed: 0},
           %{active: 2, needs_migration: 0}},
          {:timers, %{scheduled: 1}, %{scheduled: 2}},
          {:rollback, report.(%{migrated: 0, refused: 0, parked: 2, skipped: 0}),
           %{migrated: 2, refused: 0, parked: 0}}
        ] do
      counts = Map.get(answer, :counts, answer)

      assert {:error, ^step, {:unexpected, ^counts}} =
               MigrateWaiting.expect(step, answer, expected)
    end

    assert :ok =
             MigrateWaiting.expect(
               :applied,
               report.(%{migrated: 2, refused: 0, parked: 0, skipped: 0}),
               %{migrated: 2, refused: 0, parked: 0}
             )
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
