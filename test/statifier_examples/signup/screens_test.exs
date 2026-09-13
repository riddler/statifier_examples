defmodule StatifierExamples.Signup.ScreensTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.Signup.Screens

  doctest Screens

  @answered %{
    "responses" => %{
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
    # Sabotage: `resolve/2` returning `[]` leaves `resolved_node/3` nothing
    # to find, and all three assertions here read off `nil`. Confirmed red,
    # then reverted from a copy.
    #
    # What does NOT discriminate here, since the shape invites the guess:
    # dropping "heading" from `fill_node/2`'s `when type in [...]` guard
    # leaves this case green. That mutation only stops slots being filled,
    # and no heading in `priv/fixtures/signup_screens.json` carries one -
    # there are four, and this one's text is the literal "Create your
    # account". The heading arm of the guard is therefore uncovered by any
    # case in this file; the `text` arm is covered by the case below.
    test "a heading keeps its level and its text" do
      node = resolved_node("account", @answered, "account_heading")

      assert node["type"] == "heading"
      assert node["level"] == 1
      assert node["text"] == "Create your account"
    end

    # Sabotage: replacing `fill_node/2`'s `Map.update!(node_doc, "text",
    # ...)` with a bare `node_doc` leaves the raw `{{ responses.first_name }}`
    # in place and this assertion fails. Confirmed red, then reverted.
    test "a text node has its slot filled from the datamodel" do
      node = resolved_node("account", @answered, "account_greeting")

      assert node["text"] == "Nice to meet you, Ada."
      refute node["text"] =~ "{{"
    end

    # Sabotage: `resolve/2` returning `[]` leaves `resolved_node/3` nothing
    # to find, and all three assertions here read off `nil`. Confirmed red,
    # then reverted from a copy.
    #
    # Two nearer mutations do NOT discriminate this case. Dropping
    # `resolve/2`'s `Enum.map(&fill_node/2)` leaves it green: a
    # `text_question` falls through `fill_node/2` untouched anyway, and
    # `label`, `placeholder` and `required` hold no slots. And `shown?/2`
    # returning true for a non-true evaluation leaves it green too, because
    # `first_name` carries no `condition` and is kept either way - the
    # `shown?/2` mutation is discriminated by the condition cases below,
    # not by this one. Kept for the type's shape rather than its
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
      keys = resolved_keys("account", %{"responses" => %{}})

      refute "account_greeting" in keys
      assert "account_heading" in keys
      assert "first_name" in keys
    end

    test "the same node appears once its condition holds" do
      assert "account_greeting" in resolved_keys("account", @answered)
    end

    # Predicator answers a missing path two different ways, and both have to
    # hide: a datamodel holding `responses` but not `seats` evaluates to
    # `{:ok, :undefined}`, while one with no `responses` root at all is an
    # `{:error, %UndefinedVariableError{}}`. `SignupScreensLive` always
    # supplies the root, so the page only ever meets the first; a caller
    # handing over a bare map meets the second.
    test "an unanswered path hides rather than raises, in both shapes" do
      node = %{"condition" => "responses.seats > 1"}

      assert Predicator.evaluate("responses.seats > 1", %{"responses" => %{}}) ==
               {:ok, :undefined}

      assert {:error, _no_root} = Predicator.evaluate("responses.seats > 1", %{})

      refute Screens.shown?(node, %{"responses" => %{}})
      refute Screens.shown?(node, %{})
    end

    test "source that does not parse hides rather than raising" do
      refute Screens.shown?(%{"condition" => "responses.seats >"}, %{
               "responses" => %{"seats" => 4}
             })
    end

    test "the plan screen swaps its button on the seat count" do
      personal = resolved_keys("plan", %{"responses" => %{"seats" => 1}})
      business = resolved_keys("plan", %{"responses" => %{"seats" => 5}})

      assert "plan_personal" in personal
      refute "plan_business" in personal
      assert "plan_business" in business
      refute "plan_personal" in business
    end
  end

  describe "fill_slots/2" do
    test "an unresolved path renders as the empty string" do
      assert Screens.fill_slots("To {{ responses.email }}.", %{"responses" => %{}}) == "To ."
      assert Screens.fill_slots("To {{ nope.at.all }}.", %{}) == "To ."
    end

    test "a non-string value is stringified" do
      assert Screens.fill_slots("{{ responses.seats }}", %{"responses" => %{"seats" => 4}}) == "4"
    end

    # Sabotage: `stringify/1`'s catch-all clause calling `to_string/1`
    # instead of returning "" raises `Protocol.UndefinedError` here.
    # Confirmed red, then reverted.
    test "a slot naming a whole subtree renders as the empty string" do
      assert Screens.fill_slots("[{{ responses }}]", @answered) == "[]"

      assert Screens.fill_slots("[{{ responses.tags }}]", %{"responses" => %{"tags" => []}}) ==
               "[]"
    end

    test "text with no slot is returned unchanged" do
      assert Screens.fill_slots("Nothing to fill", @answered) == "Nothing to fill"
    end
  end

  describe "response_keys/1" do
    test "responses are keyed by element key" do
      assert Screens.response_keys(Screens.screen("account")) == ["first_name", "email"]
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
