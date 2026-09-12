defmodule StatifierExamples.Signup.ValidationTest do
  @moduledoc """
  The stand-in for Riddler R10c's elements package: the two rules a screen's
  questions can declare, and the three things this module deliberately does
  not do.

  A pure test - nothing here names a run, a chart or LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierExamples.Signup.{Screens, Validation}

  doctest Validation

  defp question(extra),
    do: Map.merge(%{"type" => "text_question", "key" => "q", "label" => "Q"}, extra)

  describe "required" do
    test "an empty required answer is a finding, and a blank one is too" do
      nodes = [question(%{"required" => true})]

      assert Validation.validate(nodes, %{"q" => ""}) == [{"q", "is required"}]
      assert Validation.validate(nodes, %{"q" => "   "}) == [{"q", "is required"}]
      assert Validation.validate(nodes, %{}) == [{"q", "is required"}]
    end

    # Sabotage: made `check/2` test `Map.get(question, "required")` for
    # truthiness instead of `== true`. FIVE cases went red including this one,
    # though not in the way the mutation suggests: a question declaring no
    # `required` key answers `nil`, and `nil and _` raises `BadBooleanError`
    # rather than reading as false, so every case over a question without the
    # key crashed - this one, both email cases, the empty-optional case and
    # the unknown-format raise. Reverted from a copy.
    test "`required` is the document's boolean, not anything truthy" do
      assert Validation.validate([question(%{"required" => "yes"})], %{"q" => ""}) == []
    end

    test "an answered required question is nothing at all" do
      assert Validation.validate([question(%{"required" => true})], %{"q" => "Ada"}) == []
    end

    # Answers reach this module as a form posts them, but a re-validated
    # screen is validated against what `Journey.submit/3` coerced, so a
    # number has to count as answered.
    test "a numeric answer is not blank" do
      assert Validation.validate([question(%{"required" => true})], %{"q" => 5}) == []
    end
  end

  describe "format" do
    # Sabotage: dropped the start/end anchors from `@email`. Exactly this case
    # went red, on the last typo in its list: "ada@example.com is mine" holds an
    # address and an unanchored regex finds it. The three typos before it still
    # failed, which is why the list has that one in it. Reverted from a copy.
    test "email rejects what a reader would call a typo" do
      nodes = [question(%{"format" => "email"})]
      message = "must look like an email address"

      for typo <- ["ada", "ada@", "@example.com", "ada@example", "ada@example.com is mine"] do
        assert Validation.validate(nodes, %{"q" => typo}) == [{"q", message}]
      end
    end

    test "email accepts an ordinary address" do
      assert Validation.validate([question(%{"format" => "email"})], %{"q" => "ada@example.com"}) ==
               []
    end

    # A format is checked only when there is something to check: an optional
    # question left empty is not a malformed answer, and reporting it as one
    # would make every `format` imply `required`.
    test "an empty optional answer is not a format failure" do
      assert Validation.validate([question(%{"format" => "email"})], %{"q" => ""}) == []
    end

    # The moduledoc's argument: a document asking for a check nobody runs is
    # a document that silently accepts anything.
    test "a format this module does not implement raises" do
      assert_raise ArgumentError, ~r/no check for format "phone"/, fn ->
        Validation.validate([question(%{"format" => "phone"})], %{"q" => "x"})
      end
    end
  end

  describe "what it is given, and what it therefore checks" do
    # The whole reason it takes resolved nodes. `resolve/2` has already
    # dropped what a condition hides, so a required question the reader
    # never saw cannot refuse their submission.
    test "only text_question nodes are checked" do
      nodes = [
        %{"type" => "heading", "key" => "h", "level" => 1, "text" => "Hi", "required" => true},
        %{"type" => "button", "key" => "b", "label" => "Go", "outcome" => "went"}
      ]

      assert Validation.validate(nodes, %{}) == []
    end

    test "one finding per question, in document order" do
      nodes = [
        question(%{"key" => "a", "required" => true}),
        question(%{"key" => "b", "required" => true, "format" => "email"})
      ]

      assert Validation.validate(nodes, %{}) == [{"a", "is required"}, {"b", "is required"}]
    end

    # Two rules about one empty box are one mistake told twice.
    test "a required question with a format reports the emptiness only" do
      nodes = [question(%{"required" => true, "format" => "email"})]

      assert Validation.validate(nodes, %{"q" => ""}) == [{"q", "is required"}]
    end
  end

  describe "against the shipped element document" do
    # The rules this app actually ships, read off the fixture rather than
    # restated: the account screen asks for a name and a work address, and
    # the address carries the `format` se-7wt added to it.
    test "the account screen refuses an empty form and accepts a filled one" do
      nodes = Screens.resolve(Screens.screen("account"), %{})

      assert Validation.validate(nodes, %{}) == [
               {"first_name", "is required"},
               {"email", "is required"}
             ]

      assert Validation.validate(nodes, %{
               "first_name" => "Ada",
               "email" => "ada@example.com"
             }) == []
    end

    test "the account screen refuses a malformed address" do
      nodes = Screens.resolve(Screens.screen("account"), %{})

      assert Validation.validate(nodes, %{"first_name" => "Ada", "email" => "ada"}) ==
               [{"email", "must look like an email address"}]
    end

    # The plan screen's seat count is optional, which is what lets the
    # personal button be reachable without typing anything.
    test "the plan screen demands nothing" do
      nodes = Screens.resolve(Screens.screen("plan"), %{"answers" => %{"seats" => 1}})

      assert Validation.validate(nodes, %{}) == []
    end
  end
end
