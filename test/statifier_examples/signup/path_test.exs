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
  question about `responses.*` that the bead left open: the paths are there,
  and every one of them is `:unknown`.

  A pure test: nothing here names LiveView.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Document, Edit, Environment}
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.{Path, Screen, Screens}

  # `path.ex`'s examples were prose until now: no test module ran them, so
  # the `validate(document()) == []` example could have gone stale without
  # anything going red. The back-edge rule is stated in an example, and an
  # example stating a rule has to be a test.
  doctest Path

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

    # Three screens in four screen blocks: the fourth is the plan screen's
    # back edge, which shows the account screen again from inside the plan
    # block's `on_went_back` slot.
    #
    # Sabotage (2026-09-18): emptied `blk_sp_plan`'s `on_went_back` slot in
    # `priv/fixtures/signup_path.json` from a copy. This case went red on
    # the block count, and so did the screen-ref walk below, the view-model
    # outline pin and the Journey's Back case. Reverted from the copy.
    test "it holds three screens, a branch and a timer" do
      blocks = Document.blocks(document())
      types = for %Block{type: type} <- blocks, do: type

      assert Enum.count(types, &(&1 == "myapp.screen")) == 4

      assert blocks
             |> Enum.filter(&(&1.type == "myapp.screen"))
             |> Enum.map(& &1.config["screen"])
             |> Enum.uniq() == ["account", "plan", "confirm"]

      assert Enum.count(types, &(&1 == "core.branch")) == 1
      assert Enum.count(types, &(&1 == "core.send")) == 1
    end

    test "the branch reads the path the plan screen's buttons write" do
      %Block{config: config} =
        Enum.find(Document.blocks(document()), &(&1.id == "blk_sp_plan_branch"))

      assert Enum.map(config["arms"], & &1["cond"]) == [
               "responses.plan == 'business'",
               "responses.plan == 'personal'"
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

  describe "the environment walk over responses.*" do
    # THE OPEN QUESTION THE BEAD LEFT: does the ADR-0011 walk see `responses.*`
    # typed? It sees the paths - all four, and only after the screens that
    # write them - and it types every one of them `:unknown`.
    #
    # Not an accident of this document: `StatifierBlocks.Environment` says a
    # `capture` map "writes `:unknown` at each of its keys, one per pair",
    # and its `capture_writes/1` builds that `:unknown` unconditionally, so
    # no declaration on this side can improve it. The ask is recorded in
    # `docs/spikes/SF040-signup-skeleton.md`; this case is what would go red
    # if the package ever answered otherwise.
    test "every responses path is present, and every one is :unknown" do
      env = Environment.at(palette(), document(), {"blk_sp_root", "body", 4})

      assert Enum.sort(Map.keys(env)) == [
               "responses.email",
               "responses.first_name",
               "responses.plan",
               "responses.seats"
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
               {"blk_sp_back_to_account", "account"},
               {"blk_sp_confirm", "confirm"}
             ]
    end

    test "a screen the element document does not declare is a finding" do
      document = repoint("blk_sp_confirm", "not_a_screen")

      assert {:unknown_screen, "blk_sp_confirm", "not_a_screen"} in Path.validate(document)
    end

    # The back-edge drop spends only KNOWN screens. The shipped back edge
    # and the block it goes back to are both pointed at a screen the
    # element document does not declare, so the back edge repeats a key an
    # earlier block named: were the drop to run before the known/unknown
    # split, it would spend the back edge and only the first block would
    # be reported. Both blocks point at nothing, and both are named.
    #
    # Sabotage (2026-09-18): moved `drop_revisits/2` back ahead of the
    # split in `validate/1`, where it stood before this case. THIS CASE WENT
    # RED alone in `test/statifier_examples/signup/`, answering only the
    # `blk_sp_account` finding. Reverted from a copy.
    test "a back edge to an unknown screen is an unknown screen too" do
      document =
        "blk_sp_account"
        |> repoint("not_a_screen")
        |> repoint("blk_sp_back_to_account", "not_a_screen")

      assert Path.validate(document) == [
               {:unknown_screen, "blk_sp_account", "not_a_screen"},
               {:unknown_screen, "blk_sp_back_to_account", "not_a_screen"}
             ]
    end

    # ARM ONE of the back-edge rule. A Back button sends the reader to a
    # screen they have already seen, on purpose, and the block it sends them
    # to is a new block with a new id - it has to be, ids being
    # document-unique - so nothing in a flat list of `{block id, screen key}`
    # pairs can tell it from two questions racing for one response key. The
    # slot can: it sits inside the plan screen's declared `on_went_back`.
    #
    # Sabotage: made `back_edge?/2` answer `false` for every block, which is
    # the validator as it stood before the rule. THIS CASE WENT RED with the
    # three findings a Path answers when its account screen is shown twice,
    # and so did the back-edge doctest and "a forward-line duplicate still
    # answers ...". Reverted from a copy.
    test "a re-visit reached through a declared back edge is not a duplicate" do
      assert Path.validate(back_edge("blk_sp_plan", "on_went_back", "account")) == []
    end

    test "the re-visiting block is still one of the Path's screen blocks" do
      refs = Path.screen_refs(back_edge("blk_sp_plan", "on_went_back", "account"))

      assert {"blk_revisit_account", "account"} in refs
    end

    # ARM TWO. The drop is aimed at the repeat, not at the slot: a block in
    # an `on_` slot is dropped only when an EARLIER block named its screen
    # key, so a Path that has a back edge still answers for the duplicate
    # its forward line carries. Here the account screen is named three
    # times - once forward, once through the back edge, once by a confirm
    # block pointed at it - and exactly the back edge is spent.
    #
    # Sabotage: dropped every ref whose key had been seen, back edge or not
    # (`drop_revisits/2` without its `back_edge?/2` conjunct). THIS CASE WENT
    # RED, and with it "a screen shown twice duplicates its response keys and
    # its outcomes" - the whole of the old rule - and the on_-slot-first case
    # below. Reverted from a copy.
    test "a forward-line duplicate still answers on a Path that also has a back edge" do
      document =
        "blk_sp_plan"
        |> back_edge("on_went_back", "account")
        |> repoint("blk_sp_confirm", "account")

      assert Path.validate(document) == [
               {:duplicate_response_key, "email", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_response_key, "first_name", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_outcome, "account_submitted", ["blk_sp_account", "blk_sp_confirm"]}
             ]
    end

    # ARM THREE, the other direction. Going back to a screen nobody has been
    # shown yet is not going back, so a block in an `on_` slot naming a
    # screen the forward line reaches LATER is kept and the pair is
    # reported - against the two blocks, in the order the Path visits them.
    #
    # Sabotage: made `drop_revisits/2` drop an `on_` slot ref whose key
    # appeared anywhere else in the document rather than earlier in it -
    # the one rewrite the other two cases cannot see. THIS CASE WENT RED
    # alone, answering `[]`. Reverted from a copy.
    test "an on_ slot showing a screen the forward line reaches later is a defect" do
      document = back_edge("blk_sp_plan", "on_went_back", "confirm")

      assert Path.validate(document) == [
               {:duplicate_response_key, "referral", ["blk_revisit_confirm", "blk_sp_confirm"]},
               {:duplicate_outcome, "signup_confirmed", ["blk_revisit_confirm", "blk_sp_confirm"]}
             ]
    end

    # R10d, and the reason the finding names blocks rather than screens: one
    # screen shown twice reaches its response keys twice, and the second visit
    # overwrites what the first one collected. Note what is NOT reported:
    # the account screen's `account_heading`, `account_intro`,
    # `account_greeting` and `account_continue` keys are duplicated just as
    # really, and `response_keys/1` reads `text_question` nodes only. That gap
    # is the moduledoc's last paragraph and finding 8 of the spike document.
    test "a screen shown twice duplicates its response keys and its outcomes" do
      document = repoint("blk_sp_confirm", "account")

      assert Path.validate(document) == [
               {:duplicate_response_key, "email", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_response_key, "first_name", ["blk_sp_account", "blk_sp_confirm"]},
               {:duplicate_outcome, "account_submitted", ["blk_sp_account", "blk_sp_confirm"]}
             ]
    end
  end

  # One pass per SCREEN, not per screen block: the back edge shows the
  # account screen a second time, and a screen shown again listens for the
  # events it listened for the first time. That is a re-visit, not two
  # screens racing for one event, and `Path.validate/1` says the same.
  defp path_events do
    for {_id, key} <- Enum.uniq_by(Path.screen_refs(document()), &elem(&1, 1)),
        outcome <- Screens.outcomes(Screens.screen(key)),
        do: Screen.outcome_event(outcome)
  end

  # The shipped Path with a screen block added inside one of another screen
  # block's declared outcome slots. The shipped fixture carries one back
  # edge of its own (2026-09-18: `blk_sp_back_to_account`, in the plan
  # block's `on_went_back`); this builds another beside it, on a copy,
  # through `StatifierBlocks.Edit` like everything else here, so
  # `priv/fixtures/signup_path.json` stays exactly as it ships.
  defp back_edge(parent_id, slot, screen_key),
    do: back_edge(document(), parent_id, slot, screen_key)

  defp back_edge(document, parent_id, slot, screen_key) do
    block =
      Block.new("myapp.screen",
        id: "blk_revisit_" <> screen_key,
        config: %{"screen" => screen_key, "timeout" => "1d"}
      )

    {:ok, edited, _inverse} = Edit.apply(document, {:insert, {parent_id, slot, 0}, block})

    edited
  end

  # The shipped Path with one screen block pointed at another screen, built
  # through `StatifierBlocks.Edit` so the result is a document the editor
  # could itself have produced.
  defp repoint(block_id, screen_key), do: repoint(document(), block_id, screen_key)

  defp repoint(document, block_id, screen_key) do
    %Block{config: config} = Enum.find(Document.blocks(document), &(&1.id == block_id))

    {:ok, edited, _inverse} =
      Edit.apply(document, {:update_config, block_id, Map.put(config, "screen", screen_key)})

    edited
  end
end
