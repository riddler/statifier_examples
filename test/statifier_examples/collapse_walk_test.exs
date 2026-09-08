defmodule StatifierExamples.CollapseWalkTest do
  @moduledoc """
  The other direction: an arrangement read back as the declaration that
  stands for it.

  `StatifierExamples.CompositesTest` walks a composite **outwards** - a
  block type an author was handed, expanded into the primitives it stands
  for, byte-identically. This file walks the same arrangement **inwards**.
  `StatifierBlocks.Composite.Collapse.propose/3` reads the Guarded step's
  own expansion back as a `StatifierBlocks.Composite.Data` declaration; that
  declaration is registered beside the module composite it came from; and
  the two are compared where they can be compared exactly - the compiled
  bytes.

  Both halves are sb ADR-0005 part (iii) as amended 2026-09-07, clauses
  `15E` to `20E`, read at the pinned commit rather than paraphrased.

  ## The one thing that does not come back identical, and why

  A collapse mints `"id_suffix"`es from each member's **type** - the last
  dot-separated segment, so `core.invoke` gives `invoke` - because a
  document id is arbitrary and carries no meaning to a later reader. The
  author of `StatifierExamples.Signup.GuardedStep` wrote `call`. So a
  declaration collapsed out of that composite's expansion expands to
  `blk_..._invoke` where the module expands to `blk_..._call`: same types,
  same configs, same tree, one different id, and therefore different state
  ids in the chart.

  The record states this consequence in as many words, so this file asserts
  it rather than working around it - and then states the byte identity that
  DOES hold, twice: once for the saved declaration against its own expansion
  (consent clause 6, which is about the composite and its expansion and says
  nothing about a second composite's ids), and once for the same declaration
  carrying the author's own `"id_suffix"`, which is the twin proper.

  A pure test: nothing here names LiveView, so it compiles and runs headless.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.{Block, Compiler, Composite, Document, Palette}
  alias StatifierBlocks.Composite.{Collapse, Data}
  alias StatifierBlocks.Edit.{History, Session}
  alias StatifierExamples.Charts
  alias StatifierExamples.Signup.GuardedStep

  # The fixture the module composite is read on, and the composite block in
  # it. Both are `StatifierExamples.CompositesTest`'s, deliberately: the
  # comparison is only worth anything if both directions are about one
  # arrangement.
  @fixture "signup_guarded_step"
  @composite_id "blk_gs_step"

  # The name the HOST gives the saved type. `15E`: a type name is a key in
  # the host's own palette namespace, so `propose/3` answers a row without
  # one and this app supplies it here, which is the whole of what a host
  # does before registering.
  @saved "myapp.guarded_step_saved"
  @authored "myapp.guarded_step_authored"

  describe "reading the Guarded step's own expansion back as a declaration" do
    # `15E` and `18E` together, on the one arrangement this app's records
    # carry. The row is storable and it is NOT named: a package that minted
    # a type name would be minting a collision in a namespace it cannot see.
    #
    # Sabotage: the refutation is about the PACKAGE's proposal, so the
    # discriminating mutation is in the dependency. In
    # `deps/statifier_blocks`, `Collapse.row/3` was made to write a
    # `"type_name"` into the row it answers, with
    # `MIX_ENV=test mix deps.compile statifier_blocks --force` before and
    # after - a stale test build reads as a false green. Red here and
    # nowhere else. Reverted from a copy and recompiled.
    test "the proposal is the storable row, and the name is the host's to give" do
      {:ok, declaration} = propose()

      assert declaration["version"] == 1
      refute Map.has_key?(declaration, "type_name")

      # Neither is invented either: a sentence and a palette entry are prose
      # and presentation the author never typed in this gesture.
      refute Map.has_key?(declaration, "sentence")
      refute Map.has_key?(declaration, "palette_entry")

      # No slot, so no pass-through slot. `RQ-SF037-3`: this composite has
      # none, and `20E` proposes one only for a slot left unfilled.
      refute Map.has_key?(declaration, "slots")
    end

    # `18E`'s unmarked reading, which is what the gesture hands over when the
    # author ticks nothing: every value that differs from its field's
    # declared default. Four of them here - the call and where it records,
    # the notification's label and its template - and `myapp:notify` is NOT
    # among them, because `myapp.notify`'s own field already defaults to it.
    #
    # Sabotage: changed `GuardedStep.subtree/1`'s `@outcome_path` from
    # `"signup.step_outcome"` to `""`, which is `core.invoke`'s declared
    # default for `assign_to`; `assign_to` dropped out of the proposal and
    # this case went red on the key list. Reverted from a copy.
    test "every value the arrangement carries that is not a default becomes a param" do
      {:ok, declaration} = propose()

      assert Enum.map(declaration["params"], & &1["key"]) ==
               ["invoke_type", "assign_to", "label", "template"]

      assert Enum.map(declaration["params"], & &1["default"]) ==
               ["myapp:provision", "signup.step_outcome", "Notify on failure", "provision_failed"]

      # Each param's field declaration is the SOURCE field's, carried across
      # rather than re-derived, so the control an author sees on the saved
      # step is the control they were looking at on the block.
      assert %{"type" => "path", "options" => %{}, "label" => "Write the result to"} =
               Enum.find(declaration["params"], &(&1["key"] == "assign_to"))
    end

    # The template: the subtree with each proposed value replaced by its
    # placeholder and every other value carried across as the literal it is.
    #
    # Sabotage: renamed `myapp.notify`'s `on_error` slot in
    # `GuardedStep.subtree/1` to `after`; the template's `"slots"` key
    # changed with it and this case went red. Reverted from a copy.
    test "the template is the arrangement with the proposed values parameterised" do
      {:ok, declaration} = propose()

      assert [
               %{
                 "type" => "core.invoke",
                 "id_suffix" => "invoke",
                 "config" => %{
                   "invoke_type" => %{"$param" => "invoke_type"},
                   "assign_to" => %{"$param" => "assign_to"},
                   "params" => ""
                 },
                 "slots" => %{"on_error" => [notify]}
               }
             ] = declaration["subtree"]

      assert %{
               "type" => "myapp.notify",
               "id_suffix" => "notify",
               "config" => %{
                 "invoke_type" => "myapp:notify",
                 "label" => %{"$param" => "label"},
                 "template" => %{"$param" => "template"}
               }
             } = notify
    end
  end

  describe "the declaration registered as a data composite beside the module one" do
    # What a host does with the map: name it, hand it to `declaration/1`, and
    # register the `{module, state}` entry in the palette it hands the
    # editor. `StatifierExamples.Charts.palette/1` is this app's seam for
    # that last step, and nothing in the package reaches it - a host that
    # never registers the row has done a legitimate thing.
    #
    # Sabotage: made `Charts.palette/1` ignore `extra` and answer
    # `registrations()` alone, which is a host that stored the row and
    # never put it back in front of an author; `new_block/2` answered
    # `:error` and this case went red on the match, taking the four cases
    # below with it. Reverted from a copy.
    test "the row a host names is a declaration the palette carries" do
      {:ok, declaration} = propose()

      assert {:ok, state} = Data.declaration(Map.put(declaration, "type_name", @saved))
      assert state.name == @saved
      assert state.version == 1

      palette = Charts.palette([{@saved, {Data, state}}])

      assert {:ok, block} = Palette.new_block(palette, @saved)
      assert block.type == @saved

      # A new block's config is each param's declared default, which by `18E`
      # is the value the author had selected - so the saved step opens on the
      # arrangement it was read from.
      assert block.config == %{
               "invoke_type" => "myapp:provision",
               "assign_to" => "signup.step_outcome",
               "label" => "Notify on failure",
               "template" => "provision_failed"
             }
    end

    # The record's sharp consequence, asserted so it cannot drift silently:
    # everything about the two expansions agrees except the one id the
    # minting rule spells from the member's TYPE where the author spelled it
    # by hand.
    #
    # Sabotage: renamed `GuardedStep.subtree/1`'s `"call"` local id to
    # `"invoke"`, which is the suffix the minting rule produces; the id
    # lists became equal and the `refute` went red. Reverted from a copy.
    test "the data twin expands to the same arrangement, under the minted ids" do
      {:ok, {module_members, _param_map}} = Composite.expand(composite_block(), GuardedStep)
      {:ok, {data_members, _param_map}} = Composite.expand(composite_block(@saved), saved_ref())

      module_blocks = Composite.flatten(module_members)
      data_blocks = Composite.flatten(data_members)

      assert Enum.map(module_blocks, & &1.type) == Enum.map(data_blocks, & &1.type)
      assert Enum.map(module_blocks, & &1.config) == Enum.map(data_blocks, & &1.config)

      assert Enum.map(module_blocks, & &1.id) == ["blk_gs_step_call", "blk_gs_step_notify"]
      assert Enum.map(data_blocks, & &1.id) == ["blk_gs_step_invoke", "blk_gs_step_notify"]

      refute Enum.map(module_blocks, & &1.id) == Enum.map(data_blocks, & &1.id)
    end

    # Consent clause 6, for the composite a Collapse produced: the compiled
    # chart of a document holding it is byte-identical to the chart of the
    # same document after it has been expanded in place. It is the same
    # obligation `StatifierExamples.CompositesTest` states for the two module
    # composites, over a declaration nobody wrote by hand.
    #
    # Sabotage: what reddens this is an arrangement that stops being legal -
    # `GuardedStep`'s `on_error` slot renamed to `after`, and
    # `Charts.palette/1` made to ignore `extra` so the type never resolves -
    # and both were run, red. What CANNOT redden it is a change that keeps
    # both compiles legal: both sides read one `Composite.expand/2` over one
    # template, so a change to the template moves both. That is the shape of
    # the obligation rather than a weakness in the case, exactly as
    # `StatifierExamples.CompositesTest` records for the module composites,
    # and it is why the case after this one exists. Reverted from copies.
    test "a document holding the data twin compiles to the same bytes as its expansion" do
      palette = saved_palette()
      block = composite_block(@saved)
      {:ok, {members, _param_map}} = Composite.expand(block, saved_ref())

      assert {:ok, composed} = compile(document([block]), palette)
      assert composed.warnings == [], "the saved composite does not compile clean"
      assert {:ok, expanded} = compile(document(members), palette)

      assert composed.scxml == expanded.scxml
      assert composed.provenance == expanded.provenance
      assert composed.invoke_types == expanded.invoke_types
    end

    # The twin proper. One substitution stands between the collapsed
    # declaration and the module composite - the `"id_suffix"` the author
    # spelled by hand - and with it made, the two are byte-identical in a
    # document: same chart, same provenance, same invoke types. That is the
    # fact the walk exists to establish, and it is the fact a host relies on
    # when it offers a saved step beside a written one.
    #
    # Sabotage: in `deps/statifier_blocks`, `Collapse.segment/1` was made to
    # mint `node` for every type rather than the type's last segment, so the
    # substitution below fixes the head node's suffix and the notification's
    # is wrong; `MIX_ENV=test mix deps.compile statifier_blocks --force`
    # before and after, and this case went red on the chart comparison.
    # Reverted from a copy and recompiled.
    test "with the author's own id_suffix the data twin is byte-identical to the module one" do
      {:ok, declaration} = propose()

      row =
        declaration
        |> Map.put("type_name", @authored)
        |> Map.put("subtree", [Map.put(hd(declaration["subtree"]), "id_suffix", "call")])

      assert {:ok, state} = Data.declaration(row)
      palette = Charts.palette([{@authored, {Data, state}}])

      assert {:ok, module_side} = compile(fixture_document(), Charts.palette())
      assert {:ok, data_side} = compile(document([composite_block(@authored, palette)]), palette)

      assert module_side.scxml == data_side.scxml
      assert module_side.provenance == data_side.provenance
      assert module_side.invoke_types == data_side.invoke_types
    end
  end

  describe "the replacement a host commits itself" do
    # `17E`. Nothing in the package calls `replacement/4`: the gesture does
    # not and `on_collapse` does not, because the swap can only happen after
    # the host has stored the declaration, named it and rebuilt its palette
    # with it. What this walks is the host's half, through the same
    # `Edit.Session.commit/2` every other editor gesture goes through.
    #
    # The chart comparison substitutes ONE id. `replacement/4` builds its
    # block with `Block.new/2`, which mints a fresh document id, and a
    # document id is arbitrary by the same rule that makes the collapse mint
    # suffixes from types rather than from ids. With that one substitution
    # the pre-Expand chart comes back exactly - which is the round trip:
    # expand an authored composite, collapse the arrangement, register it,
    # commit the replacement, and the chart is where it started.
    #
    # Sabotage: in `deps/statifier_blocks`, `Collapse.replacement/4` was made
    # to insert one index PAST the arrangement's own target rather than at
    # it; `MIX_ENV=test mix deps.compile statifier_blocks --force` before
    # and after, and this case went red - red on the target assertion
    # first, which is the one that says "where the arrangement was".
    # Reverted from a copy and recompiled.
    test "committing the compound puts the composite back where the arrangement was" do
      {:ok, declaration} = propose()

      row =
        declaration
        |> Map.put("type_name", @authored)
        |> Map.put("subtree", [Map.put(hd(declaration["subtree"]), "id_suffix", "call")])

      {:ok, state} = Data.declaration(row)
      palette = Charts.palette([{@authored, {Data, state}}])

      expanded = expanded_document()
      session = %Session{palette: palette, document: expanded, history: History.new()}

      assert {:ok, {:compound, [{:remove, "blk_gs_step_call"}, {:insert, target, _block}]}} =
               Collapse.replacement(expanded, "blk_gs_step_call", @authored, declaration)

      assert target == {"blk_gs_root", "body", 0}

      assert {:ok, moved} = Session.commit(session, edit(expanded, declaration))

      assert [root, composite] = Document.blocks(moved.document)
      assert root.id == "blk_gs_root"
      assert composite.type == @authored

      # One remove with one insert is one compound, so the author sees one
      # gesture: one press of Undo puts the arrangement back.
      assert {:ok, stepped} = Session.step(moved, :undo)
      assert Document.to_json(stepped.document) == Document.to_json(expanded)

      # And the chart is the one the walk started from, under the id the
      # replacement minted.
      assert {:ok, before_expand} = compile(fixture_document(), Charts.palette())
      assert {:ok, after_commit} = compile(moved.document, palette)

      assert String.replace(after_commit.scxml, composite.id, @composite_id) ==
               before_expand.scxml
    end
  end

  # -- helpers -----------------------------------------------------------

  # The proposal every case here starts from: the Guarded step's own
  # expansion, collapsed back, unmarked - which is what a tray with nothing
  # ticked hands over.
  @spec propose() :: {:ok, map()} | {:error, term()}
  defp propose do
    expanded = expanded_document()
    ids = expanded |> Document.blocks() |> Enum.map(& &1.id) |> List.delete("blk_gs_root")

    Collapse.propose(expanded, Charts.palette(), ids)
  end

  @spec edit(Document.t(), map()) :: StatifierBlocks.Edit.t()
  defp edit(expanded, declaration) do
    {:ok, command} =
      Collapse.replacement(expanded, "blk_gs_step_call", @authored, declaration)

    command
  end

  @spec saved_state() :: Data.state()
  defp saved_state do
    {:ok, declaration} = propose()
    {:ok, state} = Data.declaration(Map.put(declaration, "type_name", @saved))

    state
  end

  @spec saved_ref() :: Palette.type_ref()
  defp saved_ref, do: {Data, saved_state()}

  @spec saved_palette() :: Palette.t()
  defp saved_palette, do: Charts.palette([{@saved, {Data, saved_state()}}])

  # The composite block, at the fixture's own id so both expansions mint
  # their member ids from one prefix and the only difference left is the
  # suffix itself.
  @spec composite_block() :: Block.t()
  defp composite_block do
    fixture_document() |> Document.blocks() |> Enum.find(&(&1.id == @composite_id))
  end

  @spec composite_block(Block.type_name()) :: Block.t()
  defp composite_block(type_name), do: composite_block(type_name, saved_palette())

  @spec composite_block(Block.type_name(), Palette.t()) :: Block.t()
  defp composite_block(type_name, palette) do
    {:ok, block} = Palette.new_block(palette, type_name)

    %{block | id: @composite_id}
  end

  # The fixture with its one composite replaced by the blocks it stands for -
  # which is what the editor's Expand control commits, and what the author in
  # this walk is looking at when they take "Save as a step".
  @spec expanded_document() :: Document.t()
  defp expanded_document do
    {:ok, {members, _param_map}} = Composite.expand(composite_block(), GuardedStep)

    document(members)
  end

  # The fixture's envelope around `blocks`. The root's own id and the
  # document's declared roots are the fixture's, which is what makes every
  # comparison here about the body and about nothing else.
  @spec document([Block.t()]) :: Document.t()
  defp document(blocks) do
    %Document{root: root} = fixture_document()

    %{fixture_document() | root: %{root | slots: %{"body" => blocks}}}
  end

  @spec fixture_document() :: Document.t()
  defp fixture_document do
    {:ok, fixture} = Charts.fixture(@fixture)

    fixture.document
  end

  # The one compile recipe this app uses everywhere, over whichever palette
  # the case is about.
  @spec compile(Document.t(), Palette.t()) :: {:ok, struct()} | {:error, [struct()]}
  defp compile(document, palette) do
    Compiler.compile(document, palette, known_invoke_types: MapSet.new(Charts.invoke_types()))
  end
end
