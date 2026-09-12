defmodule StatifierExamples.Signup.PathTest do
  @moduledoc """
  The Path: `priv/fixtures/signup_path.json` over
  `priv/fixtures/signup_screens.json`, and the check that the two halves
  agree.

  Three things are asserted here, and the third is the one the spike went
  looking for. The Path **compiles** - three screens, a branch on what the
  second one recorded, and a timer alongside. Its buttons raise **distinct**
  events, which is what lets `StatifierExamples.Signup.Screen` leave the
  screen out of an event name. And the **environment walk** answers a
  question about `answers.*` that the bead left open: the paths are there,
  and every one of them is `:unknown`.

  A pure test: nothing here names LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Edit, Environment}
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.{Path, Screen, Screens}

  defp document, do: Path.document()
  defp palette, do: Charts.palette()

  describe "the Path compiles" do
    # Sabotage: pointed `blk_sp_plan`'s `screen` param at a key the element
    # document does not declare. THIS CASE STAYED GREEN - the screen expands
    # to a group with no handlers and the document still compiles - and six
    # others went red: both outcome-event cases, all three `validate/1` cases,
    # and the environment walk. That is the whole reason the validator
    # exists. The compiler never reads the element document, so a Path whose
    # two halves disagree is a Path that compiles. Reverted from a copy.
    test "green, with no warnings" do
      assert {:ok, %{warnings: [], record: record}} = Compiler.compile(document(), palette())
      assert record.document_id == "bdoc_signup_path"
      assert record.chart_identity.content_hash =~ "sha256:"
    end

    test "it holds three screens, a branch and a timer" do
      types = for %Block{type: type} <- Document.blocks(document()), do: type

      assert Enum.count(types, &(&1 == "myapp.screen")) == 3
      assert Enum.count(types, &(&1 == "core.branch")) == 1
      assert Enum.count(types, &(&1 == "core.send")) == 1
    end

    test "the branch reads what the plan screen's buttons record" do
      %Block{config: config} =
        Enum.find(Document.blocks(document()), &(&1.id == "blk_sp_plan_branch"))

      assert Enum.map(config["arms"], & &1["cond"]) == [
               "answers.plan == 'business'",
               "answers.plan == 'personal'"
             ]
    end
  end

  describe "the outcome events" do
    # `Screen.outcome_event/1` puts no screen in the name, so distinctness
    # across the Path is what keeps two screens' buttons from listening for
    # one event. `StatifierExamples.Signup.Path.validate/1` is the general
    # check; this is the shipped Path passing it.
    test "are distinct across the whole Path" do
      events = path_events()

      assert length(events) == 5
      assert Enum.uniq(events) == events
    end

    test "are the outcome names the buttons declare, prefixed" do
      assert path_events() == [
               "signup.account_submitted",
               "signup.personal_chosen",
               "signup.business_chosen",
               "signup.went_back",
               "signup.signup_confirmed"
             ]
    end
  end

  describe "the environment walk over answers.*" do
    # THE OPEN QUESTION THE BEAD LEFT: does the ADR-0011 walk see `answers.*`
    # typed? It sees the paths - all four, and only after the screens that
    # write them - and it types every one of them `:unknown`.
    #
    # Not an accident of this document: `StatifierBlocks.Environment` says a
    # `capture` map "writes `:unknown` at each of its keys, one per pair",
    # and its `capture_writes/1` builds that `:unknown` unconditionally, so
    # no declaration on this side can improve it. The ask is recorded in
    # `docs/spikes/SF040-signup-skeleton.md`; this case is what would go red
    # if the package ever answered otherwise.
    test "every answers path is present, and every one is :unknown" do
      env = Environment.at(palette(), document(), {"blk_sp_root", "body", 4})

      assert Enum.sort(Map.keys(env)) == [
               "answers.email",
               "answers.first_name",
               "answers.plan",
               "answers.seats"
             ]

      assert Enum.uniq(Map.values(env)) == [:unknown]
    end

    test "nothing is declared before the first screen has run" do
      assert Environment.at(palette(), document(), {"blk_sp_root", "body", 0}) == %{}
    end
  end

  describe "validate/1" do
    test "the shipped Path has nothing wrong with it" do
      assert Path.validate(document()) == []
    end

    test "it names every myapp.screen block, in document order" do
      assert Path.screen_refs(document()) == [
               {"blk_sp_account", "account"},
               {"blk_sp_plan", "plan"},
               {"blk_sp_confirm", "confirm"}
             ]
    end

    test "a screen the element document does not declare is a finding" do
      document = repoint("blk_sp_confirm", "not_a_screen")

      assert {:unknown_screen, "blk_sp_confirm", "not_a_screen"} in Path.validate(document)
    end

    # R10d, and the reason the finding names blocks rather than screens: one
    # screen shown twice reaches its element keys twice, and the second visit
    # overwrites what the first one collected.
    test "a screen shown twice duplicates its element keys and its outcomes" do
      document = repoint("blk_sp_confirm", "account")

      assert Path.validate(document) == [
               {:duplicate_element_key, "email", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_element_key, "first_name", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_outcome, "account_submitted", ["blk_sp_account", "blk_sp_confirm"]}
             ]
    end
  end

  defp path_events do
    for {_id, key} <- Path.screen_refs(document()),
        outcome <- Screens.outcomes(Screens.screen(key)),
        do: Screen.outcome_event(outcome)
  end

  # The shipped Path with one screen block pointed at another screen, built
  # through `StatifierBlocks.Edit` so the result is a document the editor
  # could itself have produced.
  defp repoint(block_id, screen_key) do
    document = document()
    %Block{config: config} = Enum.find(Document.blocks(document), &(&1.id == block_id))

    {:ok, edited, _inverse} =
      Edit.apply(document, {:update_config, block_id, Map.put(config, "screen", screen_key)})

    edited
  end
end
