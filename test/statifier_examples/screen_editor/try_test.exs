defmodule StatifierExamples.ScreenEditor.TryTest do
  @moduledoc """
  The screen editor's Try action over a patron registration document of its
  own: two screens whose keys and outcomes the signup Path fixture has never
  heard of, run as a Journey on the Path `Try.path/1` derives for them.
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Repo
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.ScreenEditor.Walk
  alias StatifierExamples.Signup.Journey

  doctest StatifierExamples.Signup.Screen, only: [parked_screen: 1]
  doctest StatifierExamples.Signup.Validation, only: [formats: 0]

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  describe "path/1" do
    # Sabotage: made group/2 leave out the screen's questions from the
    # capture; the card_type pair went missing, then reverted.
    test "parks once per screen and captures every question on it" do
      {:ok, screens} = Walk.screen_document(registration())
      path = Try.path(screens)

      assert {:ok, _compiled} = Durable.compile(path, [])

      assert [card, welcome] = path.root.slots["body"]

      assert [_present, %Block{type: "core.await", config: %{"event" => park}}] =
               card.slots["body"]

      assert park == "signup.screen.card_choice.resumed"

      assert [%Block{config: %{"event" => "signup.card_chosen", "capture" => capture}}] =
               card.slots["interrupts"]

      assert capture == %{
               "responses.card_type" => "card_type",
               "responses.lending_rules" => "lending_rules",
               "responses.card_source" => ["const", "online"]
             }

      assert [%Block{config: %{"event" => "signup.registration_finished"}}] =
               welcome.slots["interrupts"]
    end
  end

  describe "start/1" do
    # Sabotage: made Journey's park/1 skip a core.await; the Journey started
    # on no screen and the card_choice assertion went red, then reverted.
    test "runs the authored screens as a Journey, invalid press first" do
      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(registration())

      {:ok, card} = Journey.current(execution_id, opts)
      assert %{key: "card_choice"} = card.screen
      assert card.state == "screen"
      assert Enum.map(card.nodes, & &1["key"]) == ~w(card_type lending_rules card_next)

      assert {:invalid, refused} =
               Journey.submit(execution_id, "card_chosen", %{"lending_rules" => true}, opts)

      assert refused.findings == [{"card_type", "is required"}]

      responses = %{"card_type" => "family", "lending_rules" => true}
      {:ok, welcome} = Journey.submit(execution_id, "card_chosen", responses, opts)

      assert %{key: "welcome"} = welcome.screen
      assert [%{"text" => "Your family card is on its way."} | _] = welcome.nodes

      assert welcome.responses == %{
               "card_type" => "family",
               "lending_rules" => true,
               "card_source" => "online"
             }

      {:ok, done} = Journey.submit(execution_id, "registration_finished", %{}, opts)
      assert done.state == "done"
      assert done.screen == nil
    end

    # Sabotage: made explained_formats/1 find no unsupported format; the
    # Try started on the question and the refusal match went red, then
    # reverted from a copy. The editor's own format choices are all
    # worded, so the document is built here, as a hand-written one would be.
    test "refuses a text question naming a format with no message, starting nothing" do
      screen =
        screen("blk_try_card", "card_choice", "Your card", [
          element("text_question", "postcode", %{"label" => "Postcode", "format" => "postcode"}),
          element("button", "card_next", %{"label" => "Continue", "outcome" => "card_chosen"})
        ])

      root = Block.new("core.sequence", id: "blk_try_doc_root", slots: %{"body" => [screen]})
      document = Document.new(root, id: "doc_unsupported_format")

      assert Try.start(document) == {:error, {:unsupported_format, ["postcode"]}}
    end

    # Sabotage: dropped "integer" from Validation's formats; Try.start/1
    # refused the fixture as {:unsupported_format, ["age"]}, then reverted
    # from a copy.
    test "starts on the patron registration fixture as it is authored" do
      {:ok, document} =
        "priv/fixtures/patron_registration_screens.json" |> File.read!() |> Document.from_json()

      assert {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(document)

      {:ok, details} = Journey.current(execution_id, opts)
      assert %{key: "patron_details"} = details.screen

      details_responses = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "old",
        "library_pin" => "1234"
      }

      assert {:invalid, refused} =
               Journey.submit(execution_id, "details_submitted", details_responses, opts)

      assert refused.findings == [{"age", "must be a whole number"}]
    end

    # Sabotage: made Journey's checked/4 validate the shown nodes without
    # putting their checks back; the future date was accepted and the
    # :invalid match went red, then reverted from a copy. Sabotage: made
    # context/1 ignore opts[:today]; the press on the 19th was accepted,
    # then reverted from a copy.
    test "holds the date of birth to its check, against the host's today" do
      {:ok, document} =
        "priv/fixtures/patron_registration_screens.json" |> File.read!() |> Document.from_json()

      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(document)

      details = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "34",
        "birth_date" => "2026-11-20",
        "library_pin" => "1234"
      }

      on = fn day -> opts ++ [today: Date.from_iso8601!(day)] end

      assert {:invalid, refused} =
               Journey.submit(execution_id, "details_submitted", details, on.("2026-11-19"))

      assert refused.findings == [{"birth_date", "A date of birth cannot be in the future."}]

      assert [
               %Riddler.Finding{
                 code: "check.birth_date_in_future",
                 element_key: "birth_date",
                 author_message: "A date of birth cannot be in the future."
               }
             ] = refused.refusals

      {:ok, still} = Journey.current(execution_id, opts)
      assert %{key: "patron_details"} = still.screen
      refute Map.has_key?(still, :refusals)

      assert {:ok, card} =
               Journey.submit(execution_id, "details_submitted", details, on.("2026-11-21"))

      assert %{key: "card_choice"} = card.screen
      refute Map.has_key?(card, :refusals)
    end

    # Sabotage: made submit/4 take the context the press carries when it
    # carries one; the press was accepted and the :invalid match
    # went red, then reverted from a copy. Sabotage: made the default
    # today 9999-12-31; the year 2999 was accepted, then reverted.
    test "takes its today from the host's clock, never from the press" do
      {:ok, document} =
        "priv/fixtures/patron_registration_screens.json" |> File.read!() |> Document.from_json()

      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(document)

      details = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "34",
        "birth_date" => "2999-01-01",
        "library_pin" => "1234",
        "context" => %{"today" => "3000-01-01"},
        "today" => "3000-01-01"
      }

      assert {:invalid, refused} =
               Journey.submit(execution_id, "details_submitted", details, opts)

      assert refused.findings == [{"birth_date", "A date of birth cannot be in the future."}]
    end

    # The fixture is where the boolean and choice blocks' `help` field is
    # used. Sabotage: took the boolean question's help out of the fixture; the
    # card screen presented one help line and this went red, then reverted
    # from a copy.
    test "presents the help the fixture puts on a choice and a boolean question" do
      {:ok, document} =
        "priv/fixtures/patron_registration_screens.json" |> File.read!() |> Document.from_json()

      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(document)

      details = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "34",
        "library_pin" => "1234"
      }

      {:ok, card} = Journey.submit(execution_id, "details_submitted", details, opts)

      helps = for %{"key" => key, "help" => help} <- card.nodes, into: %{}, do: {key, help}

      assert helps == %{
               "card_type" => "You can change card at any branch.",
               "lending_rules" => "They cover loan periods, renewals and fines."
             }
    end

    # Sabotage: took the image block out of the fixture; the details
    # screen presented no library_logo and this went red, then reverted
    # from a copy.
    test "presents the image, divider, link, date, slider and option description the fixture adds" do
      {:ok, document} =
        "priv/fixtures/patron_registration_screens.json" |> File.read!() |> Document.from_json()

      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(document)
      {:ok, details} = Journey.current(execution_id, opts)
      details_nodes = Map.new(details.nodes, &{&1["key"], &1})

      assert %{
               "type" => "image",
               "src" => "/images/logo.svg",
               "alt" => "Riverbend Public Library"
             } =
               details_nodes["library_logo"]

      assert %{"type" => "divider"} = details_nodes["details_divider"]

      assert %{"type" => "text_question", "format" => "date"} =
               birth = details_nodes["birth_date"]

      refute Map.has_key?(birth, "checks")

      responses = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "34",
        "birth_date" => "1990-04-17",
        "library_pin" => "1234"
      }

      {:ok, card} = Journey.submit(execution_id, "details_submitted", responses, opts)
      card_nodes = Map.new(card.nodes, &{&1["key"], &1})

      assert %{"type" => "link", "href" => "https://library.example.com/lending-rules"} =
               card_nodes["rules_link"]

      assert %{"style" => "slider", "step" => 1, "min" => 1, "max" => 20} =
               card_nodes["items_at_once"]

      assert %{"value" => "student", "description" => "For patrons in full-time education" <> _} =
               card_nodes["card_type"]["answer_options"] |> List.last()
    end

    # Sabotage: made walk/1 answer the walk's refusals unwrapped; the
    # {:walk, _} match went red, then reverted.
    test "refuses a document the walk refuses, starting nothing" do
      stray = Block.new("myapp.screens.text", id: "blk_stray", config: %{"key" => "stray"})
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [stray]})

      assert {:error, {:walk, [{"blk_stray", _message}]}} = Try.start(Document.new(root))
    end

    # Sabotage: made start/1 leave the walked screens out of the Journey's
    # options; the start answered :undeclared_screens, then reverted.
    test "refuses a screen document riddler does not admit, starting nothing" do
      twice = screen("blk_try_twice", "card_choice", "Your card again", [])
      root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => [twice, twice]})

      assert {:error, {:screens_document, [_ | _]}} =
               Try.start(Document.new(root, id: "doc_twice"))
    end
  end

  describe "Journey with a supplied Path" do
    # Sabotage: made Journey's resume/2 ignore opts[:path]; the current read
    # answered :chart_unknown, then reverted.
    test "refuses a Path that is not the one the Journey started on" do
      {:ok, %{execution_id: execution_id, opts: opts}} = Try.start(registration())
      {:ok, screens} = Walk.screen_document(registration())

      other = Try.path(Map.update!(screens, "screens", &Enum.take(&1, 1)))

      assert {:error, {:identity_mismatch, _stored, _supplied}} =
               Journey.current(execution_id, Keyword.put(opts, :path, other))
    end
  end

  # A patron registration block document authored in the screen palette:
  # the card the patron wants and the lending rules, then a welcome.
  defp registration do
    card =
      screen("blk_try_card", "card_choice", "Your card", [
        element("choice_question", "card_type", %{
          "label" => "Which card would you like?",
          "select" => "one",
          "style" => "radio",
          "required" => true,
          "answer_options" => ["standard=Standard card", "family=Family card"]
        }),
        element("boolean_question", "lending_rules", %{
          "label" => "I agree to the lending rules",
          "required" => true
        }),
        element("button", "card_next", %{
          "label" => "Continue",
          "outcome" => "card_chosen",
          "writes" => ["responses.card_source=online"]
        })
      ])

    welcome =
      screen("blk_try_welcome", "welcome", "Welcome", [
        element("text", "welcome_text", %{
          "text" => "Your {{ responses.card_type }} card is on its way."
        }),
        element("button", "welcome_done", %{
          "label" => "Finish",
          "outcome" => "registration_finished"
        })
      ])

    root = Block.new("core.sequence", id: "blk_try_doc_root", slots: %{"body" => [card, welcome]})
    Document.new(root, id: "doc_patron_registration")
  end

  defp screen(id, key, title, elements) do
    Block.new("myapp.screens.screen",
      id: id,
      config: %{"key" => key, "title" => title},
      slots: %{"elements" => elements}
    )
  end

  defp element(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_try_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
