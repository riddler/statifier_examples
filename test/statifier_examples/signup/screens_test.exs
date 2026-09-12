defmodule StatifierExamples.Signup.ScreensTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.Signup.Screens

  doctest Screens

  @answered %{
    "answers" => %{
      "first_name" => "Ada",
      "email" => "ada@example.com",
      "seats" => 4
    }
  }

  describe "screens/0" do
    test "reads the three signup screens in document order" do
      assert [%{key: "account"}, %{key: "plan"}, %{key: "confirm"}] = Screens.screens()
    end

    test "every node carries a key and one of the four skeleton types" do
      for screen <- Screens.screens(), node <- screen.nodes do
        assert is_binary(node["key"])
        assert node["type"] in ~w(heading text text_question button)
      end
    end
  end

  describe "resolve/2 per element type" do
    # Sabotage: dropping the `level` key from the fixture's heading node
    # leaves `@node["level"]` nil, the `<h1>` arm stops matching, and this
    # goes red on the level assertion.
    test "a heading keeps its level and its text" do
      node = resolved_node("account", @answered, "account_heading")

      assert node["type"] == "heading"
      assert node["level"] == 1
      assert node["text"] == "Create your account"
    end

    # Sabotage: making `fill_node/2` fall through for "text" leaves the raw
    # `{{ answers.first_name }}` in place and this assertion fails.
    test "a text node has its slot filled from the datamodel" do
      node = resolved_node("account", @answered, "account_greeting")

      assert node["text"] == "Nice to meet you, Ada."
      refute node["text"] =~ "{{"
    end

    # Sabotage: renaming the fixture's `label` key makes this nil.
    test "a text_question carries its label, placeholder and required flag" do
      node = resolved_node("account", @answered, "first_name")

      assert node["label"] == "First name"
      assert node["placeholder"] == "Ada"
      assert node["required"] == true
    end

    # Sabotage: emptying `outcomes/1`'s comprehension filter returns every
    # node's outcome (nil for three of them) and the match fails.
    test "a button declares an outcome name" do
      node = resolved_node("account", @answered, "account_continue")

      assert node["outcome"] == "account_submitted"
      assert Screens.outcomes(Screens.screen("account")) == ["account_submitted"]
    end
  end

  describe "resolve/2 and conditions" do
    # Sabotage: making `shown?/2` return true for a non-true evaluation
    # lets the greeting through on an empty datamodel and this goes red.
    test "a node whose condition does not hold is not in the resolved list" do
      keys = resolved_keys("account", %{"answers" => %{}})

      refute "account_greeting" in keys
      assert "account_heading" in keys
      assert "first_name" in keys
    end

    test "the same node appears once its condition holds" do
      assert "account_greeting" in resolved_keys("account", @answered)
    end

    # Predicator answers a missing path two different ways, and both have to
    # hide: a datamodel holding `answers` but not `seats` evaluates to
    # `{:ok, :undefined}`, while one with no `answers` root at all is an
    # `{:error, %UndefinedVariableError{}}`. The first screen is rendered
    # against the second shape before anything is answered.
    test "an unanswered path hides rather than raises, in both shapes" do
      node = %{"condition" => "answers.seats > 1"}

      assert Predicator.evaluate("answers.seats > 1", %{"answers" => %{}}) == {:ok, :undefined}
      assert {:error, _no_root} = Predicator.evaluate("answers.seats > 1", %{})

      refute Screens.shown?(node, %{"answers" => %{}})
      refute Screens.shown?(node, %{})
    end

    test "source that does not parse hides rather than raising" do
      refute Screens.shown?(%{"condition" => "answers.seats >"}, %{"answers" => %{"seats" => 4}})
    end

    test "the plan screen swaps its button on the seat count" do
      personal = resolved_keys("plan", %{"answers" => %{"seats" => 1}})
      business = resolved_keys("plan", %{"answers" => %{"seats" => 5}})

      assert "plan_personal" in personal
      refute "plan_business" in personal
      assert "plan_business" in business
      refute "plan_personal" in business
    end
  end

  describe "fill_slots/2" do
    test "an unresolved path renders as the empty string" do
      assert Screens.fill_slots("To {{ answers.email }}.", %{"answers" => %{}}) == "To ."
      assert Screens.fill_slots("To {{ nope.at.all }}.", %{}) == "To ."
    end

    test "a non-string value is stringified" do
      assert Screens.fill_slots("{{ answers.seats }}", %{"answers" => %{"seats" => 4}}) == "4"
    end

    test "text with no slot is returned unchanged" do
      assert Screens.fill_slots("Nothing to fill", @answered) == "Nothing to fill"
    end
  end

  describe "answer_keys/1" do
    test "answers are keyed by element key" do
      assert Screens.answer_keys(Screens.screen("account")) == ["first_name", "email"]
    end
  end

  describe "screen/1" do
    test "an unknown key is nil" do
      refute Screens.screen("no-such-screen")
    end
  end

  defp resolved_keys(key, datamodel) do
    key |> Screens.screen() |> Screens.resolve(datamodel) |> Enum.map(& &1["key"])
  end

  defp resolved_node(key, datamodel, node_key) do
    key
    |> Screens.screen()
    |> Screens.resolve(datamodel)
    |> Enum.find(&(&1["key"] == node_key))
  end
end
