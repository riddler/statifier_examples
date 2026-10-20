defmodule StatifierExamples.ScreenEditorTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Document
  alias StatifierBlocks.Palette
  alias StatifierBlocks.Shell
  alias StatifierExamples.Charts
  alias StatifierExamples.ScreenEditor
  alias StatifierExamples.ScreenEditor.ChoiceQuestion

  doctest StatifierExamples.ScreenEditor.Node
  doctest StatifierExamples.ScreenEditor.ChoiceQuestion

  @node_types ~w(heading text text_question choice_question boolean_question button variant)

  describe "the palette" do
    test "registers the screen and every node type under the document's own names" do
      assert Enum.map(ScreenEditor.registrations(), &elem(&1, 0)) ==
               ["myapp.screens.screen" | Enum.map(@node_types, &("myapp.screens." <> &1))]
    end

    test "resolves every type, preflights clean and draws every icon" do
      palette = ScreenEditor.palette()

      assert Palette.preflight(palette) == []

      for {name, module} <- ScreenEditor.registrations() do
        assert {:ok, ^module} = Palette.fetch(palette, name)
        assert %{group: "Screens", icon: icon} = module.palette_entry()
        assert Charts.icon(icon) == icon
      end
    end

    # Sabotage: renamed the choice question's "answer_options" field to
    # "options"; the field-name assertion went red, then reverted.
    test "spells each field as the screen document does" do
      assert fields("screen") == ~w(key title)
      assert fields("heading") == ~w(key condition level text)
      assert fields("text") == ~w(key condition text)

      assert fields("text_question") ==
               ~w(key condition label placeholder required format pattern min max)

      assert fields("choice_question") ==
               ~w(key condition label select answer_options style required min_selections max_selections)

      assert fields("boolean_question") == ~w(key condition label required)
      assert fields("button") == ~w(key condition label outcome writes style validates)
      assert fields("variant") == ~w(key condition)
    end

    test "requires no style of a button, and a select of a choice question" do
      assert %{required?: false} = field("button", "style")
      assert %{required?: true, type: {:select, selects}} = field("choice_question", "select")
      assert Enum.map(selects, &elem(&1, 0)) == ["one", "many"]
    end

    test "gives a screen and a variant a nodes slot, and no node any other" do
      for {name, module} <- ScreenEditor.registrations() do
        slots = Enum.map(module.slots(%{}), &elem(&1, 0))

        if name in ["myapp.screens.screen", "myapp.screens.variant"],
          do: assert(slots == ["nodes"]),
          else: assert(slots == [])
      end
    end
  end

  describe "the profile" do
    # Sabotage: added :tables to the profile's drawer tabs; the drawer
    # assertion went red, then reverted.
    test "hides the chart-only surfaces and keeps Source" do
      profile = ScreenEditor.profile()

      assert Shell.drawer_tabs(profile.drawer_tabs) == [:findings, :source]
      assert Shell.inspector_tabs(profile.inspector_tabs) == [:config, :findings]
      assert profile.run? == false
      assert profile.palette_groups == ["Screens"]
    end

    test "offers the four choice styles as an open list" do
      assert %{{"myapp.screens.choice_question", "style"} => {:open, styles}} =
               ScreenEditor.field_candidates()

      assert Enum.map(styles, &elem(&1, 0)) == ~w(radio dropdown checkboxes list)
    end
  end

  describe "a patron registration document" do
    # Sabotage: made the button refuse every config; the compile went red
    # with a finding on the button, then reverted.
    test "compiles with no findings" do
      assert {:ok, _compiled} = Compiler.compile(registration(), ScreenEditor.palette())
    end
  end

  describe "validate_config/1" do
    test "refuses a node key that is not key-shaped" do
      assert {:error, [{"key", _message}]} =
               validate("text", %{"key" => "Welcome", "text" => "Hello"})
    end

    test "refuses a heading level outside 1 to 6, and a blank text" do
      assert {:error, [{"level", _}, {"text", _}]} =
               validate("heading", %{"key" => "title", "level" => 7, "text" => ""})
    end

    test "refuses a text question bound that is not a number" do
      assert {:error, [{"min", _}]} =
               validate("text_question", %{"key" => "age", "label" => "Age", "min" => "ten"})

      assert :ok =
               validate("text_question", %{"key" => "age", "label" => "Age", "max" => "120.5"})
    end

    # Sabotage: dropped the uniqueness clause from value_findings/1; the
    # duplicate-value case went red, then reverted.
    test "holds a choice question's options to value=Label, key-shaped and unique" do
      assert :ok = validate("choice_question", choice(%{}))

      for rows <- [[], ["standard"], ["Standard=Standard card"], ["family=A", "family=B"]] do
        assert {:error, [{"answer_options", _}]} =
                 validate("choice_question", choice(%{"answer_options" => rows}))
      end
    end

    test "reads selection bounds on a select of many only" do
      assert {:error, [{"min_selections", _}]} =
               validate("choice_question", choice(%{"min_selections" => 1}))

      many = %{"select" => "many", "min_selections" => 1, "max_selections" => 2}
      assert :ok = validate("choice_question", choice(many))

      assert {:error, [{"min_selections", _}]} =
               validate("choice_question", choice(%{many | "min_selections" => 3}))

      assert {:error, [{"max_selections", _}]} =
               validate("choice_question", choice(%{many | "max_selections" => 3}))

      assert {:error, [{"min_selections", _}]} =
               validate("choice_question", choice(%{many | "min_selections" => -1}))
    end

    test "holds a button to a key-shaped outcome and writes of responses.<path>=value" do
      button = %{"key" => "go", "label" => "Continue", "outcome" => "details_submitted"}

      assert :ok = validate("button", Map.put(button, "writes", ["responses.card=family"]))

      assert {:error, [{"writes", _}]} =
               validate("button", Map.put(button, "writes", ["card=family"]))

      assert {:error, [{"outcome", _}]} = validate("button", %{button | "outcome" => ""})
    end

    test "parses the option rows a walk reads" do
      assert ChoiceQuestion.answer_options(["family=Family card = two adults"]) ==
               {:ok, [{"family", "Family card = two adults"}]}
    end
  end

  defp module(type), do: Map.new(ScreenEditor.registrations())["myapp.screens." <> type]

  defp fields(type), do: Enum.map(module(type).config_schema(%{}), & &1.key)

  defp field(type, key), do: Enum.find(module(type).config_schema(%{}), &(&1.key == key))

  defp validate(type, config), do: module(type).validate_config(config)

  defp choice(overrides) do
    Map.merge(
      %{
        "key" => "card_type",
        "label" => "Which card would you like?",
        "select" => "one",
        "answer_options" => ["standard=Standard card", "family=Family card"]
      },
      overrides
    )
  end

  # Every type once: one screen holding a heading, a text, each question,
  # a variant with a conditional and a default candidate, and a button.
  defp registration do
    nodes = [
      node("heading", "title", %{"level" => 1, "text" => "Register for a library card"}),
      node("text", "intro", %{"text" => "It takes a minute."}),
      node("text_question", "first_name", %{"label" => "First name", "required" => true}),
      node("text_question", "email", %{"label" => "Email", "format" => "email"}),
      node("choice_question", "card_type", Map.delete(choice(%{}), "key")),
      node("boolean_question", "lending_rules", %{
        "label" => "I agree to the lending rules",
        "required" => true
      }),
      Block.new("myapp.screens.variant",
        id: "blk_pr_notice",
        config: %{"key" => "notice"},
        slots: %{
          "nodes" => [
            node("text", "family_notice", %{
              "text" => "A family card covers two adults.",
              "condition" => "responses.card_type == 'family'"
            }),
            node("text", "default_notice", %{"text" => "Welcome."})
          ]
        }
      ),
      node("button", "continue", %{"label" => "Continue", "outcome" => "details_submitted"})
    ]

    screen =
      Block.new("myapp.screens.screen",
        id: "blk_pr_details",
        config: %{"key" => "patron_details", "title" => "Your details"},
        slots: %{"nodes" => nodes}
      )

    Document.new(Block.new("core.sequence", id: "blk_pr_root", slots: %{"body" => [screen]}))
  end

  defp node(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_pr_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
