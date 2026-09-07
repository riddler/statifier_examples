# Defined BEFORE the test module on purpose. `mix test` starts async test
# modules as their `defmodule` finishes, while the parallel require is
# still reading the rest of the file, so a support module written after
# the test module can still be undefined when the first test calls it
# (`se-bur`: the flags cases went red on `current_version/0` roughly one
# run in five, whenever the seed put one of them first).
defmodule StatifierExamples.ViewModelPinTest.FlaggedType do
  @moduledoc """
  A block type that exists only so `StatifierExamples.ViewModelPinTest` has
  one field of each rendering flag to look at.

  It is here rather than in `lib/` because it is not a type this app ships:
  registering it in `StatifierExamples.Charts.palette/0` would put it in the
  editor's palette for every author, and editing a shipped fixture to carry
  a flag would change what the app ships in order to test what the package
  declares.
  """

  use StatifierBlocks.BlockType

  alias StatifierBlocks.Block

  # Never compiled: this type exists to be READ by `ViewModel.build/3`, and
  # nothing in this file asks the compiler for it. The callback is required
  # by the behaviour, so it is here, and it refuses rather than pretending
  # to emit - a test-only type reaching a compile is a bug in the test, not
  # a document to be compiled.
  @impl StatifierBlocks.BlockType
  def emit(%Block{}, _context) do
    {:error, [{"type", "myapp.flagged is a test-only type and emits nothing"}]}
  end

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    [
      %{key: "plain", type: :string, label: "Plain", required?: false, default: "a"},
      %{
        key: "secret",
        type: :string,
        label: "Secret",
        required?: false,
        default: "kept",
        hidden?: true
      },
      %{
        key: "shown",
        type: :string,
        label: "Shown",
        required?: false,
        default: "b",
        readonly?: true
      }
    ]
  end
end

