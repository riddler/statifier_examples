defmodule StatifierExamplesWeb.SignupJourneyLiveTest do
  @moduledoc """
  `/signup-journey` drawn, pressed and reloaded.

  What is asserted here is only what the page adds over
  `StatifierExamples.Signup.JourneyTest`: that the markup carries the
  resolved screen, that a press reaches the execution, that a refused submit draws
  its findings, and - the property the page exists to demonstrate - that a
  second mount of the same URL picks the execution up where the first one left it.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Signup.Journey

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  defp started(conn) do
    {:ok, execution_id} = Journey.start("page-#{System.unique_integer([:positive])}")
    {:ok, live, html} = live(conn, ~p"/signup-journey?execution=#{execution_id}")

    %{live: live, html: html, execution_id: execution_id}
  end

  describe "with no run" do
    test "it offers to start one", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/signup-journey")

      assert html =~ "No run yet"
      assert has_element?(live, "#start-journey")
      refute has_element?(live, "#run-id")
    end

    # Sabotage: made `handle_event("start", ...)` patch to the page with no
    # `execution` param. Exactly this case went red: the patch drew the empty page
    # again and `#journey-responses` never appeared. Reverted from a copy.
    test "and starting one lands on the first screen", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey")

      html = live |> element("#start-journey") |> render_click()

      assert html =~ "Create your account"
      assert has_element?(live, "#journey-responses")
      assert has_element?(live, "#account_continue")
    end

    # No reader reaches this: the form is drawn only inside the `:if={@view}`
    # block, so there is no element to change and the event has to be sent to
    # the view directly. It is still worth refusing, because
    # `Journey.resolve/2` wants a view with a `:screen` and a page with no
    # execution has no view at all.
    #
    # Sabotage: removed the `view: nil` clause from
    # `handle_event("response", ...)`. This case went red - the event raised
    # a FunctionClauseError on `Journey.resolve/2` and took the view down
    # with it. Reverted from a copy.
    test "and a keystroke with no run refuses rather than raising", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey")

      html = render_change(live, "response", %{"responses" => %{"first_name" => "Ada"}})

      assert html =~ "no_execution"
      assert has_element?(live, "#journey-error")
      refute has_element?(live, "#journey-responses")
    end
  end

  describe "the screen it draws" do
    test "is the resolved one, not the whole document", %{conn: conn} do
      %{live: live, html: html} = started(conn)

      assert html =~ "Create your account"
      assert has_element?(live, "#first_name")
      assert has_element?(live, "#email")

      # Conditional on a name nobody has given.
      refute has_element?(live, "#account_greeting")
    end

    # Sabotage: made the page pass `@view.datamodel` to `SignupElements.screen`
    # as its `responses` instead of `@view.responses`. NOTHING went red, in
    # either suite, and that is a finding rather than a gap in the cases: this
    # Path never returns to a screen, so no input is ever drawn over a
    # response the chart already holds, and the whole `responses` attribute is
    # unobservable here. It stays correct because the next Path will not be
    # linear. Reverted from a copy.
    test "and it redraws as the reader types, because a condition may read it",
         %{conn: conn} do
      %{live: live} = started(conn)

      refute has_element?(live, "#account_greeting")

      html =
        live
        |> form("#journey-responses", responses: %{"first_name" => "Ada"})
        |> render_change()

      assert html =~ "Nice to meet you, Ada."
    end
  end

  describe "a press" do
    # The page's whole job in one case: a click becomes an event on a durable
    # execution, and what comes back is the next screen.
    #
    # Sabotage: made `handle_event("outcome", ...)` assign the view without
    # clearing the draft. NOTHING went red: a stale draft is merged into the
    # next screen's resolve and its payload, and no screen on this Path reads
    # or captures another screen's keys, so it changes nothing that anything
    # can see. The clearing stays because a Path whose screens shared a key
    # would send the previous screen's response as this one's. Reverted from a
    # copy.
    test "moves the run to the next screen", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey-responses", responses: @account) |> render_change()
      html = live |> element("#account_continue") |> render_click()

      assert html =~ "Pick a plan"
      assert has_element?(live, "#seats")
    end

    test "that does not validate draws its findings and stays put", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey-responses", responses: %{"email" => "ada"}) |> render_change()
      html = live |> element("#account_continue") |> render_click()

      assert html =~ "Create your account"
      assert has_element?(live, "#finding-first_name", "is required")
      assert has_element?(live, "#finding-email", "must look like an email address")
    end

    # The seat count decides which buttons the plan screen offers, and the
    # page has to re-resolve on every keystroke for either of them to be
    # clickable at all.
    test "on a button a condition reveals", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey-responses", responses: @account) |> render_change()
      live |> element("#account_continue") |> render_click()

      refute has_element?(live, "#plan_personal")

      live |> form("#journey-responses", responses: %{"seats" => "1"}) |> render_change()

      assert has_element?(live, "#plan_personal")
      refute has_element?(live, "#plan_business")

      html = live |> element("#plan_personal") |> render_click()

      assert html =~ "Confirm and finish"
    end
  end

  describe "the run outlives the page" do
    # THE POINT OF THE PAGE. A second mount of the same URL is a different
    # process with a different socket and nothing carried over, and it opens
    # on the screen the first one left the execution on, reading the responses back
    # out of the chart rather than out of anything it kept.
    #
    # Sabotage: made `Journey.current/1` build its view from an empty
    # datamodel rather than the execution's. Two cases went red, this one on the
    # address it reads back: with no responses the confirm summary's text slot
    # renders empty and the collected block is bare. Reverted from a copy.
    test "and a second mount opens where it was", %{conn: conn} do
      %{live: live, execution_id: execution_id} = started(conn)

      live |> form("#journey-responses", responses: @account) |> render_change()
      live |> element("#account_continue") |> render_click()

      {:ok, second, html} = live(conn, ~p"/signup-journey?execution=#{execution_id}")

      assert html =~ "Pick a plan"
      assert has_element?(second, "#seats")

      # The first screen's responses are the chart's now, and the page reads
      # them back out of it - the collected block is drawn from the execution's own
      # datamodel.
      assert render(second) =~ "ada@example.com"
    end

    test "and a run id nobody stored shows the refusal", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/signup-journey?execution=not-a-run")

      assert html =~ "execution_not_found"
      assert has_element?(live, "#journey-error")
      refute has_element?(live, "#journey-responses")
    end

    # And a keystroke that arrives anyway keeps that refusal rather than
    # replacing it with the vaguer one, which is the only reason the clause
    # reads the assign instead of writing over it.
    #
    # Sabotage: made the clause assign `:no_execution` unconditionally. This
    # case went red - the page drew "no_execution" and the reader lost the
    # reason. Reverted from a copy.
    test "and a keystroke on a refused run keeps the refusal it has", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey?execution=not-a-run")

      html = render_change(live, "response", %{"responses" => %{"first_name" => "Ada"}})

      assert html =~ "execution_not_found"
      refute html =~ "no_execution"
    end
  end
end
