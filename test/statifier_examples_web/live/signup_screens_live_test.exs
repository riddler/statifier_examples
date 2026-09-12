defmodule StatifierExamplesWeb.SignupScreensLiveTest do
  use StatifierExamplesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StatifierExamples.Signup.Screens
  alias StatifierExamplesWeb.SignupElements

  describe "the page" do
    test "renders the first screen by default", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/signup-screens")

      assert html =~ "Create your account"
      assert html =~ ~s(id="first_name")
      assert html =~ ~s(data-outcome="account_submitted")
    end

    test "?screen= picks a screen", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/signup-screens?screen=confirm")

      assert html =~ "Confirm and finish"
    end

    # Sabotage: dropping `coerce/1` leaves the seat count a string,
    # `answers.seats > 1` no longer evaluates to true, and the business
    # button never appears.
    test "answering a question reveals the nodes its condition guards", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-screens?screen=plan")

      refute render(live) =~ ~s(data-outcome="business_chosen")

      html =
        live
        |> element("form")
        |> render_change(%{"answers" => %{"seats" => "5"}})

      assert html =~ ~s(data-outcome="business_chosen")
      refute html =~ ~s(data-outcome="personal_chosen")
    end

    test "a button reports the outcome it declares", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-screens")

      refute has_element?(live, "#last-outcome")

      live |> element("#account_continue") |> render_click()

      assert has_element?(live, "#last-outcome code", "account_submitted")
    end
  end

  describe "the components" do
    test "a heading renders at its level" do
      node = %{"type" => "heading", "key" => "h", "level" => 2, "text" => "Sub"}

      assert render_component(&SignupElements.element/1, node: node) =~ "<h2"
    end

    test "a question renders its answer back into the input" do
      node = %{"type" => "text_question", "key" => "first_name", "label" => "First name"}

      html =
        render_component(&SignupElements.element/1,
          node: node,
          answers: %{"first_name" => "Ada"}
        )

      assert html =~ ~s(name="answers[first_name]")
      assert html =~ ~s(value="Ada")
    end

    # Sabotage: replacing the raise with a no-op clause makes an unknown type
    # render nothing and this stops raising.
    test "an unknown element type raises rather than rendering nothing" do
      node = %{"type" => "carousel", "key" => "x"}

      assert_raise ArgumentError, ~r/no renderer for element type "carousel"/, fn ->
        render_component(&SignupElements.element/1, node: node)
      end
    end

    test "resolved_screen/1 draws only the nodes whose conditions hold" do
      html =
        render_component(&SignupElements.resolved_screen/1,
          screen: Screens.screen("account"),
          datamodel: %{"answers" => %{}}
        )

      refute html =~ "Nice to meet you"
      assert html =~ "Create your account"
    end
  end
end
