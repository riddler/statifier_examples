defmodule StatifierExamples.ScreenEditor.WalkTest do
  @moduledoc """
  The walk from a screen editor block document to the screen document
  riddler reads, proven two ways: the shipped signup screens document
  authored as blocks and walked back to itself, and the patron registration
  screens block document walked and admitted by riddler with no finding.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Document
  alias StatifierBlocks.Palette
  alias StatifierBlocks.Schema
  alias StatifierExamples.ScreenEditor
  alias StatifierExamples.ScreenEditor.Walk
  alias StatifierExamples.Signup.Screens

  doctest StatifierExamples.ScreenEditor.Walk
  doctest StatifierExamples.ScreenEditor.Button

  @registration "priv/fixtures/patron_registration_screens.json"

  describe "the signup screens document, authored as blocks" do
    # Sabotage: made base/2 skip the "condition" field; the round trip went
    # red on the conditional nodes, then reverted.
    test "walks back to the shipped document, every field carried" do
      fixture = Screens.document()
      document = author(fixture)
      {:ok, upgraded} = Riddler.Screens.upgrade(fixture)

      assert :ok = Document.validate(document)
      assert {:ok, _compiled} = Compiler.compile(document, ScreenEditor.palette())
      assert {:ok, ^upgraded} = Walk.screen_document(document)
    end

    # Sabotage: made collect/2 return its answers reversed; the node keys
    # came out last first, then reverted.
    test "keeps each screen's nodes in the order they were authored" do
      {:ok, walked} = Walk.screen_document(author(Screens.document()))

      assert Enum.map(walked["screens"], & &1["key"]) == ~w(account plan confirm)

      assert walked["screens"] |> hd() |> Map.fetch!("elements") |> Enum.map(& &1["key"]) ==
               ~w(account_heading account_intro first_name email account_greeting account_continue)
    end
  end

  describe "the patron registration screens block document" do
    # Sabotage: made options/1 keep the option rows as written; riddler
    # refused the document (not a screens document), then reverted.
    test "walks to a screen document riddler admits with no finding" do
      {:ok, walked} = Walk.screen_document(registration())

      assert {:ok, %Riddler.Screens.Document{}} = Screens.admit(walked)
    end

    test "holds a choice question of each select and a boolean question" do
      {:ok, walked} = Walk.screen_document(registration())
      elements = Enum.flat_map(walked["screens"], & &1["elements"])

      assert %{"select" => "one", "answer_options" => [%{"value" => "standard"} | _]} =
               Enum.find(elements, &(&1["key"] == "card_type"))

      assert %{"select" => "many", "min_selections" => 0, "max_selections" => 3} =
               Enum.find(elements, &(&1["key"] == "interests"))

      assert %{"type" => "boolean_question", "required" => true} =
               Enum.find(elements, &(&1["key"] == "lending_rules"))
    end

    # Sabotage: dropped the secret question from the palette's
    # registrations; the walk refused the block as no element type, then
    # reverted.
    test "asks for a PIN as a secret question, and carries a help line and a default" do
      assert {:ok, walked} = Walk.screen_document(registration())
      [details, card] = walked["screens"]

      assert %{
               "type" => "secret_question",
               "label" => "Choose a PIN for your library card",
               "help" => "You type it with your card number to borrow at the self-service desk.",
               "required" => true
             } = Enum.find(details["elements"], &(&1["key"] == "library_pin"))

      assert %{"help" => "We write here when a hold is ready and before a loan is due."} =
               Enum.find(details["elements"], &(&1["key"] == "email"))

      assert %{"default" => "standard"} = Enum.find(card["elements"], &(&1["key"] == "card_type"))
    end

    # Sabotage: made number/3 leave an integer bound as its text; the "min"
    # assertion went red, then reverted.
    test "turns the editor's own shapes back into the document's" do
      {:ok, walked} = Walk.screen_document(registration())
      elements = Enum.flat_map(walked["screens"], & &1["elements"])

      assert %{"min" => 0, "max" => 120} = Enum.find(elements, &(&1["key"] == "age"))

      assert %{
               "writes" => %{
                 "responses.card_source" => ["const", "online"],
                 "responses.newsletter" => ["const", true]
               },
               "style" => "primary"
             } = Enum.find(elements, &(&1["key"] == "card_finish"))

      assert %{"validates" => false} = Enum.find(elements, &(&1["key"] == "card_back"))

      assert %{"type" => "variant", "elements" => [%{"key" => "family_notice"}, _default]} =
               Enum.find(elements, &(&1["key"] == "card_notice"))
    end

    # Sabotage: made described/2 drop the descriptions; the student
    # option came out with no description, then reverted from a copy.
    # Sabotage: made step/1 leave the step as its text; the slider match
    # went red, then reverted from a copy.
    test "walks each newer element and field into riddler's shape" do
      {:ok, walked} = Walk.screen_document(registration())
      [details, card] = walked["screens"]
      by_key = fn screen -> Map.new(screen["elements"], &{&1["key"], &1}) end

      details = by_key.(details)
      card = by_key.(card)

      assert details["library_logo"] == %{
               "type" => "image",
               "key" => "library_logo",
               "src" => "/images/logo.svg",
               "alt" => "Riverbend Public Library",
               "size" => "small"
             }

      assert details["details_divider"] == %{"type" => "divider", "key" => "details_divider"}

      assert %{
               "format" => "date",
               "min" => "1900-01-01",
               "checks" => [
                 %{
                   "code" => "check.birth_date_in_future",
                   "condition" => "trim(responses.birth_date)::date <= context.today::date",
                   "message" => "A date of birth cannot be in the future."
                 }
               ]
             } = details["birth_date"]

      assert %{"style" => "slider", "step" => 1, "min" => 1, "max" => 20} =
               card["items_at_once"]

      assert card["rules_link"] == %{
               "type" => "link",
               "key" => "rules_link",
               "label" => "Read the lending rules",
               "href" => "https://library.example.com/lending-rules"
             }

      options = card["card_type"]["answer_options"]
      refute Map.has_key?(card["card_type"], "option_descriptions")
      assert [%{"value" => "standard"} = standard, _family, student] = options
      refute Map.has_key?(standard, "description")

      assert student["description"] ==
               "For patrons in full-time education, with a longer loan period"
    end

    # Sabotage: took the checks row off the fixture's date of birth
    # question; the future date answered :ok, then reverted from a copy.
    test "holds the date of birth to its check, decided against the host's today" do
      {:ok, walked} = Walk.screen_document(registration())
      {:ok, document} = Screens.admit(walked)

      answered = %{
        "first_name" => "Rosa",
        "email" => "rosa@example.com",
        "age" => "34",
        "library_pin" => "1234"
      }

      root = fn birth_date ->
        %{
          "responses" => Map.put(answered, "birth_date", birth_date),
          "context" => %{"today" => "2026-11-27"}
        }
      end

      assert {:error, [finding]} =
               Riddler.Screens.validate_screen(document, "patron_details", root.("2031-04-17"))

      assert %Riddler.Finding{
               code: "check.birth_date_in_future",
               element_key: "birth_date",
               field: "checks",
               author_message: "A date of birth cannot be in the future."
             } = finding

      assert :ok =
               Riddler.Screens.validate_screen(document, "patron_details", root.("1990-04-17"))
    end

    test "is a document the screen palette authors, with no finding" do
      document = registration()
      schema = ScreenEditor.palette() |> Schema.for_palette() |> ExJsonSchema.Schema.resolve()

      assert :ok ==
               ExJsonSchema.Validator.validate(
                 schema,
                 @registration |> File.read!() |> Jason.decode!()
               )

      assert [] == Palette.preflight(ScreenEditor.palette(), [document])
      assert {:ok, _compiled} = Compiler.compile(document, ScreenEditor.palette())
    end
  end

  describe "the envelope and the blanks" do
    # Sabotage: made put_present/3 keep blank values; the blank condition
    # and the empty writes came out, then reverted. Sabotage: made
    # envelope/2 write schema_version 1; the envelope match went red, then
    # reverted from a copy.
    test "leaves blank fields out and keeps false" do
      button = %{"label" => "Back", "outcome" => "went_back", "condition" => "", "writes" => []}
      question = %{"label" => "Nickname", "required" => false, "placeholder" => nil}

      {:ok, walked} =
        Walk.screen_document(
          one_screen([
            element("button", "back", button),
            element("text_question", "nickname", question)
          ])
        )

      assert [
               %{"type" => "button", "key" => "back", "label" => "Back", "outcome" => "went_back"} =
                 back,
               %{"key" => "nickname", "required" => false} = nickname
             ] = walked |> Map.fetch!("screens") |> hd() |> Map.fetch!("elements")

      refute Map.has_key?(back, "condition")
      refute Map.has_key?(back, "writes")
      refute Map.has_key?(nickname, "placeholder")
      assert %{"schema_version" => 2, "id" => "sdoc_walk"} = walked
      refute Map.has_key?(walked, "metadata")
    end
  end

  describe "a write row's value" do
    # Sabotage: made constant/1 answer the text unread; the number and the
    # boolean came out as strings, then reverted.
    test "is read as JSON when it is JSON, and as the text when it is not" do
      rows = [
        "responses.card=family",
        "responses.guests=2",
        "responses.newsletter=false",
        ~s(responses.branch_code="12"),
        ~s(responses.collections=["fiction","audiobooks"])
      ]

      assert %{
               "responses.card" => ["const", "family"],
               "responses.guests" => ["const", 2],
               "responses.newsletter" => ["const", false],
               "responses.branch_code" => ["const", "12"],
               "responses.collections" => ["const", ["fiction", "audiobooks"]]
             } == writes(rows)
    end

    # Sabotage: made write/2's is_map_key/2 clause never match; the second
    # row replaced the first and the walk answered :ok, then reverted.
    test "refuses two rows that write one path" do
      rows = ["responses.card=family", "responses.card=standard"]

      assert {:error, [{"blk_walk_go", message}]} =
               Walk.screen_document(one_screen([element("button", "go", button(rows))]))

      assert message =~ "responses.card is written twice"
    end

    # Sabotage: made writes_findings/1's duplicate clause never match; the
    # duplicate rows validated :ok, then reverted.
    test "is a finding in the editor when one path is written twice" do
      rows = ["responses.card=family", "responses.card=standard"]

      assert {:error, [{"writes", "each response path is written once"}]} =
               ScreenEditor.Button.validate_config(Map.put(button(rows), "key", "go"))
    end
  end

  describe "what the walk refuses" do
    # Sabotage: made screen_document/1 accept a root of any type; the walk
    # answered :ok, then reverted.
    test "a root that is not a sequence of screens" do
      root = Block.new("myapp.screens.screen", id: "blk_walk_root", config: %{"key" => "lone"})

      assert {:error, [{"blk_walk_root", _message}]} =
               Walk.screen_document(Document.new(root, id: "sdoc_walk"))
    end

    # Sabotage: widened walk_element/1's guard to any type name; the nested
    # screen walked as an element, then reverted.
    test "a block in an elements slot that is not an element, and one in the body that is not a screen" do
      nested = Block.new("myapp.screens.screen", id: "blk_walk_nested", config: %{"key" => "x"})
      wait = Block.new("core.wait", id: "blk_walk_wait", config: %{"duration" => "1s"})
      stray = Block.new("myapp.screens.text", id: "blk_walk_stray", config: %{"key" => "stray"})
      screen = screen_block([nested, wait])
      root = Block.new("core.sequence", id: "blk_walk_root", slots: %{"body" => [screen, stray]})

      assert {:error, [{"blk_walk_nested", _}, {"blk_walk_wait", _}, {"blk_walk_stray", _}]} =
               Walk.screen_document(Document.new(root, id: "sdoc_walk"))
    end

    # Sabotage: made checks/1 keep the rows as written; the checks case
    # answered :ok, then reverted from a copy.
    test "a check row, an option description or a step it cannot read" do
      choice = %{
        "label" => "Card",
        "select" => "one",
        "answer_options" => ["standard=Standard card"],
        "option_descriptions" => ["student=Ages 12 to 18"]
      }

      cases = [
        element("text_question", "age", %{"label" => "Age", "checks" => ["responses.age > 0"]}),
        element("choice_question", "card", choice),
        element("text_question", "items", %{"label" => "Items", "step" => "one"})
      ]

      for block <- cases do
        assert {:error, [{id, _message}]} = Walk.screen_document(one_screen([block]))
        assert id == block.id
      end
    end

    # Sabotage: made bounds/1 convert a date bound like a number; the walk
    # refused the date question, then reverted from a copy.
    test "keeps a date or time bound as the text it is" do
      for {format, min} <- [
            {"date", "1900-01-01"},
            {"time", "09:00"},
            {"datetime", "2026-01-01T09:00:00Z"}
          ] do
        question = %{"label" => "When", "format" => format, "min" => min}

        assert {:ok, walked} =
                 Walk.screen_document(one_screen([element("text_question", "when", question)]))

        assert %{"min" => ^min} =
                 walked |> Map.fetch!("screens") |> hd() |> Map.fetch!("elements") |> hd()
      end
    end

    # Sabotage: made options/1 pass an unreadable option row through; the
    # choice question case answered :ok, then reverted.
    test "an option row, a bound or a write row it cannot read" do
      cases = [
        element("choice_question", "card", %{
          "label" => "Card",
          "select" => "one",
          "answer_options" => ["standard"]
        }),
        element("text_question", "age", %{"label" => "Age", "min" => "ten"}),
        element("button", "go", button(["card=family"]))
      ]

      for block <- cases do
        assert {:error, [{id, _message}]} = Walk.screen_document(one_screen([block]))
        assert id == block.id
      end
    end
  end

  # The shipped screen document authored as the screen editor would hold
  # it: a core.sequence of screen blocks, each node a block of its type,
  # the options and writes as the editor's rows.
  defp author(fixture) do
    screens =
      for screen <- fixture["screens"] do
        Block.new("myapp.screens.screen",
          id: "blk_screen_" <> screen["key"],
          config: Map.take(screen, ["key", "title"]),
          slots: %{"elements" => Enum.map(screen["nodes"], &author_node/1)}
        )
      end

    root = Block.new("core.sequence", id: "blk_root", slots: %{"body" => screens})
    Document.new(root, id: fixture["id"], metadata: fixture["metadata"])
  end

  defp author_node(%{"type" => type, "key" => key} = node_doc) do
    config =
      node_doc
      |> Map.drop(["type", "nodes"])
      |> Map.update("writes", [], &write_rows/1)
      |> Map.update("answer_options", [], &option_rows/1)
      |> Enum.reject(fn {field, value} ->
        field in ["writes", "answer_options"] and value == []
      end)
      |> Map.new()

    Block.new("myapp.screens." <> type,
      id: "blk_node_" <> key,
      config: config,
      slots:
        if(node_doc["nodes"],
          do: %{"elements" => Enum.map(node_doc["nodes"], &author_node/1)},
          else: %{}
        )
    )
  end

  defp write_rows(writes) do
    for {path, ["const", value]} <- Enum.sort(writes), do: path <> "=" <> row_value(value)
  end

  # A string the walk would read as JSON is written quoted; any other
  # string as itself, and every other value as its JSON.
  defp row_value(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, _json} -> Jason.encode!(value)
      {:error, _text} -> value
    end
  end

  defp row_value(value), do: Jason.encode!(value)

  defp option_rows(options), do: Enum.map(options, &(&1["value"] <> "=" <> &1["label"]))

  defp registration do
    {:ok, document} = @registration |> File.read!() |> Document.from_json()
    document
  end

  defp writes(rows) do
    {:ok, walked} = Walk.screen_document(one_screen([element("button", "go", button(rows))]))

    walked
    |> Map.fetch!("screens")
    |> hd()
    |> Map.fetch!("elements")
    |> hd()
    |> Map.fetch!("writes")
  end

  defp button(rows), do: %{"label" => "Go", "outcome" => "went_on", "writes" => rows}

  defp one_screen(elements) do
    root =
      Block.new("core.sequence",
        id: "blk_walk_root",
        slots: %{"body" => [screen_block(elements)]}
      )

    Document.new(root, id: "sdoc_walk")
  end

  defp screen_block(elements) do
    Block.new("myapp.screens.screen",
      id: "blk_walk_screen",
      config: %{"key" => "patron_details", "title" => "Your details"},
      slots: %{"elements" => elements}
    )
  end

  defp element(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_walk_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
