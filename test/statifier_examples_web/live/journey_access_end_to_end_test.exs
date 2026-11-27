defmodule StatifierExamplesWeb.JourneyAccessEndToEndTest do
  @moduledoc """
  The access design end to end, on the app's SQLite database: the Journey
  page, `RiddlerLiveView.Journey` drawing it, `StatifierExamplesWeb.JourneyHost`
  stepping it, and `StatifierExamplesWeb.JourneyAccess` asked before each
  step.

  - A person outside a Journey's scope cannot mount it, submit on it or go
    back on it.
  - A setup the branch onboarding runs as a durable child is checked
    against the branch scope it inherited: the branch's librarian steps
    it, a librarian of another branch does not.
  - A secret question's typed value reaches no HTML the page draws.

  ## How a submit and a back request by an outsider are driven

  A visitor outside the scope is never drawn the form or the Back
  control, because the component asks the access module before it draws
  anything. So a submit or a back request from an outsider cannot be
  pressed on a page an outsider loaded; driving one there would test a
  missing form, not the check the component asks before `submit/2` and
  `back/2`.

  Instead the page is loaded by a member, who is drawn the form, and then
  the actor the component holds is replaced by an outsider's before the
  press (`become/2`). Nothing else changes: the same screen, the same
  form, the same button, the same Journey. The component's
  `Riddler.Journey.Access.check/4` for `:submit` or `:back` is then the
  only thing between the press and the host, and the stored execution
  shows whether the host was called. The same replacement with another
  member of the scope is pressed through, so the replacement alone is not
  what refuses.

  This app's actor is read from the session, which does not change under
  a running page; the replacement stands in for an access answer that
  changes mid-Journey (a librarian moved to another branch), which is
  what the component's per-operation check exists for.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Persistence
  alias StatifierExamplesWeb.JourneyAccess
  alias StatifierPersistence.{Executions, Storage}

  @onboarding "/signup-journey?path=branch_onboarding"
  @registration "/signup-journey?path=patron_registration"
  @riverside %{"kind" => "branch", "id" => "riverside"}

  # The PIN typed into the secret question. Long and odd enough that no
  # other text on the page carries it by chance.
  @pin "73915246"

  defp key(key), do: ~s([data-riddler-key="#{key}"])

  defp librarian(branch, visitor \\ "V-#{System.unique_integer([:positive])}"),
    do: init_test_session(build_conn(), librarian_of: branch, visitor: visitor)

  defp patron(visitor), do: init_test_session(build_conn(), visitor: visitor)

  # Presses the button keyed `button` with the form's values and `values`.
  defp press(live, button, values \\ %{}) do
    live
    |> form("#journey form", values)
    |> put_submitter("button" <> key(button))
    |> render_submit()

    render(live)
  end

  defp started(conn, path) do
    {:ok, live, _html} = live(conn, path)
    live |> element("#start-journey") |> render_click()
    {:ok, %{query: query}} = live |> assert_patch() |> URI.new()
    %{"execution" => execution_id} = URI.decode_query(query)

    {live, execution_id}
  end

  # The riverside branch's onboarding, started by its librarian, with the
  # card reader setup picked: the page presents the setup, a durable child
  # of the onboarding execution, on its first screen.
  defp on_reader_setup(conn) do
    {live, execution_id} = started(conn, @onboarding)
    press(live, "onboarding_branch_continue", %{"branch_name" => "Riverside branch"})

    live
    |> form("#journey form", %{"integrations" => ["bdoc_card_reader_setup"]})
    |> render_change()

    press(live, "onboarding_integrations_continue")
    assert has_element?(live, key("reader_model_continue"))

    {live, execution_id}
  end

  # A fresh page on the riverside onboarding `execution_id`, mounted by a
  # librarian of the riverside branch: the component presents the
  # onboarding's focus and holds the scope that execution records.
  defp mounted(execution_id) do
    {:ok, live, _html} = live(librarian("riverside"), "#{@onboarding}&execution=#{execution_id}")
    assert has_element?(live, "#presented-child")
    live
  end

  defp active_child(execution_id) do
    {:ok, store} = Storage.new(Persistence, [])
    {:ok, [child]} = Executions.active_children(store, execution_id)
    child.execution_id
  end

  # Replaces the actor the page's `RiddlerLiveView.Journey` holds with the
  # actor `session` names, without telling the component: the next event
  # is checked for that actor against the scope already presented (the
  # moduledoc's "How a submit and a back request by an outsider are
  # driven"). Fails unless exactly one such component is replaced.
  #
  # It reads phoenix_live_view's channel state as 1.2 holds it, a
  # `components` tuple of the components by id and five-tuple entries; a
  # release that changes that shape fails here, on the match or the
  # asserts, not in the test that calls it.
  defp become(live, session) do
    actor = JourneyAccess.actor(session)

    :sys.replace_state(live.pid, fn %{components: {cids, ids, uuids}} = state ->
      journeys = for {cid, {RiddlerLiveView.Journey, _, _, _, _}} <- cids, do: cid
      assert [cid] = journeys
      {module, id, assigns, private, prints} = Map.fetch!(cids, cid)
      assert Map.has_key?(assigns, :actor)
      assigns = Map.put(assigns, :actor, actor)

      %{
        state
        | components: {Map.put(cids, cid, {module, id, assigns, private, prints}), ids, uuids}
      }
    end)

    live
  end

  defp refused?(live) do
    has_element?(live, "#journey [data-riddler-refused]") and
      not has_element?(live, "#journey form")
  end

  # THE MOUNT. Each Journey is drawn to a member of its scope and refused,
  # with the one refusal and nothing of the Journey, to everyone else: the
  # riverside onboarding and the setup it runs, to a librarian of another
  # branch and to a visitor who is no librarian; a patron's registration,
  # to a visitor of another session.
  #
  # Sabotage (run): made `JourneyAccess.member?/2` answer `true` for every
  # scope. The hillside librarian was drawn the setup's screen and this
  # went red on the first refusal.
  test "a person outside the scope cannot mount the Journey" do
    {_live, onboarding_id} = on_reader_setup(librarian("riverside"))
    child_id = active_child(onboarding_id)
    {_live, registration_id} = started(patron("P-1001"), @registration)

    refusals = [
      {"#{@onboarding}&execution=#{onboarding_id}",
       [librarian("hillside"), patron("P-1001"), build_conn()]},
      {"#{@onboarding}&execution=#{child_id}", [librarian("hillside"), build_conn()]},
      {"#{@registration}&execution=#{registration_id}",
       [patron("P-2002"), librarian("riverside", "P-2002")]}
    ]

    for {url, outsiders} <- refusals, outsider <- outsiders do
      {:ok, live, html} = live(outsider, url)

      assert has_element?(live, "#journey-refused[data-riddler-refused]")
      refute has_element?(live, "#journey form")
      refute has_element?(live, "#execution-id")
      refute html =~ onboarding_id
      refute html =~ child_id
      refute html =~ registration_id
    end

    {:ok, member, _html} =
      live(librarian("riverside"), "#{@onboarding}&execution=#{onboarding_id}")

    assert has_element?(member, key("reader_model_continue"))

    {:ok, member, _html} = live(patron("P-1001"), "#{@registration}&execution=#{registration_id}")
    assert has_element?(member, key("details_continue"))
  end

  # THE SUBMIT, AND THE INHERITED SCOPE. The setup is a durable child that
  # carries the onboarding's branch scope, copied when it was created. A
  # page mounted on the onboarding presents the child, and the component
  # holds the scope the child records (`JourneyHost.present/1` answers the
  # scope of the execution it presents) and checks every press against
  # it. A librarian of another branch is refused the press and the child
  # stays where it was; another librarian of the riverside branch, put in
  # the same way, is let through and the child moves.
  #
  # Sabotage (run): made `JourneyAccess.member?/2` answer `true` for every
  # scope. The hillside librarian's press was not refused and this went
  # red on the refusal.
  #
  # Sabotage (run): set `inherited_metadata_keys:` in `Durable.driver/1`
  # to `[]`. The child recorded no scope, the riverside librarian's fresh
  # page was refused the setup's screen, and this went red on `mounted/1`'s
  # `#presented-child` assertion.
  test "a child's submit is checked against the scope it inherited" do
    {_live, onboarding_id} = on_reader_setup(librarian("riverside"))
    child_id = active_child(onboarding_id)

    outsider = mounted(onboarding_id)

    outsider
    |> become(%{"librarian_of" => "hillside", "visitor" => "V-hillside"})
    |> press("reader_model_continue", %{"reader_kind" => "desk_reader"})

    assert refused?(outsider)

    member = mounted(onboarding_id)
    refute has_element?(member, key("reader_location_continue"))

    member
    |> become(%{"librarian_of" => "riverside", "visitor" => "V-riverside-2"})
    |> press("reader_model_continue", %{"reader_kind" => "desk_reader"})

    refute refused?(member)
    assert has_element?(member, key("reader_location_continue"))
    assert active_child(onboarding_id) == child_id
    assert child_id != onboarding_id
    assert {:ok, @riverside} = Durable.scope(child_id)
  end

  # THE BACK REQUEST. On the setup's second screen, where Back is offered,
  # a librarian of another branch is refused the back request and the
  # child stays on that screen.
  #
  # Sabotage (run): made `JourneyAccess.member?/2` answer `true` for every
  # scope. The hillside librarian's back request was not refused and this
  # went red on the refusal.
  test "a person outside the scope cannot go back" do
    {live, onboarding_id} = on_reader_setup(librarian("riverside"))
    press(live, "reader_model_continue", %{"reader_kind" => "desk_reader"})

    outsider = mounted(onboarding_id)
    assert has_element?(outsider, "[data-riddler-back]")

    outsider
    |> become(%{"librarian_of" => "hillside", "visitor" => "V-hillside"})
    |> element("[data-riddler-back]")
    |> render_click()

    assert refused?(outsider)

    member = mounted(onboarding_id)
    assert has_element?(member, key("reader_location_continue"))
    refute has_element?(member, key("reader_model_continue"))

    member
    |> become(%{"librarian_of" => "riverside", "visitor" => "V-riverside-2"})
    |> element("[data-riddler-back]")
    |> render_click()

    refute refused?(member)
    assert has_element?(member, key("reader_model_continue"))
  end

  # THE SECRET QUESTION. The PIN typed into the patron registration's
  # secret question is in none of the HTML the page draws: the screen as
  # first drawn, the screen re-presented after the PIN is typed, the screen
  # drawn with the findings of a refused press, the next screen with what
  # the chart has collected, and that screen drawn again on a fresh mount
  # once the PIN is stored. No Path this app runs offers Back to or from
  # the screen that asks the PIN, so there is no Back to draw here.
  #
  # Sabotage (run): made `Signup.Journey`'s seal step answer the responses
  # unsealed. The chart held the PIN as typed, a page drawn after the
  # press carried it, and this went red on the refute over the pages.
  test "the secret question's value never reaches the page HTML" do
    {live, execution_id} = started(patron("P-1001"), @registration)
    pages = [render(live)]

    typed = %{
      "first_name" => "Rosa",
      "email" => "not an address",
      "age" => "34",
      "riddler-password" => %{"library_pin" => @pin}
    }

    pages = [live |> form("#journey form", typed) |> render_change() | pages]

    pages = [press(live, "details_continue", typed) | pages]
    assert has_element?(live, "[data-riddler-finding]")
    assert has_element?(live, key("details_continue"))

    pages = [press(live, "details_continue", %{typed | "email" => "rosa@example.com"}) | pages]
    assert has_element?(live, key("card_finish"))
    assert has_element?(live, "#collected")

    refute has_element?(live, "[data-riddler-back]")

    {:ok, again, html} = live(patron("P-1001"), "#{@registration}&execution=#{execution_id}")
    assert has_element?(again, key("card_finish"))
    pages = [html, render(again) | pages]

    for html <- pages, do: refute(html =~ @pin)
  end
end
