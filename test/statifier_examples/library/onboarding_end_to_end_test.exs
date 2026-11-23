defmodule StatifierExamples.Library.OnboardingEndToEndTest do
  @moduledoc """
  The branch onboarding Path end to end, durably, on SQLite: one test that
  walks a branch from its first screen to the closing one, with two
  integrations picked, and the two refusals a branch never sees on that
  walk - a checkpoint's and a misfit child's.

  ## What a restart is here

  Nothing holds an execution between steps: every call loads it from
  `StatifierExamples.Persistence` by its id. A restart is therefore a step
  taken by a process that has never seen the execution, holding nothing
  but the id. `restarted/2` checks the stored row is there and running,
  then takes the next step from a fresh `Task`.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.{Block, Document}
  alias StatifierExamples.Charts.{Durable, Execution}
  alias StatifierExamples.Library.{Onboarding, Setups}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screen}
  alias StatifierPersistence.Execution, as: Stored
  alias StatifierPersistence.Execution.Linkage
  alias StatifierPersistence.Storage

  @picked ["bdoc_catalogue_sync", "bdoc_card_reader_setup"]

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp store do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    store
  end

  defp stored(execution_id) do
    {:ok, record} = Storage.fetch_execution(store(), execution_id)
    Stored.from_record(record)
  end

  # The restart: the execution is read back from the store, and the next
  # step is taken by a process that never saw it.
  defp restarted(execution_id, step) do
    assert %Stored{status: :active} = stored(execution_id)
    step |> Task.async() |> Task.await()
  end

  # The execution the onboarding's focus is on, and the view it shows.
  defp focused(execution_id) do
    restarted(execution_id, fn ->
      {:ok, {target, opts}} = Onboarding.focus(execution_id)
      {:ok, view} = Journey.current(target, opts)
      {target, opts, view}
    end)
  end

  # A press on the screen the focus is on, taken by a fresh process.
  defp press(execution_id, outcome, responses) do
    assert {:ok, view} =
             restarted(execution_id, fn ->
               {:ok, {target, opts}} = Onboarding.focus(execution_id)
               Journey.submit(target, outcome, responses, opts)
             end)

    view
  end

  defp back(target, opts, screen),
    do: Journey.back(target, %{"screen" => screen, "back" => true}, opts)

  defp children(execution_id) do
    {:ok, children} =
      Storage.list_executions_by_metadata(store(), Linkage.parent_match(execution_id))

    children |> Enum.map(&Stored.from_record/1) |> Enum.sort_by(& &1.execution_id)
  end

  # The card-reader setup with a `core.checkpoint` after its location
  # step: a test-only Path, so the shipped setups stay as they are.
  defp with_checkpoint do
    {:ok, [screens: screens, path: %Document{root: root} = path]} =
      Setups.options("card_reader_setup")

    [model, location, test_card] = root.slots["body"]

    checkpoint = %Block{
      type: "core.checkpoint",
      id: "blk_cr_checkpoint",
      type_version: 1,
      config: %{},
      slots: %{}
    }

    body = [model, location, checkpoint, test_card]

    [
      screens: screens,
      path: %Document{
        path
        | id: "bdoc_card_reader_setup_checkpoint",
          root: %{root | slots: %{"body" => body}}
      }
    ]
  end

  # The onboarding's pick and loop with a subchart declaring `synced`
  # where every child declares `done`: a test-only Path whose child misfits.
  # It is not the onboarding, so its children resolve from the shipped
  # fixture list, whose library loan declares the one root outcome `done`.
  defp misfit do
    %Document{root: root} = onboarding = Onboarding.document()
    [_branch, pick, %Block{slots: %{"body" => [setup]}} = each, _finish] = root.slots["body"]
    setup = %{setup | config: Map.put(setup.config, "outcomes", "synced")}
    each = %{each | slots: %{"body" => [setup]}}

    %Document{
      onboarding
      | id: "bdoc_branch_onboarding_misfit",
        root: %{root | slots: %{"body" => [pick, each]}}
    }
  end

  # Sabotage notes, one per mutation, each run and turned red on an
  # assertion, then reverted from a copy:
  # - `Onboarding.focus/1` always answering the onboarding execution
  #   itself: red on the focus after the pick naming the first child.
  # - `Journey.back_offered?/2` answering `true` for every position: red
  #   on the setup's first screen offering Back.
  # - `Durable.subchart_host/1` always answering `Charts.Subchart`: red on
  #   the pick's view, the onboarding not resting on a child.
  # - `Durable.rest/3` leaving out the settled position's fold: red on the
  #   catalogue sync's screen key after its first press.
  # - statifier_blocks' outcome fit judging no child undeclared (a
  #   dependency mutation, recompiled for the test env): red on the misfit
  #   parent having a child execution.
  # - statifier_blocks' trail compiler placing no clear on a
  #   `core.checkpoint` (a dependency mutation, recompiled for the test
  #   env): red on the screen past the checkpoint offering Back.
  test "a branch picks two integrations, goes back where it may, and finishes" do
    id = "onboarding-#{System.unique_integer([:positive])}"
    {:ok, ^id} = Journey.start(id, Onboarding.options())

    # Back across the onboarding's own screens.
    assert %{screen: %{key: "onboarding_integrations"}, back: true} =
             press(id, "branch_named", %{"branch_name" => "Riverside branch"})

    assert {^id, opts, _view} = focused(id)

    assert {:ok, %{screen: %{key: "onboarding_branch"}}} =
             back(id, opts, "onboarding_integrations")

    press(id, "branch_named", %{"branch_name" => "Riverside branch"})

    assert %{screen: nil, state: "waiting"} =
             press(id, "integrations_chosen", %{"integrations" => @picked})

    # The first pick runs as a child; its first step offers no Back, so
    # Back never crosses out of the setup, and the onboarding, resting on
    # the child, has no screen to go back from.
    first = Linkage.child_execution_id(id, "blk_bo_setup", 0)
    assert {^first, child_opts, view} = focused(id)
    assert %{screen: %{key: "catalogue_source"}, back: false} = view
    assert back(first, child_opts, "catalogue_source") == {:error, :back_not_offered}
    assert back(id, Onboarding.options(), "onboarding_integrations") == {:error, :not_on_a_screen}

    # Back within the setup.
    assert %{screen: %{key: "catalogue_schedule"}, back: true} =
             press(id, "feed_chosen", %{"catalogue_feed" => "union_catalogue"})

    assert {^first, child_opts, _view} = focused(id)

    assert {:ok, %{screen: %{key: "catalogue_source"}}} =
             back(first, child_opts, "catalogue_schedule")

    assert %{screen: %{key: "catalogue_schedule"}} =
             press(id, "feed_chosen", %{"catalogue_feed" => "union_catalogue"})

    press(id, "schedule_chosen", %{"sync_schedule" => "nightly"})
    press(id, "sync_confirmed", %{"sync_contact_email" => "desk@example.com"})

    # The second pick, a child of a later pass.
    assert {second, _opts, view} = focused(id)
    assert String.starts_with?(second, first <> "@")
    assert %{screen: %{key: "reader_model"}, back: false} = view

    press(id, "model_chosen", %{"reader_kind" => "desk_reader"})
    press(id, "location_given", %{"reader_location" => "Front desk"})
    press(id, "test_reported", %{"reader_test_result" => "card_read"})

    # Past the loop: the closing screen offers no Back into a setup.
    assert {^id, opts, view} = focused(id)
    assert %{screen: %{key: "onboarding_finished"}, back: false} = view
    assert back(id, opts, "onboarding_finished") == {:error, :back_not_offered}

    assert %{state: "done"} = press(id, "onboarding_confirmed", %{})
    assert %Stored{status: :completed} = stored(id)

    # Each picked setup ran once, in the order picked, and finished with
    # the outcome the subchart declares.
    assert [
             %Stored{execution_id: ^first, status: :completed, donedata: %{"outcome" => "done"}},
             %Stored{execution_id: ^second, status: :completed, donedata: %{"outcome" => "done"}}
           ] = children(id)

    # A checkpoint is honoured: past it, Back is neither offered nor taken.
    checkpointed = "checkpoint-#{System.unique_integer([:positive])}"
    opts = with_checkpoint()
    {:ok, ^checkpointed} = Journey.start(checkpointed, opts)

    model = %{"reader_kind" => "desk_reader"}
    assert {:ok, %{back: true}} = Journey.submit(checkpointed, "model_chosen", model, opts)

    # Before it, Back is taken.
    assert {:ok, %{screen: %{key: "reader_model"}}} = back(checkpointed, opts, "reader_place")
    assert {:ok, %{back: true}} = Journey.submit(checkpointed, "model_chosen", model, opts)

    assert {:ok, %{screen: %{key: "reader_test"}, back: false}} =
             restarted(checkpointed, fn ->
               Journey.submit(
                 checkpointed,
                 "location_given",
                 %{"reader_location" => "Front desk"},
                 opts
               )
             end)

    assert back(checkpointed, opts, "reader_test") == {:error, :back_not_offered}

    # A misfit child is refused at child creation: no child execution.
    misfit_id = "misfit-#{System.unique_integer([:positive])}"
    document = misfit()
    {:ok, ^misfit_id} = Journey.start(misfit_id, screens: Onboarding.screens(), path: document)

    assert {:ok, {_durable, moved}} =
             restarted(misfit_id, fn ->
               {:ok, compiled} = Durable.compile(document, [])
               {:ok, {durable, run}} = Durable.resume(compiled, document, misfit_id)

               Durable.send_event(
                 durable,
                 run,
                 Screen.outcome_event("integrations_chosen"),
                 %{"integrations" => ["bdoc_library_loan"]}
               )
             end)

    assert children(misfit_id) == []

    assert Enum.any?(
             Execution.entries(moved),
             &(&1.label == "Child chart refused" and &1.detail =~ "child_outcome_undeclared")
           )
  end
end
