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

  alias Riddler.Journey.Scope
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.RegistrationSteps
  alias StatifierExamples.Signup.Journey

  @account %{"first_name" => "Ada", "email" => "ada@example.com"}

  defp started(conn) do
    {:ok, execution_id} = Journey.start("page-#{System.unique_integer([:positive])}")
    {:ok, live, html} = live(conn, ~p"/signup-journey?execution=#{execution_id}")

    %{live: live, html: html, execution_id: execution_id}
  end

  # An element of the screen RiddlerLiveView.Journey draws, by its key.
  defp key(key), do: ~s([data-riddler-key="#{key}"])

  # Presses the button keyed `key`: a submit of the component's form with
  # that button as its submitter. It answers the page as drawn once the
  # press has landed: the component draws its answer in the submit's own
  # render, and the page draws what it shows beside the component from the
  # host's word one message later.
  defp press(live, key) do
    live |> form("#journey form") |> put_submitter("button" <> key(key)) |> render_submit()
    render(live)
  end

  describe "with no execution" do
    test "it offers to start one", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/signup-journey")

      assert html =~ "No execution yet"
      assert has_element?(live, "#no-execution")
      assert has_element?(live, "#start-journey")
      refute has_element?(live, "#execution-id")
    end

    # Sabotage: made `handle_event("start", ...)` patch to the page with no
    # `execution` param. Exactly this case went red: the patch drew the empty page
    # again and `#journey-responses` never appeared. Reverted from a copy.
    test "and starting one lands on the first screen", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey")

      html = live |> element("#start-journey") |> render_click()

      assert html =~ "Create your account"
      assert has_element?(live, "#journey form")
      assert has_element?(live, key("account_continue"))
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
    test "and a keystroke with no execution refuses rather than raising", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey")

      html = render_change(live, "change", %{"responses" => %{"first_name" => "Ada"}})

      assert html =~ "no_execution"
      assert has_element?(live, "#journey-error")
      refute has_element?(live, "#journey form")
    end

    # The same shape one press further along. The outcome buttons are drawn
    # inside the `:if={@view}` block too, so the event has to be sent to the
    # view directly - and the clause behind them reads
    # `assigns.view.execution_id`, which a page with no execution cannot
    # answer.
    #
    # Sabotage: removed the `view: nil` clause from
    # `handle_event("outcome", ...)`. This case went red - the event raised
    # reading `execution_id` out of nil and took the view down with it.
    # Reverted from a copy.
    test "and an outcome press with no execution refuses rather than raising", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey")

      html = render_click(live, "submit", %{"outcome" => "continue"})

      assert html =~ "no_execution"
      assert has_element?(live, "#journey-error")
      refute has_element?(live, "#journey form")
    end
  end

  describe "the screen it draws" do
    test "is the resolved one, not the whole document", %{conn: conn} do
      %{live: live, html: html, execution_id: execution_id} = started(conn)

      assert html =~ "Create your account"
      assert has_element?(live, "#execution-id", execution_id)
      assert has_element?(live, "#journey-element-first_name")
      assert has_element?(live, "#journey-element-email")

      # Conditional on a name nobody has given.
      refute has_element?(live, key("account_greeting"))
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

      refute has_element?(live, key("account_greeting"))

      html =
        live
        |> form("#journey form", %{"first_name" => "Ada"})
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
    test "moves the execution to the next screen", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      html = live |> press("account_continue")

      assert html =~ "Pick a plan"
      assert has_element?(live, "#journey-element-seats")
    end

    test "that does not validate draws its findings and stays put", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey form", %{"email" => "ada"}) |> render_change()
      html = live |> press("account_continue")

      assert html =~ "Create your account"
      assert has_element?(live, "#journey-element-first_name-finding-1", "is required")

      assert has_element?(
               live,
               "#journey-element-email-finding-1",
               "must look like an email address"
             )
    end

    # The seat count decides which buttons the plan screen offers, and the
    # page has to re-resolve on every keystroke for either of them to be
    # clickable at all.
    test "on a button a condition reveals", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")

      refute has_element?(live, key("plan_personal"))

      live |> form("#journey form", %{"seats" => "1"}) |> render_change()

      assert has_element?(live, key("plan_personal"))
      refute has_element?(live, key("plan_business"))

      html = live |> press("plan_personal")

      assert html =~ "Confirm and finish"
    end

    # The execution was stopped out of band while this page still showed the
    # plan screen, so the chart refuses the press. `Journey` answers with the
    # last settled position and the reason; the page has to say that the
    # press did not land, because the screen it draws is the one the reader
    # was already on and would otherwise read as a press that did nothing.
    # The ordinary press before the stop is where the notice's absence is
    # pinned.
    #
    # Sabotage: removed the `#press-discarded` paragraph from `render/1`. Red
    # on the notice assertion. Made its `:if` always true instead: red on the
    # refute after the ordinary press. Both reverted from a copy.
    test "the chart refused says so and stays where the execution stopped", %{conn: conn} do
      %{live: live, execution_id: execution_id} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")

      refute has_element?(live, "#press-discarded")

      {:ok, {{durable, _run}, _document}} = Durable.resume(execution_id)
      assert :ok = Durable.abandon(durable)

      live |> form("#journey form", %{"seats" => "1"}) |> render_change()
      html = live |> press("plan_personal")

      assert has_element?(live, "#press-discarded", "your last press was not recorded")
      assert html =~ "Pick a plan"
      refute html =~ "Confirm and finish"
    end
  end

  describe "beside the screen" do
    # The business arm rests on its asynchronous call, and the page says why
    # it waits and when to ask again rather than only that it is between
    # screens.
    #
    # Sabotage: made the `#waiting-reason` paragraph's `:if` always false. Red
    # here on the reason and nowhere else. Reverted from a copy.
    test "a waiting execution shows the reason and the retry hint", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")
      live |> form("#journey form", %{"seats" => "5"}) |> render_change()
      live |> press("plan_business")

      assert has_element?(live, "#journey-waiting")
      assert has_element?(live, "#waiting-reason", "company_details_pending")
      assert has_element?(live, "#waiting-retry", "Ask again in 5 seconds")
      refute has_element?(live, "#journey form")
      refute has_element?(live, "#journey-done")
    end

    # The last press finishes the Path, and the page shows the finished line
    # and the receipt the execution finished with.
    #
    # Sabotage: made the result block's `:if` always false. Red here on
    # `#journey-result` and nowhere else. Reverted from a copy.
    test "a done execution shows what it finished with", %{conn: conn} do
      %{live: live} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")
      live |> form("#journey form", %{"seats" => "1"}) |> render_change()
      live |> press("plan_personal")
      live |> press("confirm_finish")

      assert has_element?(live, "#journey-finished", "The execution finished: done.")
      assert has_element?(live, "#journey-result", "ada@example.com")
      refute has_element?(live, "#journey-stopped-on")
      refute has_element?(live, "#journey-waiting")
    end

    # Loaded fresh for an execution that stopped on a screen, the page draws
    # the finished line and the screen it stopped on - not that screen's
    # title with nothing under it.
    #
    # Sabotage: put back the old rule, the done section drawn only when the
    # view names no screen. Red here and on the refused-press case below.
    # Reverted from a copy.
    test "an execution stopped on a screen shows the finished line", %{conn: conn} do
      {:ok, execution_id} = Journey.start("page-#{System.unique_integer([:positive])}")
      {:ok, {{durable, _run}, _document}} = Durable.resume(execution_id)
      assert :ok = Durable.abandon(durable)

      {:ok, live, _html} = live(conn, ~p"/signup-journey?execution=#{execution_id}")

      assert has_element?(live, "#journey-finished", "The execution finished: failed.")
      assert has_element?(live, "#journey-stopped-on", "Create your account")
      refute has_element?(live, "#journey form")
      refute has_element?(live, "#journey-result")
    end
  end

  describe "the execution outlives the page" do
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

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")

      {:ok, second, html} = live(conn, ~p"/signup-journey?execution=#{execution_id}")

      assert html =~ "Pick a plan"
      assert has_element?(second, "#journey-element-seats")

      # The first screen's responses are the chart's now, and the page reads
      # them back out of it - the collected block is drawn from the execution's own
      # datamodel.
      assert render(second) =~ "ada@example.com"
    end

    test "and an execution id nobody stored shows the refusal", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/signup-journey?execution=not-an-execution")

      assert html =~ "execution_not_found"
      assert has_element?(live, "#journey-error")
      refute has_element?(live, "#journey form")
    end

    # And a keystroke that arrives anyway keeps that refusal rather than
    # replacing it with the vaguer one, which is the only reason the clause
    # reads the assign instead of writing over it.
    #
    # Sabotage: made the clause assign `:no_execution` unconditionally. This
    # case went red - the page drew "no_execution" and the reader lost the
    # reason. Reverted from a copy.
    test "and a keystroke on a refused execution keeps the refusal it has", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey?execution=not-an-execution")

      html = render_change(live, "change", %{"responses" => %{"first_name" => "Ada"}})

      assert html =~ "execution_not_found"
      refute html =~ "no_execution"
    end

    # Sabotage: made the outcome clause assign `:no_execution` unconditionally.
    # This case went red - the page drew "no_execution" and the reader lost
    # the reason. Reverted from a copy.
    test "and an outcome press on a refused execution keeps the refusal it has", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup-journey?execution=not-an-execution")

      html = render_click(live, "submit", %{"outcome" => "continue"})

      assert html =~ "execution_not_found"
      refute html =~ "no_execution"
    end
  end

  describe "Back through returnable steps" do
    @steps_path "/signup-journey?path=patron_registration_steps"
    @name %{"first_name" => "Rosa", "email" => "rosa@example.com"}

    defp steps_started(conn) do
      {:ok, live, _html} = live(conn, @steps_path)
      live |> element("#start-journey") |> render_click()

      live
    end

    # Sabotage: made `journey_url/2` drop the `path` param. The patched URL
    # named no Path and this went red. Reverted from a copy.
    test "the page runs the patron registration steps, and offers no Back on the first", %{
      conn: conn
    } do
      live = steps_started(conn)

      assert has_element?(live, key("name_continue"))
      refute has_element?(live, "[data-riddler-back]")
      assert assert_patch(live) =~ "path=patron_registration_steps"
    end

    # Sabotage: rendered `#journey-back` whatever `@view.back` held. The
    # first step drew a Back control and this went red, as did the test
    # above and the signup Path case below. Reverted from a copy.
    #
    # Sabotage: made `handle_event("back", ...)` send `"back" => "true"`, a
    # string. Riddler decoded it as a submit, the execution stayed on the
    # card step and this went red. Reverted from a copy.
    test "Back sends riddler's back request and the step gone back to carries its held values",
         %{conn: conn} do
      live = steps_started(conn)

      live |> form("#journey form", @name) |> render_change()
      live |> press("name_continue")
      assert has_element?(live, key("card_continue"))
      assert has_element?(live, "[data-riddler-back]")

      live |> form("#journey form", %{"card_type" => "family"}) |> render_change()
      html = live |> element("[data-riddler-back]") |> render_click()

      assert has_element?(live, key("name_continue"))
      refute has_element?(live, "[data-riddler-back]")
      refute has_element?(live, "#journey-error")
      assert html =~ ~s(value="Rosa")
      assert html =~ ~s(value="rosa@example.com")
      refute html =~ "family"
    end

    # Sabotage: made the back clause assign `draft: %{}` in place of
    # `held(view)`. Pressing Continue on the re-shown step sent nothing,
    # the required name came back as a finding and this went red. Reverted
    # from a copy.
    test "a step gone back to moves on again without retyping", %{conn: conn} do
      live = steps_started(conn)

      live |> form("#journey form", @name) |> render_change()
      live |> press("name_continue")
      live |> element("[data-riddler-back]") |> render_click()

      live |> press("name_continue")

      refute has_element?(live, "[data-riddler-finding]")
      assert has_element?(live, key("card_continue"))
      assert has_element?(live, "[data-riddler-back]")
    end

    # Sabotage: made `load/2` call `Journey.current/1` without the page's
    # options. A reload of the steps execution read it against the signup
    # Path and this went red. Reverted from a copy.
    # The steps run under the patron scope of the visitor reloading them.
    test "a reload picks the steps execution up where it was", %{conn: conn} do
      opts = RegistrationSteps.options()
      {:ok, patron} = Scope.new("patron", "P-1001")
      conn = init_test_session(conn, visitor: "P-1001")

      {:ok, execution_id} =
        Journey.start("page-steps-#{System.unique_integer([:positive])}", opts ++ [scope: patron])

      {:ok, _card} = Journey.submit(execution_id, "name_given", @name, opts)

      {:ok, live, _html} = live(conn, "#{@steps_path}&execution=#{execution_id}")

      assert has_element?(live, key("card_continue"))
      assert has_element?(live, "[data-riddler-back]")
    end

    # Sabotage: made `path_options/1` answer the signup Path for a key the
    # list does not hold. No refusal was drawn and this went red. Reverted
    # from a copy.
    test "a path the page does not run is refused", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/signup-journey?path=no_such_path")

      assert html =~ "unknown_path"
      assert has_element?(live, "#journey-error")
      live |> element("#start-journey") |> render_click()
      refute has_element?(live, "#journey form")
    end

    # Sabotage: made `back_offered?/2` in `Journey` answer `true` for every
    # position. The signup Path's plan screen drew a Back control and this
    # went red. Reverted from a copy.
    test "the signup Path draws no engine Back control, and keeps its authored Back button", %{
      conn: conn
    } do
      %{live: live} = started(conn)

      live |> form("#journey form", @account) |> render_change()
      live |> press("account_continue")

      assert has_element?(live, key("plan_back"))
      refute has_element?(live, "[data-riddler-back]")
    end
  end
end
