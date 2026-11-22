defmodule StatifierExamplesWeb.SettingsLiveTest do
  @moduledoc """
  `/settings` drawn and pressed: the three branch library setups listed,
  each started alone as a durable Journey and walked on the Journey page,
  with Back between its steps.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Library.Setups
  alias StatifierExamples.Signup.Journey

  # Each setup's first two steps: the first screen's continue button, what
  # it carries, and the second screen's continue button.
  @first_steps %{
    "catalogue_sync" =>
      {"#catalogue_source_continue", %{"catalogue_feed" => "branch_export"},
       "#catalogue_schedule_continue"},
    "reading_list_import" =>
      {"#reading_list_source_continue", %{"reading_list_format" => "booklist_link"},
       "#reading_list_term_continue"},
    "card_reader_setup" =>
      {"#reader_model_continue", %{"reader_kind" => "self_checkout"}, "#reader_location_continue"}
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
      refute has_element?(journey, "#journey-back")
      refute has_element?(journey, "#journey-error")
    end
  end

  # Sabotage: made the Journey page send `"back" => "true"`, a string.
  # Riddler decoded it as a submit, the page stayed on the second step and
  # this went red. Reverted from a copy.
  test "each setup's page offers Back between its steps", %{conn: conn} do
    for {key, {first_button, press, second_button}} <- @first_steps do
      journey = started(conn, key)

      journey |> form("#journey-responses", responses: press) |> render_change()
      journey |> element(first_button) |> render_click()

      assert has_element?(journey, second_button), "#{key} did not move on"
      assert has_element?(journey, "#journey-back"), "#{key} offers no Back"

      journey |> element("#journey-back") |> render_click()

      assert has_element?(journey, first_button), "#{key} did not go back"
      refute has_element?(journey, "#journey-back")
      refute has_element?(journey, "#journey-error")
    end
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
