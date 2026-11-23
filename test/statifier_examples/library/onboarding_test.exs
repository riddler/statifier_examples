defmodule StatifierExamples.Library.OnboardingTest do
  @moduledoc """
  The branch onboarding Path: the pick, one durable child per picked setup
  named from data, the allow-list that resolves those children, and
  `focus/1`, which says which execution a press goes to.

  Not async: durable executions step through the application's named
  `StatifierExamples.Charts.ExecutionLock`.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Statifier.Machine.Identity
  alias StatifierBlocks.Compiled
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Execution, Subchart}
  alias StatifierExamples.Library.{Onboarding, Setups}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Journey, Screen}
  alias StatifierPersistence.Execution.Linkage
  alias StatifierPersistence.{Executions, Storage}

  @catalogue_sync [
    {"feed_chosen", %{"catalogue_feed" => "union_catalogue"}},
    {"schedule_chosen", %{"sync_schedule" => "nightly"}},
    {"sync_confirmed", %{"sync_contact_email" => "desk@example.com"}}
  ]

  @card_reader_setup [
    {"model_chosen", %{"reader_kind" => "desk_reader"}},
    {"location_given", %{"reader_location" => "Front desk"}},
    {"test_reported", %{"reader_test_result" => "card_read"}}
  ]

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  defp start do
    {:ok, execution_id} =
      Journey.start("onboarding-#{System.unique_integer([:positive])}", Onboarding.options())

    execution_id
  end

  # Presses the screen the onboarding execution's focus is on.
  defp press(execution_id, outcome, responses) do
    {:ok, {target, opts}} = Onboarding.focus(execution_id)
    Journey.submit(target, outcome, responses, opts)
  end

  defp presses(execution_id, steps) do
    for {outcome, responses} <- steps,
        do: assert({:ok, _view} = press(execution_id, outcome, responses))
  end

  defp focused_view(execution_id) do
    assert {:ok, {target, opts}} = Onboarding.focus(execution_id)
    assert {:ok, view} = Journey.current(target, opts)
    {target, view}
  end

  defp pick(execution_id, ids) do
    {:ok, _view} = press(execution_id, "branch_named", %{"branch_name" => "Riverside branch"})
    press(execution_id, "integrations_chosen", %{"integrations" => ids})
  end

  defp store do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    store
  end

  defp children(execution_id) do
    {:ok, children} = Executions.active_children(store(), execution_id)
    children
  end

  defp every_child(execution_id) do
    {:ok, children} =
      Storage.list_executions_by_metadata(store(), Linkage.parent_match(execution_id))

    children
  end

  defp status(execution_id) do
    {:ok, execution} = Storage.fetch_execution(store(), execution_id)
    execution.status
  end

  defp first_child(execution_id), do: Linkage.child_execution_id(execution_id, "blk_bo_setup", 0)

  describe "resolve_chart/2, the allow-list" do
    # Sabotage: made the binary clause answer `{:ok, document}` uncompiled
    # for every setup. This test went red on the `%Compiled{}` match.
    test "answers each of the three setups by its document id, compiled as a child" do
      for key <- Setups.keys() do
        {:ok, document} = Setups.document(key)

        assert {:ok, %Compiled{interface: %{declared_outcomes: ["done"]}}} =
                 Onboarding.resolve_chart(document.id, %{})
      end
    end

    # Sabotage: made the binary clause fall back to the shipped fixture
    # list (`StatifierExamples.Charts.Subchart.resolve_chart/2`) on
    # `:error`. This test went red on the first shipped fixture's id.
    test "refuses every other id, a shipped fixture's included" do
      shipped = Enum.map(Charts.fixtures(), & &1.document.id)

      for id <- ["bdoc_unknown_setup", Onboarding.document().id | shipped] do
        assert Onboarding.resolve_chart(id, %{}) == :error
      end

      assert Onboarding.resolve_chart(nil, %{}) == :error
      assert Onboarding.resolve_chart(["bdoc_catalogue_sync"], %{}) == :error
    end
  end

  describe "parent?/1" do
    # Sabotage: made `parent?/1` answer `true` for every hash. This test went
    # red on the catalogue setup's hash.
    test "is true for the onboarding Path's own compile and false for any other chart" do
      {:ok, %Compiled{scxml: scxml}} = Durable.compile(Onboarding.document(), [])
      assert Onboarding.parent?(Identity.of_source(scxml).content_hash)

      {:ok, setup} = Setups.document("catalogue_sync")
      {:ok, %Compiled{scxml: other}} = Subchart.child_compile(setup)
      refute Onboarding.parent?(Identity.of_source(other).content_hash)
    end
  end

  describe "the pick and the children it starts" do
    # Sabotage: made `focus/1` always answer the onboarding execution itself.
    # This test went red: the focused view was the onboarding's, not the
    # catalogue setup's first screen.
    test "the first pick runs as a durable child, and the page's focus is on it" do
      id = start()
      {:ok, {^id, _opts}} = Onboarding.focus(id)

      {:ok, _view} = pick(id, ["bdoc_catalogue_sync", "bdoc_card_reader_setup"])

      assert [%{execution_id: child_id, status: :active}] = children(id)
      assert child_id == first_child(id)

      {target, view} = focused_view(id)
      assert target == child_id
      assert view.screen.key == "catalogue_source"
      refute view.back
    end

    # Sabotage: reverted `Durable`'s feed id to `child_execution_id/3` with
    # index 0 on the drive's own execution id. This test went red: no feed
    # row named the second pass's child.
    test "a finished setup starts the next pick's child under the later pass's id" do
      id = start()
      {:ok, _view} = pick(id, ["bdoc_catalogue_sync", "bdoc_card_reader_setup"])
      first = first_child(id)

      [{outcome, responses} | rest] = Enum.reverse(@catalogue_sync)
      presses(id, Enum.reverse(rest))

      {:ok, %Compiled{} = compiled} = Onboarding.resolve_chart("bdoc_catalogue_sync", %{})
      {:ok, setup} = Setups.fetch_document("bdoc_catalogue_sync")
      {:ok, {durable, run}} = Durable.resume(compiled, setup, first)

      assert {:ok, {_durable, moved}} =
               Durable.send_event(durable, run, Screen.outcome_event(outcome), responses)

      assert status(first) == :completed
      assert [%{execution_id: second}] = children(id)
      assert String.starts_with?(second, first <> "@")

      assert Enum.any?(Execution.entries(moved), fn entry ->
               entry.label == "Child chart started" and entry.source == second
             end)

      {^second, view} = focused_view(id)
      assert view.screen.key == "reader_model"
    end

    # Sabotage: dropped the `child: true` option `focus/1` adds. This test
    # went red: the resume of the child was refused by the identity guard.
    test "both picks run, each a child, and the onboarding moves to its closing screen" do
      id = start()
      {:ok, _view} = pick(id, ["bdoc_catalogue_sync", "bdoc_card_reader_setup"])

      presses(id, @catalogue_sync)
      presses(id, @card_reader_setup)

      assert children(id) == []
      assert id |> every_child() |> Enum.map(& &1.status) == [:completed, :completed]

      {^id, view} = focused_view(id)
      assert view.screen.key == "onboarding_finished"

      {:ok, done} = press(id, "onboarding_confirmed", %{})
      assert done.state == "done"
    end
  end

  describe "a trace of another execution" do
    # Sabotage: took `Execution.absorb/2`'s clause for a trace of another
    # execution out. The child's configuration marked the onboarding
    # reading's blocks active and this went red on the equality.
    test "leaves the reading it reaches as it was" do
      id = start()
      {:ok, _view} = pick(id, ["bdoc_card_reader_setup"])

      onboarding = Onboarding.document()
      {:ok, compiled} = Durable.compile(onboarding, [])
      {:ok, {_parent, run}} = Durable.resume(compiled, onboarding, id)

      {:ok, %Compiled{} = child_compiled} =
        Onboarding.resolve_chart("bdoc_card_reader_setup", %{})

      {:ok, setup} = Setups.fetch_document("bdoc_card_reader_setup")
      {:ok, {child, _child_run}} = Durable.resume(child_compiled, setup, first_child(id))

      stable = %Statifier.Effect.Trace.MacrostepStable{
        configuration: child.machine_state.configuration,
        macrostep: child.machine_state.macrostep,
        microstep: child.machine_state.microstep,
        round: child.machine_state.round
      }

      assert Execution.absorb(run, {:effect_of, first_child(id), nil, {:trace, stable}}) == run
    end
  end

  describe "Back" do
    # Sabotage: took the settled position's fold out of `Durable.rest/3`.
    # This test went red: the child's view after Back still named the
    # screen it was resumed on.
    test "goes back between a setup's own steps and never out of the setup" do
      id = start()
      {:ok, _view} = pick(id, ["bdoc_card_reader_setup"])
      presses(id, Enum.take(@card_reader_setup, 1))

      {target, view} = focused_view(id)
      assert view.screen.key == "reader_place"
      assert view.back

      {:ok, opts} = Setups.options("card_reader_setup")

      {:ok, back} =
        Journey.back(target, %{"screen" => "reader_place", "back" => true}, opts ++ [child: true])

      assert back.screen.key == "reader_model"
      refute back.back
    end

    # Sabotage: put a `core.checkpoint` between the onboarding's branch step
    # and its pick step in the fixture. This test went red: Back was not
    # offered on the pick screen.
    test "goes back between the onboarding's own screens" do
      id = start()
      {:ok, view} = press(id, "branch_named", %{"branch_name" => "Riverside branch"})
      assert view.screen.key == "onboarding_integrations"
      assert view.back

      {:ok, back} =
        Journey.back(
          id,
          %{"screen" => "onboarding_integrations", "back" => true},
          Onboarding.options()
        )

      assert back.screen.key == "onboarding_branch"
    end
  end

  describe "a chart_from naming a document outside the three" do
    # Sabotage: made `resolve_chart/2` answer the catalogue setup for an id
    # it does not list. This test went red: a child execution was created.
    test "starts no child" do
      id = start()
      {:ok, _view} = press(id, "branch_named", %{"branch_name" => "Riverside branch"})

      {:ok, {durable, run}} =
        Durable.resume(
          elem(Durable.compile(Onboarding.document(), []), 1),
          Onboarding.document(),
          id
        )

      shipped = hd(Charts.fixtures()).document.id

      {:ok, {_durable, moved}} =
        Durable.send_event(
          durable,
          run,
          Screen.outcome_event("integrations_chosen"),
          %{"integrations" => [shipped]}
        )

      assert every_child(id) == []
      assert children(id) == []

      assert Enum.any?(Execution.entries(moved), &(&1.label == "Child chart refused"))
      refute Enum.any?(Execution.entries(moved), &(&1.label == "Child chart started"))
    end
  end
end
