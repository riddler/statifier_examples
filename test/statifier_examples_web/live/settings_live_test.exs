defmodule StatifierExamplesWeb.SettingsLiveTest do
  @moduledoc """
  `/settings` drawn and pressed: the three branch library setups listed,
  each started alone as a durable Journey and walked on the Journey page,
  with Back between its steps.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.Setups
  alias StatifierExamples.Persistence
  alias StatifierExamples.Signup.Journey
  alias StatifierPersistence.Execution.Linkage
  alias StatifierPersistence.Storage

  # The page is a librarian's, and this app has no sign-in: every test here
  # but the refusal's puts the riverside branch's librarian in its session.
  setup %{conn: conn} do
    {:ok, conn: init_test_session(conn, librarian_of: "riverside")}
  end

  defp execution_count do
    %{rows: [[count]]} =
      StatifierExamples.Repo.query!("SELECT count(*) FROM statifier_executions")

    count
  end

  # Each setup's first two steps: the first screen's continue button, what
  # it carries, and the second screen's continue button.
  @first_steps %{
    "catalogue_sync" =>
      {~s([data-riddler-key="catalogue_source_continue"]), %{"catalogue_feed" => "branch_export"},
       ~s([data-riddler-key="catalogue_schedule_continue"])},
    "reading_list_import" =>
      {~s([data-riddler-key="reading_list_source_continue"]),
       %{"reading_list_format" => "booklist_link"},
       ~s([data-riddler-key="reading_list_term_continue"])},
    "card_reader_setup" =>
      {~s([data-riddler-key="reader_model_continue"]), %{"reader_kind" => "self_checkout"},
       ~s([data-riddler-key="reader_location_continue"])}
  }

  # Press a setup's Start and follow the navigation to the Journey page.
  defp started(conn, key) do
    {:ok, settings, _html} = live(conn, ~p"/settings")

    {:ok, journey, _html} =
      settings |> element("#start-#{key}") |> render_click() |> follow_redirect(conn)

    journey
  end

  # Sabotage: dropped the `:for` over `@setups` in the page's list. No
  # setup was drawn and this went red. Reverted from a copy.
  test "lists each setup with its name, its root outcomes and a Start", %{conn: conn} do
    {:ok, live, html} = live(conn, ~p"/settings")

    for key <- Setups.keys() do
      {:ok, document} = Setups.document(key)
      assert has_element?(live, "#setup-#{key}", document.metadata["name"])
      assert has_element?(live, "#setup-#{key} code", "done")
      assert has_element?(live, "#start-#{key}")
    end

    refute html =~ "settings-error"
  end

  # Sabotage: made the start clause navigate to the Journey page without
  # `path`. The URL named no setup and this went red. Reverted from a copy.
  #
  # Sabotage: made `path_options/1` on the Journey page answer `:error` for
  # every setup key. The page refused the setup, drew no first screen and
  # this went red. Reverted from a copy.
  test "Start starts the setup as a durable Journey on its first screen, with no Back", %{
    conn: conn
  } do
    for {key, {first_button, _press, _second}} <- @first_steps do
      {:ok, settings, _html} = live(conn, ~p"/settings")

      assert {:error, {:live_redirect, %{to: to}}} =
               settings |> element("#start-#{key}") |> render_click()

      %{query: query} = URI.parse(to)
      assert %{"path" => ^key, "execution" => execution_id} = URI.decode_query(query)

      {:ok, opts} = Setups.options(key)
      assert {:ok, %{state: "screen"}} = Journey.current(execution_id, opts)

      {:ok, journey, _html} = live(conn, to)
      assert has_element?(journey, first_button)
      refute has_element?(journey, "[data-riddler-back]")
      refute has_element?(journey, "#journey-error")
    end
  end

  # Sabotage: made the Journey page send `"back" => "true"`, a string.
  # Riddler decoded it as a submit, the page stayed on the second step and
  # this went red. Reverted from a copy.
  test "each setup's page offers Back between its steps", %{conn: conn} do
    for {key, {first_button, press, second_button}} <- @first_steps do
      journey = started(conn, key)

      journey |> form("#journey form", press) |> render_change()

      journey
      |> form("#journey form")
      |> put_submitter("button" <> first_button)
      |> render_submit()

      assert has_element?(journey, second_button), "#{key} did not move on"
      assert has_element?(journey, "[data-riddler-back]"), "#{key} offers no Back"

      journey |> element("[data-riddler-back]") |> render_click()

      assert has_element?(journey, first_button), "#{key} did not go back"
      refute has_element?(journey, "[data-riddler-back]")
      refute has_element?(journey, "#journey-error")
    end
  end

  # THE BRANCH SCOPE. A setup started here runs alone - a root execution,
  # no child of anything - and records the librarian's branch scope.
  #
  # Sabotage (run): made the page start the setup under the open scope
  # every visitor holds. The host refused a scope of the wrong kind, no
  # redirect came and this went red on the first match.
  test "Start starts the setup alone under the librarian's branch scope", %{conn: conn} do
    {:ok, settings, _html} = live(conn, ~p"/settings")

    assert {:error, {:live_redirect, %{to: to}}} =
             settings |> element("#start-catalogue_sync") |> render_click()

    %{"execution" => execution_id} = to |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert {:ok, %{"kind" => "branch", "id" => "riverside"}} = Durable.scope(execution_id)

    {:ok, store} = Storage.new(Persistence, [])
    {:ok, record} = Storage.fetch_execution(store, execution_id)
    refute Map.has_key?(record.metadata, Linkage.reserved_key())
  end

  # Sabotage (run): made the page start the setup under the riverside
  # branch scope without asking the access module. The setup started, the
  # page navigated away and this went red on the refute.
  test "a visitor who is no librarian is refused Start, and nothing is started" do
    {:ok, settings, _html} = live(build_conn(), ~p"/settings")
    before = execution_count()

    pressed = settings |> element("#start-catalogue_sync") |> render_click()

    refute match?({:error, {:live_redirect, _to}}, pressed)
    assert has_element?(settings, "#settings-refused[data-riddler-refused]")
    assert render(settings) =~ "There is nothing to show here."
    assert execution_count() == before
  end

  # Sabotage: made the start clause's `:error` branch leave the socket as
  # it was. No refusal was drawn and this went red. Reverted from a copy.
  test "a setup the list does not hold is refused and nothing is started", %{conn: conn} do
    {:ok, settings, _html} = live(conn, ~p"/settings")

    html = render_click(settings, "start", %{"setup" => "branch_closure"})

    assert html =~ "unknown_setup"
    assert has_element?(settings, "#settings-error")
  end
end
