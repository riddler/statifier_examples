defmodule StatifierExamplesWeb.RegistrationJourneyLiveTest do
  @moduledoc """
  `/signup-journey?path=patron_registration`: the patron registration the
  screen editor's document authors, filled in and finished on the Journey
  page, through a screen that asks a boolean question and a many-choice
  question.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts.Durable

  @path "/signup-journey?path=patron_registration"

  @details %{
    "first_name" => "Rosa",
    "email" => "rosa@example.com",
    "age" => "34",
    "riddler-password" => %{"library_pin" => "4321"}
  }

  defp key(key), do: ~s([data-riddler-key="#{key}"])

  # Presses the button keyed `key` with the form's values and `values`: a
  # secret question's input carries no value, so a PIN is typed into the
  # submit itself.
  defp press(live, key, values \\ %{}) do
    live
    |> form("#journey form", values)
    |> put_submitter("button" <> key(key))
    |> render_submit()

    render(live)
  end

  defp on_card_screen(conn) do
    {:ok, live, _html} = live(conn, @path)
    refute has_element?(live, "#journey-error")
    live |> element("#start-journey") |> render_click()

    press(live, "details_continue", @details)
    assert has_element?(live, key("lending_rules"))

    live
  end

  # The component types the ticked box as `true` before the host sees it,
  # which riddler's check of a boolean question requires.
  #
  # Sabotage (run): made `StatifierExamplesWeb.JourneyHost.submit/2` hand
  # `Signup.Journey` every boolean response as the string it was posted
  # as. Riddler refused the lending rules answer, the page drew its
  # finding, the execution stayed on the card screen and this went red.
  # Restored from a copy.
  test "a step with a boolean question is completed, and the Journey finishes", %{conn: conn} do
    live = on_card_screen(conn)

    live
    |> form("#journey form", %{
      "card_type" => "student",
      "interests" => ["fiction", "audiobooks"],
      "lending_rules" => "true"
    })
    |> render_change()

    press(live, "card_finish")

    refute has_element?(live, "[data-riddler-finding]")
    assert has_element?(live, "#journey-finished", "The execution finished: done.")
    assert render(live) =~ "&quot;lending_rules&quot; =&gt; true"

    assert render(live) =~
             "&quot;interests&quot; =&gt; [&quot;fiction&quot;, &quot;audiobooks&quot;]"
  end

  test "an unticked boolean question it requires is refused beside the question", %{conn: conn} do
    live = on_card_screen(conn)

    live |> form("#journey form", %{"card_type" => "student"}) |> render_change()
    press(live, "card_finish")

    assert has_element?(live, "#journey-element-lending_rules-finding-1")
    assert has_element?(live, key("card_finish"))
    refute has_element?(live, "#journey-done")
  end

  # THE PATRON SCOPE. A registration starts under the patron scope the
  # visitor's own session id names, the patron it is about to create, and
  # a visitor of another session is a member of no such scope.
  #
  # Sabotage (run): made `JourneyAccess.scopes/1` add the patron scope
  # `"P-1001"` to every actor's. The second session was drawn the
  # registration and this went red on the refusal.
  test "a registration runs under its visitor's patron scope, and no other visitor sees it", %{
    conn: conn
  } do
    {:ok, live, _html} = live(init_test_session(conn, visitor: "P-1001"), @path)
    live |> element("#start-journey") |> render_click()
    {:ok, %{query: query}} = live |> assert_patch() |> URI.new()
    %{"execution" => execution_id} = URI.decode_query(query)

    assert {:ok, %{"kind" => "patron", "id" => "P-1001"}} = Durable.scope(execution_id)

    url = "#{@path}&execution=#{execution_id}"
    {:ok, other, _html} = live(init_test_session(build_conn(), visitor: "P-2002"), url)

    assert has_element?(other, "#journey-refused[data-riddler-refused]")
    refute has_element?(other, "#journey form")

    {:ok, again, _html} = live(init_test_session(build_conn(), visitor: "P-1001"), url)
    assert has_element?(again, key("details_continue"))
  end
end