defmodule StatifierExamples.ViewModelPinTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts

  # The pin. `StatifierExamplesWeb.PlanLiveTest` builds its expectation from
  # the same `ViewModel.outline/1` call the page renders from, which is the
  # right question to ask of a page and the wrong one to ask of a contract:
  # a walk that changed its mind about what a document says would change the
  # expectation with it and stay green. So the numbers and the strings below
  # are LITERALS, read off the pinned `statifier_blocks` once and written
  # down. When `Node.sentence`, the outline's kind partition or a fixture's
  # shape moves, this file goes red HERE - in the reference embedder, before
  # the change reaches a host that has none of these tests.
  #
  # It calls `ViewModel.build/3` directly, with no LiveView and no
  # connection: what is pinned is the package's answer, not a page's
  # rendering of it.
  #
  # ## What to do when a case here goes red
  #
  # Read the diff first. A sentence that changed wording, a row that
  # appeared, a kind that moved: each is a real change to what a document
  # says it is, and the fix is to decide whether it was intended and then to
  # update the literal - never to re-derive it from the walk.

  # Every fixture this app ships, with the exact number of rows
  # `ViewModel.outline/1` returns for it and the exact breakdown by kind.
  # Enumerated as the product of the fixture list rather than one
  # representative: a document whose shape no other fixture has is exactly
  # the one a single-fixture test misses.
  #
  # The kind counts are here and not only the total because a partition that
  # silently lost a member - rails read as steps, trays dropped - keeps the
  # total intact. The bead's sabotage criterion is that case.
  @outlines %{
    "card_processing" => {47, %{step: 24, arm: 15, rail: 8}},
    "card_processing_composite" => {2, %{step: 2}},
    "card_processing_sketch" => {8, %{step: 7, tray: 1}},
    "signup_wizard" => {20, %{step: 12, arm: 4, rail: 4}},
    "signup_invitations" => {11, %{step: 9, rail: 2}},
    "signup_onboarding" => {5, %{step: 2, arm: 2, rail: 1}},
    "signup_bulk_invites" => {5, %{step: 4, rail: 1}},
    "signup_bulk_invites_strict" => {5, %{step: 4, rail: 1}},
    "signup_invite_chunk" => {2, %{step: 2}},
    "signup_guarded_step" => {2, %{step: 2}}
  }

  # The two fixtures whose prose is pinned as well as counted, as
  # `{block_id, depth, sentence}` for every `:step` row in walk order. The
  # id is carried beside the sentence so a failure names the block rather
  # than an index, and `depth` is here because nesting depth is the other
  # half of what a list view draws.
  #
  # These two because between them they exercise every core type that
  # declares a `sentence/1` callback - branch, parallel, wait, send, assign,
  # subchart - plus this app's own types, which declare none and fall back
  # to the author's title and then to the palette label.
  @card_processing_steps [
    {"blk_cp_root", 0, "Sequence"},
    {"blk_cp_intake", 1, "Intake"},
    {"blk_cp_validation", 1, "Decide: When \"valid\", otherwise"},
    {"blk_cp_authz_deadline", 3, "Send card.authz_timed_out"},
    {"blk_cp_lanes", 3, "Run 3 lanes at the same time"},
    {"blk_cp_risk_rating", 5, "Risk rating"},
    {"blk_cp_fraud_wait", 5, "Wait 2m"},
    {"blk_cp_risk_branch", 5, "Decide: When \"high_risk\", otherwise"},
    {"blk_cp_three_ds_wait", 5, "Wait 10m"},
    {"blk_cp_authorize", 3, "Invoke"},
    {"blk_cp_authz_park", 5, "Park"},
    {"blk_cp_authz_error_notify", 5, "Notify"},
    {"blk_cp_outcome", 1, "Decide: When \"approved\", otherwise"},
    {"blk_cp_capture", 3, "Invoke"},
    {"blk_cp_capture_retry", 3, "Decide: When \"retry\", otherwise"},
    {"blk_cp_retry_wait", 5, "Wait 1m"},
    {"blk_cp_capture_retry_call", 5, "Capture funds"},
    {"blk_cp_park", 3, "Park"},
    {"blk_cp_manual_wait", 3, "Wait 2d"},
    {"blk_cp_resolve", 3, "Resolve review"},
    {"blk_cp_review_cleared", 3, "Set review.parked"},
    {"blk_cp_tail", 1, "Sequence"},
    {"blk_cp_receipt", 2, "Receipt"},
    {"blk_cp_final_notify", 2, "Notify"}
  ]

  @signup_wizard_steps [
    {"blk_su_root", 0, "Sequence"},
    {"blk_su_account", 1, "Signup step"},
    {"blk_su_verify", 1, "Group"},
    {"blk_su_send_verification", 2, "Signup step"},
    {"blk_su_reminder_window", 2, "Group"},
    {"blk_su_reminder_timer", 3, "Send signup.reminder_due"},
    {"blk_su_verify_wait", 3, "Wait 24h"},
    {"blk_su_reminder_notice", 2, "Notify"},
    {"blk_su_onboarding", 1, "Group"},
    {"blk_su_onboarding_deadline", 2, "Send signup.abandoned"},
    {"blk_su_plan", 2, "Decide: When \"business\", otherwise"},
    {"blk_su_provision", 2, "Provision"}
  ]

  # The four kinds `ViewModel.outline/1` may hand back. Pinned as a set of
  # its own so a kind ADDED upstream is a decision this app is told about,
  # rather than one it silently draws nothing for.
  @kinds [:arm, :rail, :step, :tray]

  describe "the outline of every fixture" do
    # The bead's first criterion. The count is a literal, so a fixture
    # gaining or losing a block is a change someone approved here.
    #
    # Sabotage: dropped the `rails` term from `outline_walk/3` in the pinned
    # `deps/statifier_blocks/lib/statifier_blocks/view_model.ex` (restored
    # from a copy taken first, `mix deps.compile statifier_blocks --force`
    # around both); three cases went red - this one on "card_processing:
    # outline/1 returned 37 rows, pinned at 47", the kind-set case on
    # `[:arm, :step, :tray]`, and card_processing's sentence list on the
    # steps that live inside a rail.
    test "each fixture walks to exactly the rows written down here" do
      for fixture <- Charts.fixtures() do
        {rows, kinds} = Map.fetch!(@outlines, fixture.key)
        outline = outline_of(fixture)

        assert length(outline) == rows,
               "#{fixture.key}: outline/1 returned #{length(outline)} rows, pinned at #{rows}"

        assert Enum.frequencies_by(outline, fn {_node, _depth, kind} -> kind end) == kinds,
               "#{fixture.key}: the kind breakdown moved"
      end
    end

    # The fixture list itself is pinned: a further fixture added without a row
    # count here would otherwise be walked by nothing.
    #
    # Sabotage: dropped the `signup_guarded_step` entry from `@outlines`, the
    # shape a tenth fixture arriving unannounced would have; this went red
    # here and took the row-count case above with it, which is the pairing
    # that makes an unwalked fixture impossible rather than merely unlikely.
    # Reverted from a copy.
    test "the ten fixtures are the ten fixtures" do
      assert Charts.fixtures() |> Enum.map(& &1.key) |> Enum.sort() ==
               @outlines |> Map.keys() |> Enum.sort()
    end

    # `kind` is a partition, and this is what says the members are the four
    # the amendment names.
    #
    # Sabotage: made `outline_walk/3`'s tray term pass `kind` through
    # instead of `:tray`, so a tray took its parent's kind (restored from a
    # copy); two cases went red - this one on `[:arm, :rail, :step]` against
    # the four, and the count case on "card_processing_sketch: the kind
    # breakdown moved". The totals were untouched, which is the whole
    # reason the kind map is pinned beside the count.
    test "no fixture produces a kind outside the four" do
      seen =
        Charts.fixtures()
        |> Enum.flat_map(&outline_of/1)
        |> Enum.map(fn {_node, _depth, kind} -> kind end)
        |> Enum.uniq()
        |> Enum.sort()

      assert seen == @kinds
    end

    # The first entry is always the root at depth 0 and kind `:step`, which
    # is the one row every list view can rely on being there.
    test "every fixture opens on its root" do
      for fixture <- Charts.fixtures() do
        [{node, depth, kind} | _rest] = outline_of(fixture)

        assert node.block_id == fixture.document.root.id
        assert depth == 0
        assert kind == :step
      end
    end
  end

  describe "the sentences two fixtures are pinned to" do
    # The bead's second criterion: the exact prose, in walk order, for every
    # `:step` row of the two fixtures that between them cover the callback.
    # The other six assert counts only - the sentences they would pin are
    # these sentences again, and a pin nobody reads is a pin nobody updates.
    #
    # Sabotage: changed `core.wait`'s `sentence/1` in the pinned dependency
    # from "Wait ..." to "Pause ..." (restored from a copy); exactly these
    # two cases went red, each diff naming its wait blocks, and the seven
    # counting cases stayed green - which is why the sentences are pinned
    # at all.
    test "card_processing reads as these lines" do
      assert steps_of("card_processing") == @card_processing_steps
    end

    test "signup_wizard reads as these lines" do
      assert steps_of("signup_wizard") == @signup_wizard_steps
    end

    # `sentence` is never blank on any row of any fixture, which is the
    # claim a list view rests on: it draws a line per block and never a
    # blank one. Asked of every row rather than of the pinned `:step` rows,
    # so the arms, rails and trays are covered too.
    test "no row anywhere has an empty sentence" do
      for fixture <- Charts.fixtures(), {node, _depth, _kind} <- outline_of(fixture) do
        assert is_binary(node.sentence) and node.sentence != "",
               "#{fixture.key}/#{node.block_id} has no sentence"
      end
    end
  end

  describe "a field's rendering flags" do
    # The bead's third criterion. No shipped fixture declares a `hidden?` or
    # `readonly?` field - no `core.*` type does, and neither does any of this
    # app's own - so the case registers a block type of its own rather than
    # editing a fixture: a fixture edited to carry a flag would be a change
    # to what this app SHIPS in order to test what the package DECLARES.
    #
    # Sabotage: made `Field`'s struct build in the pinned `view_model.ex`
    # write `hidden?: false` rather than reading the declaration (restored
    # from a copy); this went red alone, on the `secret` field coming back
    # with `hidden?: false`.
    test "hidden? and readonly? reach ViewModel.Field" do
      fields = flagged_fields()

      assert Enum.map(fields, & &1.key) == ["plain", "secret", "shown"]

      assert %{hidden?: false, readonly?: false} = field(fields, "plain")
      assert %{hidden?: true, readonly?: false} = field(fields, "secret")
      assert %{hidden?: false, readonly?: true} = field(fields, "shown")
    end

    # A hidden field is a rendering claim and nothing else: it is still a
    # declared field, it still carries its value, and the compiler still
    # sees it. This is what stops "hidden" being read as "dropped".
    test "a hidden field still carries its value" do
      assert %{value: "kept", label: "Secret"} = flagged_fields() |> field("secret")
    end
  end

  # ----------------------------------------------------------------- helpers

  defp outline_of(fixture) do
    fixture.document
    |> ViewModel.build(Charts.palette(), [])
    |> ViewModel.outline()
  end

  defp steps_of(key) do
    {:ok, fixture} = Charts.fixture(key)

    fixture
    |> outline_of()
    |> Enum.filter(fn {_node, _depth, kind} -> kind == :step end)
    |> Enum.map(fn {node, depth, _kind} -> {node.block_id, depth, node.sentence} end)
  end

  defp field(fields, key), do: Enum.find(fields, &(&1.key == key))

  # One block of the test-only type, built and walked. The palette is this
  # app's own with the type registered on top, which is the same
  # `Palette.from_modules/2` seam a host uses.
  defp flagged_fields do
    palette =
      Palette.from_modules(
        [{"myapp.flagged", StatifierExamples.ViewModelPinTest.FlaggedType}],
        core: true
      )

    document =
      "myapp.flagged"
      |> Block.new(id: "blk_flagged")
      |> Document.new()

    document
    |> ViewModel.build(palette, [])
    |> Map.fetch!(:root)
    |> Map.fetch!(:form)
    |> Map.fetch!(:fields)
  end
end
