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

      assert :ok = Document.validate(document)
      assert {:ok, _compiled} = Compiler.compile(document, ScreenEditor.palette())
      assert {:ok, ^fixture} = Walk.screen_document(document)
    end

    # Sabotage: made collect/2 return its answers reversed; the node keys
    # came out last first, then reverted.
    test "keeps each screen's nodes in the order they were authored" do
      {:ok, walked} = Walk.screen_document(author(Screens.document()))

      assert Enum.map(walked["screens"], & &1["key"]) == ~w(account plan confirm)

      assert walked["screens"] |> hd() |> Map.fetch!("nodes") |> Enum.map(& &1["key"]) ==
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
      nodes = Enum.flat_map(walked["screens"], & &1["nodes"])

      assert %{"select" => "one", "answer_options" => [%{"value" => "standard"} | _]} =
               Enum.find(nodes, &(&1["key"] == "card_type"))

      assert %{"select" => "many", "min_selections" => 0, "max_selections" => 3} =
               Enum.find(nodes, &(&1["key"] == "interests"))

      assert %{"type" => "boolean_question", "required" => true} =
               Enum.find(nodes, &(&1["key"] == "lending_rules"))
    end

    # Sabotage: made number/3 leave an integer bound as its text; the "min"
    # assertion went red, then reverted.
    test "turns the editor's own shapes back into the document's" do
      {:ok, walked} = Walk.screen_document(registration())
      nodes = Enum.flat_map(walked["screens"], & &1["nodes"])

      assert %{"min" => 0, "max" => 120} = Enum.find(nodes, &(&1["key"] == "age"))

      assert %{
               "writes" => %{
                 "responses.card_source" => ["const", "online"],
                 "responses.newsletter" => ["const", true]
               },
               "style" => "primary"
             } = Enum.find(nodes, &(&1["key"] == "card_finish"))

      assert %{"validates" => false} = Enum.find(nodes, &(&1["key"] == "card_back"))

      assert %{"type" => "variant", "nodes" => [%{"key" => "family_notice"}, _default]} =
               Enum.find(nodes, &(&1["key"] == "card_notice"))
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
    # and the empty writes came out, then reverted.
    test "leaves blank fields out and keeps false" do
      button = %{"label" => "Back", "outcome" => "went_back", "condition" => "", "writes" => []}
      question = %{"label" => "Nickname", "required" => false, "placeholder" => nil}

      {:ok, walked} =
        Walk.screen_document(
          one_screen([
            node("button", "back", button),
            node("text_question", "nickname", question)
          ])
        )

      assert [
               %{"type" => "button", "key" => "back", "label" => "Back", "outcome" => "went_back"} =
                 back,
               %{"key" => "nickname", "required" => false} = nickname
             ] = walked |> Map.fetch!("screens") |> hd() |> Map.fetch!("nodes")

      refute Map.has_key?(back, "condition")
      refute Map.has_key?(back, "writes")
      refute Map.has_key?(nickname, "placeholder")
      assert %{"schema_version" => 1, "id" => "sdoc_walk"} = walked
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
               Walk.screen_document(one_screen([node("button", "go", button(rows))]))

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

    # Sabotage: widened walk_node/1's guard to any type name; the nested
    # screen walked as a node, then reverted.
    test "a block in a nodes slot that is not a node, and one in the body that is not a screen" do
      nested = Block.new("myapp.screens.screen", id: "blk_walk_nested", config: %{"key" => "x"})
      wait = Block.new("core.wait", id: "blk_walk_wait", config: %{"duration" => "1s"})
      stray = Block.new("myapp.screens.text", id: "blk_walk_stray", config: %{"key" => "stray"})
      screen = screen_block([nested, wait])
      root = Block.new("core.sequence", id: "blk_walk_root", slots: %{"body" => [screen, stray]})

      assert {:error, [{"blk_walk_nested", _}, {"blk_walk_wait", _}, {"blk_walk_stray", _}]} =
               Walk.screen_document(Document.new(root, id: "sdoc_walk"))
    end

    # Sabotage: made options/1 pass an unreadable option row through; the
    # choice question case answered :ok, then reverted.
    test "an option row, a bound or a write row it cannot read" do
      cases = [
        node("choice_question", "card", %{
          "label" => "Card",
          "select" => "one",
          "answer_options" => ["standard"]
        }),
        node("text_question", "age", %{"label" => "Age", "min" => "ten"}),
        node("button", "go", button(["card=family"]))
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
          slots: %{"nodes" => Enum.map(screen["nodes"], &author_node/1)}
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
          do: %{"nodes" => Enum.map(node_doc["nodes"], &author_node/1)},
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
    {:ok, walked} = Walk.screen_document(one_screen([node("button", "go", button(rows))]))
    walked |> Map.fetch!("screens") |> hd() |> Map.fetch!("nodes") |> hd() |> Map.fetch!("writes")
  end

  defp button(rows), do: %{"label" => "Go", "outcome" => "went_on", "writes" => rows}

  defp one_screen(nodes) do
    root =
      Block.new("core.sequence", id: "blk_walk_root", slots: %{"body" => [screen_block(nodes)]})

    Document.new(root, id: "sdoc_walk")
  end

  defp screen_block(nodes) do
    Block.new("myapp.screens.screen",
      id: "blk_walk_screen",
      config: %{"key" => "patron_details", "title" => "Your details"},
      slots: %{"nodes" => nodes}
    )
  end

  defp node(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_walk_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
