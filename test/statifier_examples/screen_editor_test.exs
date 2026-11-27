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

  doctest StatifierExamples.ScreenEditor.Element
  doctest StatifierExamples.ScreenEditor.ChoiceQuestion
  doctest StatifierExamples.ScreenEditor.TextQuestion

  @element_types ~w(heading text text_question choice_question boolean_question secret_question button variant image divider link)

  describe "the palette" do
    test "registers the screen and every element type under the document's own names" do
      assert Enum.map(ScreenEditor.registrations(), &elem(&1, 0)) ==
               ["myapp.screens.screen" | Enum.map(@element_types, &("myapp.screens." <> &1))]
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
               ~w(key condition label placeholder help required format pattern min max style step checks)

      assert fields("choice_question") ==
               ~w(key condition label select answer_options option_descriptions style help default required min_selections max_selections checks)

      assert fields("boolean_question") == ~w(key condition label help required checks)
      assert fields("secret_question") == ~w(key condition label help required checks)
      assert fields("button") == ~w(key condition label outcome writes style validates)
      assert fields("variant") == ~w(key condition)
      assert fields("image") == ~w(key condition src alt size fit)
      assert fields("divider") == ~w(key condition)
      assert fields("link") == ~w(key condition label href style)
    end

    test "requires no style of a button, and a select of a choice question" do
      assert %{required?: false} = field("button", "style")
      assert %{required?: true, type: {:select, selects}} = field("choice_question", "select")
      assert Enum.map(selects, &elem(&1, 0)) == ["one", "many"]
    end

    test "gives a screen and a variant an elements slot, and no element any other" do
      for {name, module} <- ScreenEditor.registrations() do
        slots = Enum.map(module.slots(%{}), &elem(&1, 0))

        if name in ["myapp.screens.screen", "myapp.screens.variant"],
          do: assert(slots == ["elements"]),
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

    # Sabotage: took "slider" out of the text question's style candidates;
    # the text question assertion went red, then reverted from a copy.
    test "offers riddler's hint names for a text question, an image and a link" do
      candidates = ScreenEditor.field_candidates()

      assert names(candidates, "text_question", "style") == ~w(multiline slider stepper)
      assert names(candidates, "image", "size") == ~w(icon avatar small medium large banner)
      assert names(candidates, "image", "fit") == ~w(contain cover)
      assert names(candidates, "link", "style") == ~w(inline button)
    end

    test "offers the date and time formats as choices of a text question's format" do
      assert %{type: {:select, formats}} = field("text_question", "format")

      assert Enum.map(formats, &elem(&1, 0)) -- [""] ==
               ~w(email phone pattern integer number date time datetime)
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
    test "refuses an element key that is not key-shaped" do
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

    # Sabotage: dropped the min-above-the-option-count clause from
    # bound_findings/3; the min_selections 3 case went red, then reverted.
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

      assert {:error, [{"min_selections", _}]} =
               validate(
                 "choice_question",
                 choice(%{"select" => "many", "min_selections" => 3, "max_selections" => nil})
               )
    end

    test "holds a button to a key-shaped outcome and writes of responses.<path>=value" do
      button = %{"key" => "go", "label" => "Continue", "outcome" => "details_submitted"}

      assert :ok = validate("button", Map.put(button, "writes", ["responses.card=family"]))

      assert {:error, [{"writes", _}]} =
               validate("button", Map.put(button, "writes", ["card=family"]))

      assert {:error, [{"outcome", _}]} = validate("button", %{button | "outcome" => ""})
    end

    # Sabotage: made validate_config/1 skip Element.present/3 on "alt";
    # the blank alt case answered :ok, then reverted from a copy.
    test "holds an image to a source and an alt text, and a link to a label and a URL" do
      image = %{"key" => "logo", "src" => "/images/logo.svg", "alt" => "Riverbend"}
      assert :ok = validate("image", image)
      assert {:error, [{"alt", _}]} = validate("image", %{image | "alt" => ""})
      assert {:error, [{"src", _}]} = validate("image", Map.delete(image, "src"))

      link = %{"key" => "rules", "label" => "Lending rules", "href" => "/lending-rules"}
      assert :ok = validate("link", link)
      assert {:error, [{"href", _}]} = validate("link", %{link | "href" => " "})
      assert :ok = validate("divider", %{"key" => "rule"})
    end

    # Sabotage: made bound_findings/2 hold a date bound to being a number;
    # the date bound case went red, then reverted from a copy.
    test "reads a date bound as text, and holds a step to a number" do
      question = %{"key" => "birth_date", "label" => "Date of birth", "format" => "date"}
      assert :ok = validate("text_question", Map.put(question, "min", "1900-01-01"))

      slider = %{"key" => "items", "label" => "Items", "format" => "integer"}
      assert :ok = validate("text_question", Map.put(slider, "step", "1"))
      assert {:error, [{"step", _}]} = validate("text_question", Map.put(slider, "step", "one"))
    end

    # Sabotage: dropped the membership test from option_descriptions/2; the
    # row naming no option validated :ok, then reverted from a copy.
    test "holds an option description to value=Description, naming an option once" do
      assert :ok =
               validate(
                 "choice_question",
                 choice(%{"option_descriptions" => ["family=Two adults"]})
               )

      for rows <- [["student=Ages 12 to 18"], ["family"], ["family=A", "family=B"]] do
        assert {:error, [{"option_descriptions", _}]} =
                 validate("choice_question", choice(%{"option_descriptions" => rows}))
      end
    end

    # Sabotage: made check_row/1 accept a code outside the check. shape; the
    # "adult:" row validated :ok, then reverted from a copy.
    test "holds a question's checks to code: condition => message, each code once" do
      row = "check.adult: responses.age::integer >= 18 => You must be 18 or over."
      question = %{"key" => "age", "label" => "Age"}

      for type <- ~w(text_question boolean_question secret_question) do
        assert :ok = validate(type, Map.put(question, "checks", [row]))
      end

      assert :ok = validate("choice_question", choice(%{"checks" => [row]}))

      for rows <- [
            ["adult: responses.age >= 18 => You must be 18."],
            ["check.adult: responses.age >= 18"],
            ["check.adult:  => You must be 18."],
            [row, row]
          ] do
        assert {:error, [{"checks", _}]} =
                 validate("text_question", Map.put(question, "checks", rows))
      end
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

  defp names(candidates, type, field) do
    {:open, pairs} = Map.fetch!(candidates, {"myapp.screens." <> type, field})
    Enum.map(pairs, &elem(&1, 0))
  end

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
  # a variant with a conditional and a default candidate, an image, a
  # divider, a link and a button.
  defp registration do
    elements = [
      element("heading", "title", %{"level" => 1, "text" => "Register for a library card"}),
      element("text", "intro", %{"text" => "It takes a minute."}),
      element("text_question", "first_name", %{"label" => "First name", "required" => true}),
      element("text_question", "email", %{"label" => "Email", "format" => "email"}),
      element("choice_question", "card_type", Map.delete(choice(%{}), "key")),
      element("boolean_question", "lending_rules", %{
        "label" => "I agree to the lending rules",
        "required" => true
      }),
      Block.new("myapp.screens.variant",
        id: "blk_pr_notice",
        config: %{"key" => "notice"},
        slots: %{
          "elements" => [
            element("text", "family_notice", %{
              "text" => "A family card covers two adults.",
              "condition" => "responses.card_type == 'family'"
            }),
            element("text", "default_notice", %{"text" => "Welcome."})
          ]
        }
      ),
      element("image", "logo", %{"src" => "/images/logo.svg", "alt" => "Riverbend"}),
      element("divider", "rule", %{}),
      element("link", "rules", %{"label" => "Lending rules", "href" => "/lending-rules"}),
      element("button", "continue", %{"label" => "Continue", "outcome" => "details_submitted"})
    ]

    screen =
      Block.new("myapp.screens.screen",
        id: "blk_pr_details",
        config: %{"key" => "patron_details", "title" => "Your details"},
        slots: %{"elements" => elements}
      )

    Document.new(Block.new("core.sequence", id: "blk_pr_root", slots: %{"body" => [screen]}))
  end

  defp element(type, key, config) do
    Block.new("myapp.screens." <> type,
      id: "blk_pr_" <> key,
      config: Map.put(config, "key", key)
    )
  end
end
