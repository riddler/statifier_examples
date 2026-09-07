defmodule StatifierExamples.CompositesTest do
  @moduledoc """
  The two reference composites this app registers, and the obligation that
  makes a composite safe to put in front of an author.

  A composite is a block type derived from **params** plus a **pure subtree**
  (sb ADR-0002 decision 5's amendment of 2026-09-07). Consent clause 6 of
  campaign SF037 states the obligation as prose: the compiled chart of a
  document holding a composite is byte-identical to the chart of the same
  document after that composite has been expanded in place. The package
  proves it for its own worked examples; this file proves it for the two
  composites a host declared, over the palette that host actually hands the
  editor, once per composite.

  The expanded document is built from `StatifierBlocks.Composite.expand/2` -
  the one expansion function - rather than transcribed, which is what makes
  the assertion about the code and not about a hand-written second copy.

  A pure test: nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, BlockType, Compiler, Composite, Document, Palette}
  alias StatifierExamples.CardAuth.AuthorizeWithDeadline
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.GuardedStep

  # `{fixture key, the composite block in it, its module, its sentence}`.
  #
  # The sentence is pinned as a literal rather than rendered a second time
  # here: what an author reads on the card is the thing worth being told
  # about when it changes, and a test that re-rendered the template would
  # agree with any template at all.
  @composites [
    {"card_processing_composite", "blk_cpx_authz", AuthorizeWithDeadline,
     "Authorize within 1h, else abandon"},
    {"signup_guarded_step", "blk_gs_step", GuardedStep, "Run myapp:provision, notify on failure"}
  ]

  describe "the two composites are registered" do
    # Sabotage: renamed the key `"myapp.guarded_step"` in
    # `Signup.block_types/0`, so the type the fixture names resolves to
    # nothing; this went red here and took three more cases with it - the
    # `new_block` case and both byte-identity cases. Reverted from a copy.
    test "each resolves through the palette this app hands the editor" do
      for {_key, _id, module, _sentence} <- @composites do
        name = module.__composite__().name

        assert {:ok, ^module} = Palette.fetch(Charts.palette(), name)
        assert Composite.composite?(module)
      end
    end

    # `RQ-SF037-3`: a composite in this campaign exposes no slot of its own,
    # so what an author edits is the params and nothing else. Pass-through
    # slots are a later campaign's question.
    #
    # Sabotage: added a second `def slots/1` to `GuardedStep`, answering
    # `core.invoke`'s `on_error` slot. It did NOT go red, and the compiler
    # said why - "this clause for slots/1 cannot match because a previous
    # clause at line 39 always matches": `slots/1` is derived by
    # `use StatifierBlocks.Composite` and is one of the callbacks the macro
    # deliberately does not make overridable, so no declaration in this repo
    # can answer anything else. Reverted from a copy. What this case is
    # therefore watching is the PACKAGE keeping `RQ-SF037-3`, and the
    # mutation that reddens it lives there; the value here is that a
    # pass-through slot arriving in a later release lands as a failure in the
    # host that assumed there was none.
    test "neither exposes a slot of its own" do
      for {_key, _id, module, _sentence} <- @composites do
        assert module.slots(%{}) == []
      end
    end

    # The params ARE the config schema, which is what lets the compiler's own
    # declaration checks run over them for free.
    #
    # Sabotage: renamed `GuardedStep`'s `failure_template` param key; this
    # went red here and on the `new_block` case, because the subtree then
    # read a key no param declared and the notify's template went empty.
    # Reverted from a copy.
    test "the config schema is the declared params, in declaration order" do
      assert Enum.map(AuthorizeWithDeadline.config_schema(%{}), & &1.key) == [
               "deadline",
               "first_lane",
               "first_call",
               "second_lane",
               "second_call",
               "third_lane",
               "third_call",
               "outcome"
             ]

      assert Enum.map(GuardedStep.config_schema(%{}), & &1.key) == [
               "invoke_type",
               "failure_template"
             ]
    end
  end

  describe "the sentence an author reads" do
    # Sabotage: swapped the `{deadline}` placeholder for `{first_lane}` in
    # `AuthorizeWithDeadline`'s sentence template; this went red, and it went
    # red alone - which is the point of pinning the string rather than
    # re-rendering it. Reverted from a copy.
    test "each fixture's composite reads the sentence pinned here" do
      for {key, id, module, sentence} <- @composites do
        assert BlockType.sentence(module, block(key, id).config) == sentence
      end
    end
  end

  describe "a composite built from its own defaults is finding-free" do
    # `StatifierBlocks.Palette.new_block/2` is what the editor's drop and this
    # app's Plan view both build an inserted block with, so a composite whose
    # defaults do not compile is one an author cannot put down without being
    # shouted at for something they did not do.
    #
    # The check is a compile rather than a `validate_config/1` call: a
    # composite's own `validate_config/1` is the injected `:ok`, and what
    # would actually be wrong with a bad default - an invoke type that does
    # not look like one, a lane name that makes no slot - is only visible
    # once the expansion has run.
    #
    # Sabotage: set `AuthorizeWithDeadline`'s `first_call` default to `""`;
    # this went red with an `invoke_type` finding on the expanded call.
    # Reverted from a copy.
    test "Palette.new_block/2 builds each with no finding at all" do
      for {_key, _id, module, _sentence} <- @composites do
        name = module.__composite__().name

        assert {:ok, block} = Palette.new_block(Charts.palette(), name)
        assert block.type == name
        assert block.type_version == module.current_version()

        assert {:ok, compiled} = compile(document([block]))
        assert compiled.warnings == []
      end
    end
  end

  describe "consent clause 6: the compiled bytes do not move when a composite is expanded" do
    # The obligation, per composite. The expanded document is the fixture with
    # the composite block replaced by exactly the blocks `Composite.expand/2`
    # answers - which is what the editor's Expand control commits - and the
    # two compiles are compared byte for byte.
    #
    # Sabotage: moved `GuardedStep`'s `myapp.notify` member out of the
    # `on_error` slot into a slot called `after`, which `core.invoke` does not
    # declare; this went red on "signup_guarded_step does not compile clean"
    # and took three more cases with it. Reverted from a copy.
    #
    # What this case CANNOT be reddened by is an edit in this repo that keeps
    # both compiles legal: both sides read the same `expand/2`, so a change to
    # a subtree moves both. That is the shape of the obligation rather than a
    # weakness in the test - what it is watching for is the package losing the
    # property, and `statifier_blocks`' own suite carries the mutation that
    # takes it away.
    test "each fixture compiles to the same bytes as its expansion" do
      for {key, id, module, _sentence} <- @composites do
        {:ok, fixture} = Charts.fixture(key)

        {members, _param_map} = Composite.expand(block(key, id), module)

        assert {:ok, composed} = compile(fixture.document)
        assert composed.warnings == [], "#{key} does not compile clean"
        assert {:ok, expanded} = compile(expanded_document(fixture.document, members))

        assert composed.scxml == expanded.scxml, "#{key}: the compiled SCXML moved"
        assert composed.provenance == expanded.provenance, "#{key}: the provenance moved"
        assert composed.invoke_types == expanded.invoke_types, "#{key}: the invoke types moved"
      end
    end

    # The other half of the same fact, stated where a reader can see it: the
    # state ids in the compiled chart are the EXPANDED blocks' ids, minted
    # from the composite block's own id. Nothing in the chart names the
    # composite, which is why expanding one in the editor cannot move it.
    #
    # Sabotage: renamed a local id in `GuardedStep.subtree/1` from `"call"` to
    # `"invoke"`; this went red here and on the arrangement case below, and
    # the byte-identity case above stayed green - which is exactly why both
    # are asserted. Reverted from a copy.
    test "the chart names the expanded blocks and never the composite" do
      assert {:ok, compiled} = compile(fixture_document("signup_guarded_step"))

      assert compiled.scxml =~ "s_blk_gs_step_call"
      assert compiled.scxml =~ "s_blk_gs_step_notify"
      refute compiled.scxml =~ "s_blk_gs_step\""

      assert {:ok, compiled} = compile(fixture_document("card_processing_composite"))

      for id <- ~w(s_blk_cpx_authz_authz s_blk_cpx_authz_deadline s_blk_cpx_authz_lanes
                   s_blk_cpx_authz_call_1 s_blk_cpx_authz_call_2 s_blk_cpx_authz_call_3
                   s_blk_cpx_authz_timeout) do
        assert compiled.scxml =~ id, "#{id} is not in the compiled chart"
      end
    end
  end

  describe "what each composite stands for" do
    # The arrangement itself, read off `expand/2` rather than off the
    # subtree, so the ids are the document's.
    #
    # Sabotage: renamed the group's `interrupts` slot to `unused` in
    # `AuthorizeWithDeadline.subtree/1`, so the deadline fires into a chart
    # with nobody listening; this went red here and took three more cases
    # with it. Reverted from a copy.
    test "the card-processing composite is the group, the deadline, three lanes and the interrupt" do
      {members, _param_map} =
        Composite.expand(
          block("card_processing_composite", "blk_cpx_authz"),
          AuthorizeWithDeadline
        )

      assert [%Block{type: "core.group", id: "blk_cpx_authz_authz"} = group] = members

      assert Enum.map(Composite.flatten(members), &{&1.type, &1.id}) == [
               {"core.group", "blk_cpx_authz_authz"},
               {"core.send", "blk_cpx_authz_deadline"},
               {"core.parallel", "blk_cpx_authz_lanes"},
               {"core.group", "blk_cpx_authz_lane_2"},
               {"core.invoke", "blk_cpx_authz_call_2"},
               {"core.group", "blk_cpx_authz_lane_1"},
               {"core.invoke", "blk_cpx_authz_call_1"},
               {"core.group", "blk_cpx_authz_lane_3"},
               {"core.invoke", "blk_cpx_authz_call_3"},
               {"core.on_event", "blk_cpx_authz_timeout"}
             ]

      assert [%Block{type: "core.on_event", config: %{"outcome" => "abandon"}}] =
               group.slots["interrupts"]
    end

    # The lane name is the root the lane records at, which is what keeps the
    # arrangement's writes derived from the params rather than hardwired.
    #
    # Sabotage: hardwired the three assign paths to one `auth.result`; this
    # went red here and alone, and the fixture's own `datamodel` key then
    # declared three roots nothing wrote. Reverted from a copy.
    test "each lane records at the root its name spells" do
      {members, _param_map} =
        Composite.expand(
          block("card_processing_composite", "blk_cpx_authz"),
          AuthorizeWithDeadline
        )

      calls =
        for %Block{type: "core.invoke", config: config} <- Composite.flatten(members),
            do: config["assign_to"]

      assert Enum.sort(calls) == [
               "balance_check.result",
               "fraud_review.result",
               "three_ds.result"
             ]
    end

    # The worked example both sb records carry, in this app's vocabulary: the
    # call, and the notification on its error path.
    #
    # Sabotage: moved the notify out of `on_error` into a slot called
    # `after`; this went red here and on three more cases, because a member
    # in a slot `core.invoke` does not declare is a structural refusal rather
    # than a second step. Reverted from a copy.
    test "the signup composite is a call with a notification on its error path" do
      {members, param_map} =
        Composite.expand(block("signup_guarded_step", "blk_gs_step"), GuardedStep)

      assert [%Block{type: "core.invoke", id: "blk_gs_step_call"} = call] = members

      assert [%Block{type: "myapp.notify", id: "blk_gs_step_notify", config: notify}] =
               call.slots["on_error"]

      assert notify["template"] == "provision_failed"

      # `RQ-SF037-5`'s other half: each expanded block is blamed on the one
      # param whose value it carries, which is the key a re-anchored finding
      # is drawn beneath.
      assert param_map == %{
               "blk_gs_step_call" => "invoke_type",
               "blk_gs_step_notify" => "failure_template"
             }
    end
  end

  # -- helpers -----------------------------------------------------------

  @spec block(String.t(), String.t()) :: Block.t()
  defp block(key, id) do
    block = key |> fixture_document() |> Document.blocks() |> Enum.find(&(&1.id == id))

    assert %Block{} = block, "#{key} holds no block #{id}"

    block
  end

  @spec fixture_document(String.t()) :: Document.t()
  defp fixture_document(key) do
    {:ok, fixture} = Charts.fixture(key)

    fixture.document
  end

  # The fixture, with the one composite in its body replaced by the blocks it
  # stands for. The envelope, the root's own id and the document's declared
  # roots are the fixture's own - which is what makes the comparison below
  # about the expansion and about nothing else. Both fixtures are a
  # `core.sequence` root whose `body` holds exactly the composite, so the
  # splice is the whole body.
  @spec expanded_document(Document.t(), [Block.t()]) :: Document.t()
  defp expanded_document(%Document{root: root} = document, members) do
    %{document | root: %{root | slots: %{"body" => members}}}
  end

  # A throwaway document around one block, for the cases that are about a
  # block rather than about a fixture.
  @spec document([Block.t()]) :: Document.t()
  defp document(blocks) do
    Document.new(Block.new("core.sequence", id: "blk_cx_root", slots: %{"body" => blocks}))
  end

  # The one compile recipe this app uses everywhere: its own palette, and the
  # invoke types it actually answers.
  @spec compile(Document.t()) :: {:ok, struct()} | {:error, [struct()]}
  defp compile(document) do
    Compiler.compile(document, Charts.palette(),
      known_invoke_types: MapSet.new(Charts.invoke_types())
    )
  end
end
