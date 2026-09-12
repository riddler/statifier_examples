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
    # Sabotage: `fill_node/2` falling through for "heading" (dropping the
    # type from its `when type in [...]` guard) leaves the node untouched,
    # and this goes red on any heading whose text carries a slot. Run as part
    # of the `fill_node/2` mutation below, which covers both arms.
    test "a heading keeps its level and its text" do
      node = resolved_node("account", @answered, "account_heading")

      assert node["type"] == "heading"
      assert node["level"] == 1
      assert node["text"] == "Create your account"
    end

    # Sabotage: replacing `fill_node/2`'s `Map.update!(node_doc, "text",
    # ...)` with a bare `node_doc` leaves the raw `{{ answers.first_name }}`
    # in place and this assertion fails. Confirmed red, then reverted.
    test "a text node has its slot filled from the datamodel" do
      node = resolved_node("account", @answered, "account_greeting")

      assert node["text"] == "Nice to meet you, Ada."
      refute node["text"] =~ "{{"
    end

    # Sabotage: `resolve/2` dropping its `Enum.map(&fill_node/2)` returns
    # the document's nodes unresolved; this case still reads `label` off a
    # node the filter kept, so it is the `shown?/2` mutation below that this
    # case goes red under. Kept for the type's shape rather than its
    # resolution.
    test "a text_question carries its label, placeholder and required flag" do
      node = resolved_node("account", @answered, "first_name")

      assert node["label"] == "First name"
      assert node["placeholder"] == "Ada"
      assert node["required"] == true
    end

    # Sabotage: widening `outcomes/1`'s comprehension to every node and its
    # `Map.fetch!` to `Map.get` returns `[nil, nil, nil, nil, nil,
    # "account_submitted"]` and the match fails. Leaving `Map.fetch!` in
    # place instead raises `KeyError` on the first heading, which is red for
    # a different reason - either way this case discriminates. Confirmed red,
    # then reverted.
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
    # `{:error, %UndefinedVariableError{}}`. `SignupScreensLive` always
    # supplies the root, so the page only ever meets the first; a caller
    # handing over a bare map meets the second.
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

    # Sabotage: `stringify/1`'s catch-all clause calling `to_string/1`
    # instead of returning "" raises `Protocol.UndefinedError` here.
    # Confirmed red, then reverted.
    test "a slot naming a whole subtree renders as the empty string" do
      assert Screens.fill_slots("[{{ answers }}]", @answered) == "[]"
      assert Screens.fill_slots("[{{ answers.tags }}]", %{"answers" => %{"tags" => []}}) == "[]"
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
