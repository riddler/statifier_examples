defmodule StatifierExamples.CompositesTest do
  @moduledoc """
  The three reference composites this app registers, and the obligation that
  makes a composite safe to put in front of an author.

  A composite is a block type derived from **params** plus a **pure subtree**
  (sb ADR-0002 decision 5's amendment of 2026-09-07). Consent clause 6 of
  campaign SF037 states the obligation as prose: the compiled chart of a
  document holding a composite is byte-identical to the chart of the same
  document after that composite has been expanded in place. The package
  proves it for its own worked examples; this file proves it for the three
  composites a host declared, over the palette that host actually hands the
  editor, once per composite.

  The third, `StatifierExamples.Signup.GuardedSection`, declares a
  **pass-through slot**, and the last three `describe` blocks are what that
  buys: the author's children are spliced into the mapped inner slot with
  their ids unchanged, the walk descends at that inner position, a finding on
  a child the author placed is the child's own, and the same declaration held
  as data expands block for block to the module twin's.

  The expanded document is built from `StatifierBlocks.Composite.expand/2` -
  the one expansion function - rather than transcribed, which is what makes
  the assertion about the code and not about a hand-written second copy.

  A pure test: nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{
    Assignability,
    Block,
    BlockType,
    Compiler,
    Composite,
    Document,
    Environment,
    Palette
  }

  alias StatifierBlocks.Compiler.Finding
  alias StatifierBlocks.Composite.Data
  alias StatifierExamples.CardAuth.AuthorizeWithDeadline
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.{GuardedSection, GuardedStep}

  # `{fixture key, the composite block in it, its module, its sentence}`.
  #
  # The sentence is pinned as a literal rather than rendered a second time
  # here: what an author reads on the card is the thing worth being told
  # about when it changes, and a test that re-rendered the template would
  # agree with any template at all.
  @composites [
    {"card_processing_composite", "blk_cpx_authz", AuthorizeWithDeadline,
     "Authorize within 1h, else abandon"},
    {"signup_guarded_step", "blk_gs_step", GuardedStep, "Run myapp:provision, notify on failure"},
    {"signup_guarded_section", "blk_gx_section", GuardedSection,
     "Run myapp:provision, notify on failure, then continue"}
  ]

  # The pass-through composite's own fixture, and the one child the author
  # put in its `body` slot. Named once here because six cases below read it.
  @section_key "signup_guarded_section"
  @section_id "blk_gx_section"
  @section_child "blk_gx_confirm"

  describe "the three composites are registered" do
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

    # `RQ-SF037-3` answered a campaign ago that a composite exposes no slot of
    # its own; `RQ-SF038-5` gives it one, for the composite that declares it
    # and for no other. Both halves are asserted, per module, because what is
    # worth being told about is a slot appearing on a composite that declared
    # none.
    #
    # `slots/1` is derived by `use StatifierBlocks.Composite` from the
    # declaration's `:slots` and is one of the callbacks the macro
    # deliberately does not make overridable, so no declaration in this repo
    # can answer anything else - which is why the arity and the label below
    # are read as facts about the declaration rather than about a function
    # this app wrote.
    #
    # Sabotage: dropped `:slots` from `GuardedSection`'s `use`. Thirteen cases
    # went red across this file, `StatifierExamples.ViewModelPinTest` and
    # `StatifierExamplesWeb.PlanLiveTest` - the splice, `pass_through/2`,
    # `slot_accepts`, both walk cases, both data-twin cases and the outline and
    # plan rows - because a composite that declares no slot carries the
    # author's children nowhere. Reverted from a copy.
    test "only the third exposes a slot of its own" do
      assert AuthorizeWithDeadline.slots(%{}) == []
      assert GuardedStep.slots(%{}) == []

      # P1's `:label` is declared and its `:arity` is left to default.
      assert GuardedSection.slots(%{}) == [{"body", :any, "Then"}]
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

      assert Enum.map(GuardedSection.config_schema(%{}), & &1.key) == [
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

      # The pass-through composite says the same thing twice over: the minted
      # members are in the chart, the composite is not, and the child the
      # AUTHOR placed is there at the id the author gave it. `ADR-0004`'s T2 -
      # a spliced child is not minted, so its state id is the one it would
      # have had had the author placed the expansion by hand.
      assert {:ok, compiled} = compile(fixture_document(@section_key))

      assert compiled.scxml =~ "s_#{@section_id}_call"
      assert compiled.scxml =~ "s_#{@section_id}_notify"
      assert compiled.scxml =~ "s_#{@section_id}_then"
      assert compiled.scxml =~ "s_#{@section_child}"
      refute compiled.scxml =~ "s_#{@section_id}\""
      refute compiled.scxml =~ "s_#{@section_id}_confirm"

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

  describe "P4: the pass-through slot carries the author's children" do
    # ADR-0002's P4, over this app's own fixture. The children the author put
    # under the composite's declared slot are placed in the mapped inner slot
    # of the member the local id names, in their stored order, and they are
    # NOT minted - minting is what turns a subtree's local ids into document
    # ids, and a child arrived carrying a document id already.
    #
    # Sabotage: renamed the fixture block's slot key from `body` to `then`,
    # which is the LOCAL id rather than the declared slot name; the splice
    # found nothing to carry and this went red on the child's absence, taking
    # six more with it - the chart's own state ids, both outline pins and both
    # plan-page rows. Reverted from a copy.
    test "the child lands in the mapped inner slot, id unchanged" do
      {members, _param_map} = Composite.expand(section_block(), GuardedSection)

      assert [
               %Block{type: "core.invoke", id: "blk_gx_section_call"},
               %Block{type: "core.group", id: "blk_gx_section_then"} = group
             ] = members

      assert [%Block{id: @section_child, type: "myapp.notify"}] = group.slots["body"]

      # Only the mapped inner slot is written. `interrupts` is the group's
      # other slot and the subtree wrote it empty; the splice leaves it that
      # way rather than reaching a slot nothing mapped to.
      assert group.slots["interrupts"] == []
    end

    # `pass_through/2` is the mapping resolved to the MINTED id, which is what
    # the environment walk needs to find the inner position and what a caller
    # must not derive for itself - `mint_id/3` is the package's rule and a
    # second implementation of it would be a second chance to disagree.
    #
    # Sabotage: pointed the declaration's `:to` at `{"call", "on_error"}`,
    # which the subtree fills with the notification. `expand/2` raised P5's
    # third refusal by name - "the mapped inner slot holds the author's
    # children and only them" - and sixteen cases went red with it, which is
    # every case that expands this composite. Reverted from a copy.
    test "pass_through/2 answers the mapping under the minted id" do
      assert Composite.pass_through(section_block(), GuardedSection) == %{
               "body" => {"blk_gx_section_then", "body"}
             }

      # A composite that declares nothing answers nothing, which is every
      # composite this app shipped before this one.
      assert Composite.pass_through(block("signup_guarded_step", "blk_gs_step"), GuardedStep) ==
               %{}
    end

    # `ADR-0004`'s T3: the expansion index maps expansion MEMBERS only, so the
    # param map is taken before the author's children are spliced in and a
    # pass-through child has no entry in it. That is what keeps a finding on a
    # child from ever being re-anchored onto the composite.
    #
    # Sabotage: in `deps/statifier_blocks`, had `expand/2` take the param map
    # over the SPLICED tree rather than over the minted members
    # (`MIX_ENV=test mix deps.compile statifier_blocks --force` before and
    # after); the child appeared in it against `nil`, and this went red on the
    # key list with the child-attribution case below - which is the pairing
    # that says the index and the attribution are one fact. Reverted from a
    # copy and recompiled.
    test "the param map names the minted members and no spliced child" do
      {_members, param_map} = Composite.expand(section_block(), GuardedSection)

      assert param_map == %{
               "blk_gx_section_call" => "invoke_type",
               "blk_gx_section_notify" => "failure_template",
               "blk_gx_section_then" => nil
             }

      refute Map.has_key?(param_map, @section_child)
    end

    # `io/1`'s `slot_accepts` is `%{}` for a composite that declares no slot
    # and, for one that does, the MAPPED INNER slot's own answer - read off
    # `core.group`, which is a core type and therefore exact behind the
    # callback.
    #
    # Sabotage: mapped the declaration at `{"then", "interrupts"}`;
    # `slot_accepts` answered the interrupt rail's `[:interrupt_handler]` and
    # this went red, taking eight more with it - the splice, `pass_through/2`,
    # both byte-identity cases, both walk cases and both data-twin cases, since
    # a `myapp.notify` spliced onto an interrupt rail is not a legal document.
    # Reverted from a copy.
    test "slot_accepts answers the mapped inner slot's kinds" do
      %{slot_accepts: accepts} = GuardedSection.io(%{})

      # `core.group`'s own answer for the slot the declaration maps into
      # (`lib/statifier_blocks/core/group.ex:56-60`), pinned as the literal:
      # what a reader wants to be told about is the kinds an author may drop
      # into the composite's interior, and a test that re-derived them would
      # agree with any answer at all.
      assert accepts == %{"body" => [:step]}

      assert %{slot_accepts: %{}} = GuardedStep.io(%{})
    end
  end

  describe "ADR-0011 section 2 and 3: the walk descends at the mapped inner position" do
    # Section 2, and the reason the composite records at a path of its own.
    # The environment a child of the declared slot is read against is NOT the
    # environment reaching the composite: it is the one obtained by walking
    # the expansion up to the mapped member, so the call's `assign_to` has
    # already been applied by the time the child is read.
    #
    # The two halves are asserted together because either alone proves
    # nothing: an entry present at both positions would say the walk never
    # descended, and one present at neither would say the call writes nothing.
    #
    # Sabotage: pointed the MODULE subtree's `assign_to` at `""`, so the call
    # records nowhere; the first assertion went red and the second stayed
    # green, which is the pair doing its job. It took both data-twin cases with
    # it, because `declaration/0` still wrote the path and the two spellings
    # stopped agreeing - which is the other thing this composite is here to
    # keep true. Reverted from a copy.
    test "the child is read against the environment inside the mapped member" do
      document = fixture_document(@section_key)
      palette = Charts.palette()

      inside = Environment.at(palette, document, {@section_id, "body", 0})
      before = Environment.at(palette, document, {"blk_gx_root", "body", 0})

      assert Map.has_key?(inside, "signup.step_outcome")
      refute Map.has_key?(before, "signup.step_outcome")
    end

    # The other half of section 2's worked example, in the terms this app can
    # state it: the fixture's own child reads clean, which it could not do
    # against an environment the walk refused to descend into.
    test "a child's read of the step's produced path is satisfied" do
      assert Assignability.validate(Charts.palette(), fixture_document(@section_key), %{}) == :ok
    end

    # Section 3, and `ADR-0004`'s T3 with it: a finding whose owner is a block
    # the AUTHOR placed is reported against that block, at that block's own
    # id. It is not lifted one level onto the composite the way a finding on a
    # member of the expansion is, because the author can see it and can change
    # it.
    #
    # The pair is asserted in one case so that the two arms are read together:
    # the same document, the same compile, one finding on the child and one on
    # the composite, and each names the block whose author owns it.
    #
    # Sabotage: in `deps/statifier_blocks`, had `expand/2` take the param map -
    # which is what the compiler builds its expansion index from - over the
    # SPLICED tree, so the child the author placed was indexed as an expansion
    # member (`MIX_ENV=test mix deps.compile statifier_blocks --force` before
    # and after); the child's finding was re-anchored onto `blk_gx_section` and
    # this went red on the first assertion, with the param-map case above.
    # Reverted from a copy and recompiled.
    test "a wrong read on a child is the child's finding, and one on a member is the composite's" do
      child =
        Block.new("core.invoke",
          id: "blk_gx_stray",
          config: %{"invoke_type" => "myapp:nobody", "assign_to" => "", "params" => ""}
        )

      assert {:ok, compiled} = compile(document([section_block([child])]))

      assert [%Finding{} = warning] = compiled.warnings
      assert warning.block_id == "blk_gx_stray"

      # And the other arm, unmoved: a minted member the author never typed is
      # still re-anchored onto the composite, on the param whose value it
      # carries.
      stray = %{section_block() | config: %{section_block().config | "invoke_type" => "nope"}}

      assert {:error, [%Finding{} = finding]} = compile(document([stray]))
      assert finding.block_id == @section_id
      assert finding.config_key == "invoke_type"
    end
  end

  describe "P9: the same declaration, held as data" do
    # The twin proper, and the one thing that makes it byte-identical rather
    # than merely equivalent: each node's `"id_suffix"` is the local id
    # `subtree/1` writes, so the two kinds mint the same ids.
    #
    # Sabotage: changed the row's `"then"` `"id_suffix"` to `"group"`; the two
    # expansions stopped being equal and this went red, as did both
    # byte-identity cases below and nothing else. Reverted from a copy.
    test "the data twin expands block for block to the module twin's" do
      state = section_state()

      assert Composite.expand(section_block(), GuardedSection) ==
               Composite.expand(section_block(), {Data, state})

      # And the declaration-level `"slots"` key decodes to the same list the
      # `use` writes, which is P2's whole claim.
      assert Data.slots(state, %{}) == GuardedSection.slots(%{})
    end

    # Consent clause 6 for the data kind: the same document, compiled over a
    # palette carrying the declaration instead of the module, is the same
    # bytes.
    #
    # What CANNOT redden this is a change that keeps both compiles legal -
    # both sides read one `Composite.expand/2` - which is the shape of the
    # obligation rather than a weakness, exactly as the module cases above
    # record.
    test "a document holding the data twin compiles to the module twin's bytes" do
      document = fixture_document(@section_key)
      palette = Charts.palette([{"myapp.guarded_section", {Data, section_state()}}])

      assert {:ok, from_module} = compile(document)
      assert {:ok, from_data} = Compiler.compile(document, palette, known_invoke_types: known())

      assert from_module.scxml == from_data.scxml
      assert from_module.provenance == from_data.provenance
      assert from_module.invoke_types == from_data.invoke_types
    end

    # T4 for the data kind against its own hand-expansion, which is the same
    # obligation the module cases state and the reason both are here: a
    # declaration that expanded to something the compiler read differently
    # would pass the case above and fail this one.
    # The envelope is the fixture's own on both sides - a `Document` mints a
    # fresh id, and two documents built by hand would differ in the `name`
    # attribute for a reason that has nothing to do with the expansion.
    test "the data twin's document compiles to its own expansion's bytes" do
      state = section_state()
      palette = Charts.palette([{"myapp.guarded_section", {Data, state}}])
      document = fixture_document(@section_key)
      {members, _param_map} = Composite.expand(section_block(), {Data, state})

      assert {:ok, composed} =
               Compiler.compile(document, palette, known_invoke_types: known())

      assert {:ok, expanded} =
               Compiler.compile(expanded_document(document, members), palette,
                 known_invoke_types: known()
               )

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
      assert composed.invoke_types == expanded.invoke_types
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
  # about the expansion and about nothing else. All three fixtures are a
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
    Compiler.compile(document, Charts.palette(), known_invoke_types: known())
  end

  @spec known() :: MapSet.t()
  defp known, do: MapSet.new(Charts.invoke_types())

  # The pass-through composite as its fixture stores it, optionally with the
  # `body` slot's children replaced - which is how the cases that need a
  # different child ask for one without a second fixture.
  @spec section_block() :: Block.t()
  defp section_block, do: block(@section_key, @section_id)

  @spec section_block([Block.t()]) :: Block.t()
  defp section_block(children) when is_list(children) do
    block = section_block()

    %{block | slots: Map.put(block.slots, "body", children)}
  end

  # The same composite's declaration, decoded. `declaration/1` is where a data
  # composite's pass-through mapping is refused, so a row that got this far is
  # one whose mapping fits its own subtree.
  @spec section_state() :: map()
  defp section_state do
    assert {:ok, state} = Data.declaration(GuardedSection.declaration())

    state
  end
end
