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

  alias Riddler.Journey.Scope
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.Onboarding
  alias StatifierExamples.Persistence
  alias StatifierExamples.Signup.Journey
  alias StatifierPersistence.Execution.Linkage
  alias StatifierPersistence.{Executions, Storage}

  @path "/signup-journey?path=branch_onboarding"
  @riverside %{"kind" => "branch", "id" => "riverside"}

  # The onboarding is a branch library's, and this app has no sign-in:
  # every test here puts the riverside branch's librarian in its session,
  # and a test of a refusal builds its own connection.
  setup %{conn: conn} do
    {:ok, conn: init_test_session(conn, librarian_of: "riverside")}
  end

  defp execution_count do
    %{rows: [[count]]} =
      StatifierExamples.Repo.query!("SELECT count(*) FROM statifier_executions")

    count
  end

  # The one active child of the onboarding execution `execution_id`.
  defp active_child(execution_id) do
    {:ok, store} = Storage.new(Persistence, [])
    {:ok, [child]} = Executions.active_children(store, execution_id)
    child.execution_id
  end

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
    {:ok, riverside} = Scope.new("branch", "riverside")

    {:ok, execution_id} =
      Journey.start(
        "onboarding-page-#{System.unique_integer([:positive])}",
        Onboarding.options() ++ [scope: riverside]
      )

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

  # THE INHERITED SCOPE. The onboarding is started under the librarian's
  # branch scope, and the setup it runs as a durable child carries the same
  # scope, copied by the driver when it created the child.
  #
  # Sabotage (run): dropped `inherited_metadata_keys:` from
  # `Durable.driver/1`. The child recorded no scope, `Durable.scope/1`
  # answered `{:ok, nil}` for it and this went red.
  test "a setup the onboarding runs carries the onboarding's branch scope", %{conn: conn} do
    {_live, execution_id} = picked(conn, ["bdoc_catalogue_sync"])
    child_id = active_child(execution_id)

    assert child_id != execution_id
    assert {:ok, @riverside} = Durable.scope(execution_id)
    assert {:ok, @riverside} = Durable.scope(child_id)

    {:ok, store} = Storage.new(Persistence, [])
    {:ok, child} = Storage.fetch_execution(store, child_id)
    assert child.metadata["scope"] == @riverside
  end

  # THE REFUSAL. A librarian of another branch, and a visitor who is no
  # librarian, are not members of the riverside branch's scope: each sees
  # the one refusal and nothing of the Journey.
  #
  # Sabotage (run): made `JourneyAccess.member?/2` answer `true` for every
  # scope. The other branch's librarian was drawn the setup's screen and
  # this went red on the refusal.
  #
  # Sabotage (run): made `load/2` draw any reason a stored execution
  # cannot be drawn without asking membership. The setup named by its own
  # id drew its reason to the outsider and this went red on the refusal.
  test "a visitor outside the branch's scope sees the one refusal and nothing else", %{
    conn: conn
  } do
    {_live, execution_id} = picked(conn, ["bdoc_catalogue_sync"])
    url = "#{@path}&execution=#{execution_id}"

    for outsider <- [
          init_test_session(build_conn(), librarian_of: "hillside"),
          build_conn()
        ] do
      {:ok, live, html} = live(outsider, url)

      assert has_element?(live, "#journey-refused[data-riddler-refused]")
      assert html =~ "There is nothing to show here."
      refute has_element?(live, "#journey form")
      refute has_element?(live, "#execution-id")
      refute has_element?(live, "#collected")
      refute html =~ execution_id

      # The setup itself, named by its own id, is refused against the
      # scope it inherited.
      child_id = active_child(execution_id)
      {:ok, child, child_html} = live(outsider, "#{@path}&execution=#{child_id}")

      assert has_element?(child, "#journey-refused[data-riddler-refused]")
      refute has_element?(child, "#journey-error")
      refute child_html =~ child_id
    end
  end

  # Sabotage (run): made the page start the onboarding under the riverside
  # branch scope without asking the access module. The page still drew the
  # refusal, since it asks again before it draws, but an execution was
  # started and this went red on the count.
  test "a visitor who is no librarian is refused Start on the onboarding" do
    {:ok, live, _html} = live(build_conn(), @path)
    before = execution_count()

    live |> element("#start-journey") |> render_click()

    assert has_element?(live, "#journey-refused[data-riddler-refused]")
    refute has_element?(live, "#journey form")
    assert execution_count() == before
  end
end
