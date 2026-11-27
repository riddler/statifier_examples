defmodule StatifierExamplesWeb.ScreenEditorLiveTest do
  @moduledoc """
  `/screen-editor` authored and tried: a patron registration document built
  in the editor with its insert and config events, then run as a Journey by
  the Try button, with no fixture file read or written for it.
  """

  use StatifierExamplesWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Plug.Conn.Query
  alias StatifierExamplesWeb.SecretResponse

  doctest StatifierExamplesWeb.SecretResponse

  describe "the page" do
    # Sabotage: dropped the profile from the editor's mount; the core
    # types came back onto the palette, then reverted.
    test "mounts the editor with the screen palette and profile", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/screen-editor")

      assert html =~ ~s(data-group="Screens")
      refute html =~ ~s(<li data-type="core.)
      refute html =~ ~s(class="sb-run")
      assert has_element?(view, "#try")
      refute has_element?(view, "#try-journey")
    end

    # Sabotage: made refusals/1 answer [] for a screens-document refusal;
    # the empty-document Try drew no refusal, then reverted.
    test "lists why Try cannot start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      twice = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, twice, %{"key" => "card_choice", "title" => "Your card"})
      again = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, again, %{"key" => "card_choice", "title" => "Your card again"})

      view |> element("#try") |> render_click()

      assert has_element?(view, "#try-refusals li")
      refute has_element?(view, "#try-journey")
    end

    # Sabotage (run): removed the format check from Try.start/1; the Try
    # started a Journey and the refusal assertion went red. Reverted from a
    # copy.
    test "refuses a text question format the Journey cannot check, keeping the page", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      details = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, details, %{"key" => "patron_details", "title" => "Your details"})

      age = insert(view, "myapp.screens.text_question", details, "elements", 0)
      configure(view, age, %{"key" => "age", "label" => "Age", "format" => "phone"})

      next = insert(view, "myapp.screens.button", details, "elements", 1)

      configure(view, next, %{
        "key" => "details_next",
        "label" => "Continue",
        "outcome" => "details_submitted"
      })

      view |> element("#try") |> render_click()

      assert has_element?(view, "#try-refusals li", "age: this page has no check")
      refute has_element?(view, "#try-journey")
      refute has_element?(view, "#details_next")
      assert render(view) =~ ~s(data-block-id="#{age}")
    end
  end

  describe "a choice question, authored and tried" do
    # Sabotage: made typed/2 leave a posted response as the form's text;
    # the boolean question's tick reached the Journey as "true" and the
    # valid press was refused, then reverted. And: drew a choice of one as
    # checkboxes; the radio assertion went red, then reverted.
    test "presents it, refuses an invalid response, then reads the next answer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      card = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, card, %{"key" => "card_choice", "title" => "Your card"})

      question = insert(view, "myapp.screens.choice_question", card, "elements", 0)

      configure(view, question, %{
        "key" => "card_type",
        "label" => "Which card would you like?",
        "select" => "one",
        "style" => "radio",
        "required" => "true",
        "answer_options" => ["standard=Standard card", "family=Family card"]
      })

      rules = insert(view, "myapp.screens.boolean_question", card, "elements", 1)

      configure(view, rules, %{
        "key" => "lending_rules",
        "label" => "I agree to the lending rules",
        "required" => "true"
      })

      next = insert(view, "myapp.screens.button", card, "elements", 2)

      configure(view, next, %{
        "key" => "card_next",
        "label" => "Continue",
        "outcome" => "card_chosen"
      })

      welcome = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, welcome, %{"key" => "welcome", "title" => "Welcome"})

      text = insert(view, "myapp.screens.text", welcome, "elements", 0)

      configure(view, text, %{
        "key" => "welcome_text",
        "text" => "Your {{ responses.card_type }} card is on its way."
      })

      # Try: the walk, the Journey, and the choice question presented.
      view |> element("#try") |> render_click()

      assert has_element?(view, "#try-journey")
      assert has_element?(view, ~s(#card_type input[type="radio"][value="standard"]))
      assert has_element?(view, ~s(#card_type input[type="radio"][value="family"]))
      assert render(view) =~ "Which card would you like?"

      # An invalid press: the rules ticked and no card chosen.
      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"lending_rules" => "true"}})

      view |> element("#card_next") |> render_click()

      assert has_element?(view, "#try-finding-card_type", "is required")
      assert has_element?(view, "#card_type")

      # A valid press, and the Journey's next answer: the welcome screen.
      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"card_type" => "family", "lending_rules" => "true"}})

      view |> element("#card_next") |> render_click()

      refute has_element?(view, "#try-findings")
      refute has_element?(view, "#card_type")
      assert has_element?(view, "#welcome_text", "Your family card is on its way.")
      assert view |> element("#try-collected") |> render() =~ "family"
    end
  end

  describe "a default and a secret question, authored and tried" do
    @pin "SENTINEL-PIN-not-a-real-pin"

    # Sabotage: started the draft empty instead of from the presented
    # values; the untouched press was refused as card_type required, then
    # reverted. And: made Journey.resolve/2 lay the typed PIN over the
    # view; the sentinel was on the page, then reverted.
    test "starts from the default, and never draws the PIN", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      card = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, card, %{"key" => "card_choice", "title" => "Your card"})

      question = insert(view, "myapp.screens.choice_question", card, "elements", 0)

      configure(view, question, %{
        "key" => "card_type",
        "label" => "Which card would you like?",
        "select" => "one",
        "required" => "true",
        "default" => "standard",
        "help" => "You can change card at any branch.",
        "answer_options" => ["standard=Standard card", "family=Family card"]
      })

      next = insert(view, "myapp.screens.button", card, "elements", 1)
      configure(view, next, %{"key" => "card_next", "label" => "Continue", "outcome" => "chosen"})

      pin_screen = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, pin_screen, %{"key" => "card_pin", "title" => "Protect your card"})

      pin = insert(view, "myapp.screens.secret_question", pin_screen, "elements", 0)

      configure(view, pin, %{
        "key" => "library_pin",
        "label" => "Choose a PIN for your library card",
        "help" => "You type it at the self-service desk.",
        "required" => "true"
      })

      done = insert(view, "myapp.screens.button", pin_screen, "elements", 1)
      configure(view, done, %{"key" => "pin_next", "label" => "Register", "outcome" => "pinned"})

      view |> element("#try") |> render_click()

      # The default is drawn chosen, with the help line, and pressing
      # without touching the form sends it.
      assert has_element?(view, ~s(#card_type input[type="radio"][value="standard"][checked]))
      assert has_element?(view, "#card_type-help", "You can change card at any branch.")

      view |> element("#card_next") |> render_click()

      refute has_element?(view, "#try-findings")
      assert has_element?(view, ~s(#library_pin input[type="password"]))
      assert has_element?(view, "#library_pin-help", "You type it at the self-service desk.")

      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"library_pin" => @pin}})

      refute render(view) =~ @pin

      view |> element("#pin_next") |> render_click()

      refute render(view) =~ @pin
      assert view |> element("#try-collected") |> render() =~ "test-sealed:"
    end
  end

  describe "a question inside a chosen variant candidate, authored and tried" do
    # Riddler resolves a variant to the candidate that wins, and the winner
    # replaces the variant (riddler 0.6.0, the `Riddler.Screens` moduledoc on
    # containers), so the draft's seeding over the presented top-level nodes
    # reaches a question that sat in a candidate.
    #
    # Sabotage: made presented/1 seed an empty draft; the untouched press was
    # refused as card_type required, then reverted from a copy.
    test "starts from its default, with no top-level question beside it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/screen-editor")

      card = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
      configure(view, card, %{"key" => "card_choice", "title" => "Your card"})

      variant = insert(view, "myapp.screens.variant", card, "elements", 0)
      configure(view, variant, %{"key" => "card_variant"})

      question = insert(view, "myapp.screens.choice_question", variant, "elements", 0)

      configure(view, question, %{
        "key" => "card_type",
        "label" => "Which card would you like?",
        "select" => "one",
        "required" => "true",
        "default" => "family",
        "answer_options" => ["standard=Standard card", "family=Family card"]
      })

      next = insert(view, "myapp.screens.button", card, "elements", 1)
      configure(view, next, %{"key" => "card_next", "label" => "Continue", "outcome" => "chosen"})

      done = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 1)
      configure(view, done, %{"key" => "all_done", "title" => "Done"})

      finish = insert(view, "myapp.screens.button", done, "elements", 0)
      configure(view, finish, %{"key" => "finish", "label" => "Finish", "outcome" => "finished"})

      view |> element("#try") |> render_click()

      assert has_element?(view, ~s(#card_type input[type="radio"][value="family"][checked]))

      view |> element("#card_next") |> render_click()

      refute has_element?(view, "#try-findings")
      assert has_element?(view, "#finish")
      assert view |> element("#try-collected") |> render() =~ "family"
    end
  end

  describe "a PIN typed on the page" do
    @pin "SENTINEL-PIN-not-a-real-pin"

    # Sabotage: took "responses" out of :phoenix :filter_parameters; the
    # LiveView's debug log of the response event carried the sentinel,
    # then reverted.
    test "reaches no log line, at debug, from any event the page handles", %{conn: conn} do
      view = tried_pin_screen(conn)

      log =
        debug_log(fn ->
          view
          |> element("#try-responses")
          |> render_change(%{"responses" => %{"library_pin" => @pin}})

          view |> element("#pin_next") |> render_click()
        end)

      refute log =~ @pin

      # The capture holds the page's own event logs, so an empty search is
      # not a search of nothing.
      assert log =~ ~s(HANDLE EVENT "response")
      assert log =~ ~s(HANDLE EVENT "outcome")
      assert has_element?(view, "#try-collected")
      assert view |> element("#try-collected") |> render() =~ "test-sealed:"
    end

    # Sabotage: made typed/2 keep a secret question's response as the
    # text; the crash report's State line carried the sentinel, then
    # reverted.
    test "is in no line of the crash report when the press crashes", %{conn: conn} do
      put_sealer(StatifierExamplesWeb.ScreenEditorLiveTest.RaisingSealer)
      view = tried_pin_screen(conn)
      Process.flag(:trap_exit, true)

      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"library_pin" => @pin}})

      log =
        debug_log(fn ->
          catch_exit(view |> element("#pin_next") |> render_click())
          wait_for_crash_report(view.pid)
        end)

      refute log =~ @pin

      # The crash report is in the capture, with the lines that print the
      # last message and the page's state.
      assert log =~ "terminating"
      assert log =~ "Last message"
      assert log =~ "State: "
    end

    # Sabotage: reverted typed/2 to the type lookup over the top-level
    # nodes alone; the draft held the PIN as the text, then reverted.
    test "inside a container is held wrapped and is in no line of the crash report", %{
      conn: conn
    } do
      put_sealer(StatifierExamplesWeb.ScreenEditorLiveTest.RaisingSealer)
      view = tried_pin_screen(conn)
      nest_secret_question(view)
      Process.flag(:trap_exit, true)

      view
      |> element("#try-responses")
      |> render_change(%{"responses" => %{"library_pin" => @pin}})

      state = :sys.get_state(view.pid)
      assert %SecretResponse{} = state.socket.assigns.draft["library_pin"]
      refute inspect(state) =~ @pin

      log =
        debug_log(fn ->
          catch_exit(view |> element("#pin_next") |> render_click())
          wait_for_crash_report(view.pid)
        end)

      refute log =~ @pin
      assert log =~ "terminating"
      assert log =~ "State: "
    end

    # Sabotage: dropped the guard on the response handler; the page read
    # the malformed responses and crashed with the sentinel in a
    # stacktrace's arguments, then reverted.
    test "in a response event the page cannot read is refused unread", %{conn: conn} do
      view = tried_pin_screen(conn)
      Process.flag(:trap_exit, true)

      # Were the page to read it and crash, the crash report would reach the
      # capture rather than end the test before the search.
      log =
        debug_log(fn ->
          try do
            render_hook(view, "response", %{"responses" => [["library_pin", @pin]]})
          catch
            :exit, _crashed -> wait_for_crash_report(view.pid)
          end
        end)

      refute log =~ @pin
      assert log =~ ~s(HANDLE EVENT "response")
      assert has_element?(view, ~s(#library_pin input[type="password"]))
    end

    # Sabotage: took the translator out of the application's start; the
    # Last message line printed the posted form string with the sentinel
    # in it, then reverted.
    test "posted by a form is in no line of a LiveView crash report" do
      posted = Query.encode(%{"responses" => %{"library_pin" => @pin}})

      message = %Phoenix.Socket.Message{
        topic: "lv:phx-crash",
        event: "event",
        payload: %{"event" => "response", "type" => "form", "value" => posted}
      }

      log =
        debug_log(fn ->
          {:ok, pid} = GenServer.start(StatifierExamplesWeb.ScreenEditorLiveTest.Crashing, nil)
          ref = Process.monitor(pid)
          send(pid, message)
          assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
        end)

      refute log =~ @pin
      assert log =~ "terminating"
      assert log =~ ~s(Last message: %Phoenix.Socket.Message{)
      assert log =~ ~s("responses" => "[FILTERED]")
    end
  end

  defmodule Crashing do
    @moduledoc false
    use GenServer

    @impl true
    def init(state), do: {:ok, state}

    @impl true
    def handle_info(_message, _state), do: raise("the page crashed")
  end

  defmodule RaisingSealer do
    @moduledoc false
    def seal(_plaintext), do: raise("the sealer is unavailable")
  end

  # The PIN screen authored in the editor and tried: one secret question
  # and the button that presses on.
  defp tried_pin_screen(conn) do
    {:ok, view, _html} = live(conn, ~p"/screen-editor")

    screen = insert(view, "myapp.screens.screen", "blk_pr_root", "body", 0)
    configure(view, screen, %{"key" => "card_pin", "title" => "Protect your card"})

    pin = insert(view, "myapp.screens.secret_question", screen, "elements", 0)

    configure(view, pin, %{
      "key" => "library_pin",
      "label" => "Choose a PIN for your library card",
      "required" => "true"
    })

    done = insert(view, "myapp.screens.button", screen, "elements", 1)
    configure(view, done, %{"key" => "pin_next", "label" => "Register", "outcome" => "pinned"})

    view |> element("#try") |> render_click()
    view
  end

  # The tried screen's view with its secret question moved inside a variant,
  # as a resolved screen that kept a container would present it. Riddler
  # resolves a variant to the candidate that wins, so no screen it presents
  # today keeps one, and the page's own state is changed to hold one.
  defp nest_secret_question(view) do
    :sys.replace_state(view.pid, fn state ->
      {secrets, rest} =
        Enum.split_with(state.socket.assigns.view.nodes, &(&1["type"] == "secret_question"))

      assert [%{"key" => "library_pin"}] = secrets
      container = %{"type" => "variant", "key" => "pin_variant", "elements" => secrets}
      put_in(state.socket.assigns.view.nodes, [container | rest])
    end)
  end

  # Everything logged while `fun` runs, with the Logger at debug for its
  # duration, as a dev server logs.
  defp debug_log(fun) do
    level = Logger.level()
    Logger.configure(level: :debug)

    try do
      capture_log([level: :debug], fun)
    after
      Logger.configure(level: level)
    end
  end

  # A crashing GenServer logs its crash report from its own process before
  # it exits, so the report is in the capture once the process is down. The
  # wait is on that exit, by a monitor, and bounded: a process that never
  # goes down fails here, by name, rather than as a missing line later.
  defp wait_for_crash_report(pid) do
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason},
                   1_000,
                   "the page process did not go down, so no crash report was logged"
  end

  defp put_sealer(sealer) do
    previous = Application.get_env(:statifier_examples, StatifierExamples.Signup.Sealer)
    Application.put_env(:statifier_examples, StatifierExamples.Signup.Sealer, sealer: sealer)

    on_exit(fn ->
      Application.put_env(:statifier_examples, StatifierExamples.Signup.Sealer, previous)
    end)
  end

  # The block ids the canvas draws, in page order.
  defp block_ids(view) do
    Regex.scan(~r/data-block-id="([^"]+)"/, render(view), capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  # One palette drag onto a gap in a block's slot, answering the id of the
  # block it placed: the one block id the canvas did not draw before.
  defp insert(view, type, parent_id, slot, index) do
    before = block_ids(view)

    canvas(view) |> render_hook("insert-dragstart", %{"type" => type})

    canvas(view)
    |> render_hook("insert-drop", %{
      "type" => type,
      "parent-id" => parent_id,
      "slot" => slot,
      "index" => to_string(index)
    })

    [id] = view |> block_ids() |> MapSet.difference(before) |> MapSet.to_list()
    id
  end

  # A config edit, as the inspector's form posts it.
  defp configure(view, block_id, config) do
    canvas(view) |> render_hook("config-change", %{"block-id" => block_id, "config" => config})
  end

  defp canvas(view), do: element(view, "#sb-canvas")
end
