defmodule StatifierExamples.FormPostTest do
  @moduledoc """
  The form-post first-workflow recipe, run the way
  `mix statifier_examples.first_workflow_form_post` runs it: every step of
  `docs/guides/first-workflow-form-post.md` against this app's own
  database and Oban instance, which the test configuration keeps in
  `testing: :manual`, so every job here runs because the recipe drained
  its queues.

  Not async: the recipe drains the shared Oban instance and steps through
  the application's named serialization strategy.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Mix.Tasks.StatifierExamples.FirstWorkflowFormPost
  alias StatifierExamples.{FormPost, Repo}
  alias StatifierExamples.FormPost.ScreenApplication

  setup do
    :ok = Sandbox.checkout(Repo)
    on_exit(fn -> Application.delete_env(:statifier_examples, ScreenApplication) end)
  end

  # Sabotage: made the recipe's wait skip `Drain.run/1`; the jobs never
  # ran and this went red with the recipe naming `routed`. Putting the
  # posted values among the job arguments `ids_only` reads went red at
  # `ids_only`; dropping the area from the words line went red on the
  # `routed` line. Each reverted from a copy.
  test "runs the whole recipe, and the engine holds ids and words only" do
    assert {:ok, lines} = FormPost.run(idempotency_key: "form-test")

    assert [
             "first workflow from a form post on statifier_router 0.12." <> _pins,
             "registered   chart " <> _hash,
             "stored       application " <> stored,
             "repeat       the same client key again: application " <> _repeat,
             "routed       execution " <> routed,
             "sent         patron_system RPL-P-" <> _sent,
             "duplicate    the intake routing run again: duplicate; " <>
               "the ledger reads created_and_delivered, duplicate",
             "ids only     no posted value in the datamodel, input log, job arguments",
             "screened out application " <> screened,
             "trace        the input log, oldest first:"
             | trace
           ] = lines

    assert stored =~ "one intake job, its arguments the id alone"
    assert routed =~ "completed: screen ok, sort both, area inside"
    assert screened =~ "screen screened_out, sort unsorted, area check_at_desk"
    assert screened =~ "status screened_out"

    # The event the intake job routed carries the id alone; the three
    # answers after it are the steps' words.
    assert [~s(  0 step application.received %{"application_id" => ) <> _id | answers] = trace
    assert ["\"ok\"", "\"both\"", "\"inside\""] == Enum.map(answers, &List.last(String.split(&1)))
  end

  # Sabotage: made a failed step answer `:unexpected` instead of its own
  # name; this went red. Reverted from a copy.
  test "a step that does not hold is named" do
    Application.put_env(:statifier_examples, ScreenApplication, fail: true)

    assert {:error, :routed, _reason} = FormPost.run()
  end

  # Sabotage: made the task print none of the lines; this went red.
  # Reverted from a copy.
  test "the mix task prints every line the recipe answers" do
    Mix.shell(Mix.Shell.Process)

    try do
      FirstWorkflowFormPost.run([])
    after
      Mix.shell(Mix.Shell.IO)
    end

    assert_received {:mix_shell, :info, ["first workflow from a form post on " <> _pins]}
    assert_received {:mix_shell, :info, ["trace        the input log, oldest first:"]}
  end

  # Sabotage: made the task print the failure with `Mix.shell().error/1`
  # instead of raising; this went red. Reverted from a copy.
  test "the mix task exits non-zero naming the step that did not hold" do
    Application.put_env(:statifier_examples, ScreenApplication, fail: true)

    assert_raise Mix.Error, ~r/first workflow form post: step routed did not hold/, fn ->
      FirstWorkflowFormPost.run([])
    end
  end
end
