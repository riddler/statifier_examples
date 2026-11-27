defmodule StatifierExamplesWeb.OnboardingJourneyLiveTest do
  @moduledoc """
  `/signup-journey?path=branch_onboarding`: the branch onboarding drawn,
  pressed and reloaded, with every setup the branch picked presented and
  pressed as the durable child it runs as.

  What is asserted here is only what the page adds over
  `StatifierExamples.Library.OnboardingTest`: that the page presents the
  active child's screen, routes its presses and its back requests to that
  child, and moves on to the next setup and the closing screen as each
  setup finishes.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Library.Onboarding
  alias StatifierExamples.Signup.Journey
  alias StatifierPersistence.Execution.Linkage

  @path "/signup-journey?path=branch_onboarding"

  defp started(conn) do
    {:ok, live, _html} = live(conn, @path)
    refute has_element?(live, "#journey-error")
    live |> element("#start-journey") |> render_click()
    {:ok, %{query: query}} = live |> assert_patch() |> URI.new()
    %{"execution" => execution_id} = URI.decode_query(query)

    {live, execution_id}
  end

  # Asserts the screen the button belongs to is the one on the page before
  # it answers, so a press that went to the wrong execution fails here on an
  # assertion rather than in the form helper.
  defp answer(live, responses, button) do
    assert has_element?(live, key(button))
    live |> form("#journey form", responses) |> render_change()
    press(live, button)
  end

  # An element of the screen RiddlerLiveView.Journey draws, by its key.
  defp key(key), do: ~s([data-riddler-key="#{key}"])

  # Presses the button keyed `key`: a submit of the component's form with
  # that button as its submitter, answering the page as drawn once the
  # press has landed.
  defp press(live, key) do
    live |> form("#journey form") |> put_submitter("button" <> key(key)) |> render_submit()
    render(live)
  end

  defp picked(conn, ids) do
    {live, execution_id} = started(conn)
    answer(live, %{"branch_name" => "Riverside branch"}, "onboarding_branch_continue")
    live |> form("#journey form", %{"integrations" => ids}) |> render_change()
    press(live, "onboarding_integrations_continue")

    {live, execution_id}
  end

  # Sabotage: made `path_options/1` answer `:error` for the onboarding key.
  # The page refused the Path and this went red. Reverted from a copy.
  test "the page runs the branch onboarding and starts on its first screen", %{conn: conn} do
    {live, _execution_id} = started(conn)

    assert has_element?(live, key("onboarding_branch_continue"))
    refute has_element?(live, "#presented-child")
    refute has_element?(live, "#journey-error")
  end

  # Sabotage: made `focus/2` answer the named execution with the page's
  # options for every Path. The page drew the onboarding resting on its
  # subchart, with no screen, and this went red. Reverted from a copy.
  test "a pick presents the first picked setup's screen, the child's own", %{conn: conn} do
    {live, execution_id} = picked(conn, ["bdoc_catalogue_sync", "bdoc_card_reader_setup"])

    child = Linkage.child_execution_id(execution_id, "blk_bo_setup", 0)
    assert has_element?(live, key("catalogue_source_continue"))
    assert has_element?(live, "#presented-child")
    assert has_element?(live, "#execution-id", child)
    refute has_element?(live, "[data-riddler-back]")
  end

  # Sabotage: made `target/1` answer the execution on the URL with the
  # page's options for every Path. The press went to the onboarding
  # execution, which was refused, and this went red. Reverted from a copy.
  test "presses go to the child, and a finished setup moves on to the next pick", %{conn: conn} do
    {live, _execution_id} = picked(conn, ["bdoc_catalogue_sync", "bdoc_card_reader_setup"])

    answer(live, %{"catalogue_feed" => "union_catalogue"}, "catalogue_source_continue")
    answer(live, %{"sync_schedule" => "nightly"}, "catalogue_schedule_continue")
    answer(live, %{"sync_contact_email" => "desk@example.com"}, "catalogue_start")

    assert has_element?(live, key("reader_model_continue"))
    assert has_element?(live, "#presented-child")
    refute has_element?(live, "#journey-error")
  end

  # Sabotage: dropped `refocus/1` from the outcome clause. After the pick
  # the page kept the onboarding's own view, resting on its subchart with
  # no screen, and this went red. Reverted from a copy.
  test "after the last pick finishes, the onboarding shows its closing screen", %{conn: conn} do
    {live, _execution_id} = picked(conn, ["bdoc_card_reader_setup"])

    answer(live, %{"reader_kind" => "desk_reader"}, "reader_model_continue")
    answer(live, %{"reader_location" => "Front desk"}, "reader_location_continue")
    answer(live, %{"reader_test_result" => "card_read"}, "reader_finish")

    assert has_element?(live, key("onboarding_finish"))
    refute has_element?(live, "#presented-child")

    press(live, "onboarding_finish")
    assert has_element?(live, "#journey-done")
  end

  # Sabotage: made the back clause send the back request to the execution
  # on the URL. It went to the onboarding execution, which rests on no
  # screen, and this went red. Reverted from a copy.
  test "Back inside a setup goes back between the setup's own steps", %{conn: conn} do
    {live, _execution_id} = picked(conn, ["bdoc_card_reader_setup"])

    answer(live, %{"reader_kind" => "desk_reader"}, "reader_model_continue")
    assert has_element?(live, "[data-riddler-back]")

    html = live |> element("[data-riddler-back]") |> render_click()

    assert has_element?(live, key("reader_model_continue"))
    refute has_element?(live, "[data-riddler-back]")
    refute has_element?(live, "#journey-error")
    assert html =~ "desk_reader"
  end

  # Sabotage: made `focus/2` answer the named execution with the page's
  # options for every Path. The reload presented the onboarding execution
  # resting on its subchart, with no screen, and this went red. Reverted
  # from a copy.
  test "a reload of the onboarding URL presents the running setup", %{conn: conn} do
    {:ok, execution_id} =
      Journey.start("onboarding-page-#{System.unique_integer([:positive])}", Onboarding.options())

    {:ok, _view} =
      Journey.submit(
        execution_id,
        "branch_named",
        %{"branch_name" => "Riverside branch"},
        Onboarding.options()
      )

    {:ok, _view} =
      Journey.submit(
        execution_id,
        "integrations_chosen",
        %{"integrations" => ["bdoc_reading_list_import"]},
        Onboarding.options()
      )

    {:ok, live, _html} = live(conn, "#{@path}&execution=#{execution_id}")

    assert has_element?(live, key("reading_list_source_continue"))
    assert has_element?(live, "#presented-child")
  end
end
