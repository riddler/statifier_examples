defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is a Hex requirement on the 0.18 line as of se-jqj,
  # the post-publish re-pin that puts the reference embedder back on what
  # is published. The 0.17 line before it made a stored duration mean one
  # thing: a
  # `:duration` field reads the duration strings `Predicator.Duration`
  # parses and refuses every other spelling, so `500ms` and `1.5s` finally
  # go through, and the intermediate canonical form between them and the
  # engine is gone along with the two public functions that served it.
  # This app calls neither, so the removal reaches nothing here. The
  # editor surfaces that land beside it - an inspector Fixtures tab, a
  # fixture-derived hint on a condition field, datamodel-derived value
  # candidates, done-event chips, an `on_select` callback - are all the
  # editor's own, reached through what this app already renders.
  #
  # 0.16.0 remains the floor, and it is REQUIRED rather than tidy: it is
  # the release in which a
  # condition's `:expression` field renders statifier-ui's expression
  # editor - picklists of field, operator and value over the source that
  # editor can round-trip - instead of a plain text input. That rendering
  # is conditional on `statifier_ui` being on the load path, which is the
  # requirement the next test guards. On the 0.15 line the picklists do
  # not exist at all.
  #
  # 0.15.0 added the Fixtures and Datamodel drawer tabs, the
  # `core.resumable_group` deadline advisory, and polish on the drawer's
  # tab strip and the truth table - all of it the editor's own surface,
  # reached through the drawer this app already renders, so nothing
  # host-side moved with it.
  #
  # 0.14.0 remains the floor: `StatifierBlocks.Runtime.DurableSubchart` - the handler that
  # answers `core.subchart` by starting the child as its own persisted run
  # - landed after 0.13.0, and se-6ag's durable subchart proof is written
  # against it. The 0.13 line carries only the in-memory
  # `StatifierBlocks.Runtime.Subchart`, whose `{:start_child, _, _}`
  # nothing but `Statifier.Session` executes. The sixth interim git pin
  # this arm carried (se-p22's pattern) is retired, and this test is what
  # says no git ref came back.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched, and the requirement alone
  # would pass against a tree still holding 0.13.0.
  #
  # The arm moves to the 0.18 line as of se-jqj. 0.18.0 lets a palette put
  # down more than one block at a time: a palette may name recipes beside
  # block types, and the core palette ships one, `deadline`, whose single
  # pick writes the `core.send` / `core.on_event` pair that spells a clock
  # interrupt - so this app's palette browser gains an entry it registers
  # nothing for. Alongside it a palette entry may declare `singleton:`,
  # `core.wait` and `core.send` rewrite a duration stored in the retired
  # spelling as the block resolves, and the editor toolbar's `:selected?`
  # attribute is renamed `:fittable?`. This app renders the editor whole and
  # passes that attribute nowhere, and declares `singleton:` on none of its
  # own block types, so neither reaches it.
  #
  # The arm moves to the 0.19 line as of se-eoj. 0.19.0 is about what a
  # chart does with the world outside it: `core.map` runs another chart
  # once per item of a datamodel list, `core.await` holds until a named
  # event arrives, `core.on_event` gains a `capture` map, and the editor
  # learns the datamodel's shape through a new `{:path, opts}` field type
  # and a `chart_outcomes` assign. All of it is additive and reached
  # through the editor this app renders whole. `core.map` compiles to one
  # `<invoke>` of the constant type `statifier_blocks:map`, a different
  # string from `statifier_blocks:subchart`, so the single-child handler
  # this app registers is not taken for a fan-out handler. Three charts
  # here name `core.map` as of se-j87, and this app registers a fan-out
  # handler for the other string. `core.subchart`'s `assign_to` is redeclared
  # `{:path, %{}}` rather than `:string`, which changes the control the
  # editor draws and not what the field accepts, so this app's stored
  # documents are unaffected.
  #
  # The arm moves to the 0.20 line as of se-goj, and this is the first move
  # this app asked for rather than followed. 0.20.0 makes the datamodel
  # document's declarations something the whole package reads:
  # `StatifierBlocks.Environment` carries the path-to-type map at any
  # position, a field naming a datamodel path may declare what it reads or
  # writes there, and an unsatisfied read is a validation error naming the
  # block, the field and the path. `statifier_datamodel` arrives
  # transitively with it, at `~> 0.1`, and is asserted below as a
  # transitive Hex entry rather than as a direct requirement: this app
  # names the package nowhere, because the `types` key its fixtures write
  # is data the compiler reads through the editor package's own
  # dependency. Two breaking edges came with the release and neither
  # reaches here - `StatifierBlocks.Predicates.Datamodel` is gone and this
  # app called it by no name, and a type expression spelled exactly
  # `unknown` reads as the permissive `:unknown` and this app spells no
  # such type.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.19.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.20.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # The arm moves to the 0.21 line, and this app asked for one half of it.
  # 0.21.0 makes the editor a debugger - a Source tab over the compiled
  # SCXML, the canvas seated in a run pane with statifier-ui's status,
  # scrubber and event log around it - and widens what a block can say:
  # `core.branch` declares a third slot for an arm whose condition cannot
  # be decided, a host states a rule about a whole document through
  # `validate_document/1` and the palette's `:validators` list, `core.map`
  # names what a child sees its item and its position under, and
  # `core.invoke`'s `assign_to` takes any datamodel path and declares the
  # path it writes. All of it is additive: a `core.branch` that leaves
  # `undecided` empty, and every type that classes no outcome as a
  # failure, compile to the bytes they compiled to at 0.20.0, so this
  # app's stored documents are unaffected.
  #
  # The half this app asked for is the failure seam. A block type may
  # class one of its outcomes as a failure through the new optional
  # `failure_outcomes/1` callback, and the compiler stamps a reserved
  # `statifier_persistence:run_status` `<donedata>` param on that
  # outcome's top-level `<final>` under both compile options - which is
  # what `statifier_persistence` 0.8.0 reads to mark the run `:failed`.
  # At 0.21.0 `core.map` and `core.subchart` classed their `error`
  # outcome; every other type, `core.invoke` included, classed nothing.
  # The chunk chart this app fans out over is a `core.sequence` around
  # one `core.invoke`, so it could not reach a failure-classed final,
  # and the host-side translation ADR-0008's decision 6 deletes stayed.
  #
  # The pin moves forward to the commit that ends that (`sb-hxs5`):
  # `core.invoke` classes its `error` outcome like the other two do, and
  # an unhandled failure-classed completion is carried to the document's
  # top-level `<final>`. The chunk chart's error final now carries the
  # reserved param, `statifier_persistence` marks the child run
  # `:failed` on its own step, and `se-cqr` deleted
  # `StatifierExamples.Charts.Durable`'s translation. That is what this
  # pin buys on top of `sb-hgjk`'s `compile_options` assign; the ledger
  # entry `se-cqr-statifier_blocks-sb-hxs5` carries it until 0.22.0 is
  # published.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # pin (`7c33c6c...`) and left `mix.lock` alone; it went red reporting
  # the recorded commit against the mutated expectation. Reverted from a
  # backup copy.
  # The arm moved to the 0.22 line, and briefly back to a Hex requirement:
  # 0.22.0 carries both commits the two earlier pins bought, so `se-gty`
  # retired them. What came beside them is additive here - `core.on_event`
  # takes an optional `payload` declaration, `core.map`'s `collect` accepts
  # any datamodel path rather than only a bare identifier, and this app's
  # documents declare neither - and the `statifier_datamodel` floor moved
  # to `~> 0.3` with the release, which is what the test above records.
  #
  # The arm moves to the 0.23 line, and back to a Hex requirement: 0.23.0
  # is published and carries the pair `se-obu` pinned for, so `se-yag`
  # retires that pin and the `refute` below is what says it did not come
  # back. The ledger entry `se-obu-statifier_blocks-sb-1c7g+sb-c9b6` is
  # what carried it until here.
  #
  # What the pin bought is the pair `StatifierExamplesWeb.EditorLiveTest`
  # asserts. `sb-c9b6` is the half nothing else could reach: the compiler
  # runs Config and Structure as a pair rather than in sequence, so a
  # config error on one card no longer hides an unsatisfied read on
  # another and the refusal carries the union - which is exactly the seam
  # the first production embedder met. `sb-1c7g` builds the insert probe
  # from `palette_entry/0`'s `default_config` as well as the schema's own
  # defaults, so a drop-time refusal is asked with the config an author is
  # about to write rather than with an empty path.
  #
  # What comes beside them in the release is additive here: a
  # `{:type_expr, opts}` field type that `core.map`'s `collect_type` and
  # `core.on_event`'s `payload` are the first to take (this app spells
  # neither), a typed child summary emitted only for a `child_use: true`
  # compile whose ROOT type declares a `donedata_type/1` (none this app
  # compiles under does), and `Palette.manifest/1`. The one note that
  # could reach a stored document is the typed environment SEEDING the
  # declared path types the datamodel document carries, and
  # `StatifierExamples.Charts.TypedEnvironmentTest` is what says none of
  # this app's documents leans on the looser reading. The
  # `statifier_datamodel` floor moves to `~> 0.4` with the release, which
  # is what the test below now records.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.22.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.23.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # The arm moves to the 0.24 line, and back to a Hex requirement: 0.24.0
  # is published and carries the three seams `se-1cl` pinned for, so
  # `se-298` retires that pin and the `refute` below is what says it did
  # not come back. The ledger entry
  # `se-1cl-statifier_blocks-sb-21gm+sb-w37s+sb-zjyv` is what carried it
  # until here.
  #
  # What the pin bought is what `StatifierExamplesWeb.PlanLiveTest`
  # asserts. `sb-w37s` is the half nothing else could reach:
  # `ViewModel.outline/1` is the pure pre-order `{node, depth, kind}` walk
  # a second view renders from, and `sentence/1` is what labels a row
  # without the card chrome. `sb-21gm` puts `hidden?` and `readonly?` on
  # `ViewModel.Field`, which is how a plain list drops the fields the
  # package editor has room for and this one does not. `sb-zjyv` makes
  # `Palette.new_block/2` public, so an insert here builds the same block
  # the editor's drop does.
  #
  # What the release adds on top of the pinned commit is one change and it
  # is additive here: the editor's optional `profile` assign and its
  # read-only mount (`sb-2bmk`). This app passes no `profile`, and a mount
  # that names none renders exactly what it rendered before, so
  # `StatifierExamplesWeb.EditorLiveTest` reads the same page it read on
  # the pin. The `statifier_datamodel` floor is unchanged at `~> 0.4`,
  # which is what the test below still records.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.23.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.24.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.24"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.24.)
    refute lock_line =~ ":git,"
  end

  # The path/type index the editor package reads a datamodel document
  # through, and the one dependency in this tree this app deliberately does
  # NOT name. It arrives because `statifier_blocks` 0.20.0 requires it, and
  # that is the whole shape of the seam: a host writes `types` into the
  # datamodel document it already hands the editor, and the package that
  # owns the read check is the one that depends on the package that owns
  # the document. A direct arm here would be this app claiming a
  # relationship it does not have.
  #
  # Sabotage: added `{:statifier_datamodel, "~> 0.1"}` to `mix.exs`'s deps
  # list; the `refute` went red naming the direct arm. Reverted from a
  # backup copy.
  #
  # The lock moves to 0.2.0, and the arm stays absent. Two packages now
  # require it rather than one - `statifier_ui` 0.9.0 takes it directly
  # too, at the same `~> 0.1`, which the resolved 0.2.0 satisfies - and
  # that changes nothing about the shape: this app still writes `types`
  # into a document it hands the editor and still names the reader
  # nowhere. 0.2.0 narrows the read check rather than widening it: a
  # record field a document declares optional no longer covers a shape
  # field the document marks required, so a read that was satisfied now
  # answers `{:missing, [name]}`. Breaking for a document that leaned on
  # the looser reading; none of this app's does, and
  # `StatifierExamples.Charts.TypedEnvironmentTest` is what says so.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.1.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.2.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # The lock moves to 0.3.0, and it moves because the pin above moved:
  # `statifier_blocks` main states `{:statifier_datamodel, "~> 0.3"}`, so
  # resolving the new pin resolves the new index. The arm is still absent
  # and this app still names the reader nowhere. 0.3.0 makes a `one_of`
  # on a declaration field a hint that never breaks a read, lets a scope
  # entry's type name a declaration, and turns the required-to-optional
  # row breaking; this app's documents declare no such row.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.2.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.3.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # The lock moves to 0.4.0, and it moves for two reasons where it used to
  # move for one: `statifier_blocks` 0.23.0 states `{:statifier_datamodel,
  # "~> 0.4"}` AND `statifier_ui` 0.10.0 states the same, both for the
  # inline shape arm 0.4.0 added to a type expression. The arm here is
  # still absent and this app still names the reader nowhere. 0.4.0 is
  # additive against a document: a type expression may be an inline
  # unnamed `{:shape, members}` instead of a name pointing at a
  # declaration, identity for that arm is member-set-wise, and
  # `Compatibility.breaks/2` documents a break's first element as the
  # kind. No document spelling changes, so this app's documents read
  # exactly as they did.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.3.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.4.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "statifier_datamodel arrives transitively and is not named directly" do
    deps = Mix.Project.config()[:deps]

    refute Enum.any?(deps, &match?({:statifier_datamodel, _requirement}, &1))
    refute Enum.any?(deps, &match?({:statifier_datamodel, _requirement, _opts}, &1))

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_datamodel": )))

    assert lock_line, "statifier_datamodel has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_datamodel, "0.4.)
    refute lock_line =~ ":git,"
  end

  # The component library, which this app declares DIRECTLY even though it
  # never calls it by name. `statifier_ui` is an OPTIONAL dependency of
  # `statifier_blocks`, exactly as `phoenix_live_view` is: the resolver
  # honours an optional requirement only if something else asks for the
  # package, so it does not arrive with the editor. Without this arm the
  # editor renders every `:expression` as the plain source input, and the
  # picklists se-21f exists to show never appear - quietly, since nothing
  # raises.
  #
  # 0.4.0 is the floor, as the release carrying both halves this app
  # needs: `StatifierUI.Live.ExpressionInput`'s picklist mode, and the
  # `StatifierUIExpressionPicklist` hook `assets/js/app.js` registers,
  # which is what composes the chosen source string into the one named
  # input the config form serializes.
  #
  # The arm moves to the 0.5 line as of se-awx. 0.5.0 reads per-value-kind
  # operator eligibility from `Predicator.Simple.operators/1` rather than a
  # table of its own, so a picklist offers what the grammar offers, in the
  # grammar's order; each entry gains `:lexeme` for the source spelling
  # while `:label` becomes the display phrase. That is a migration only for
  # a caller building source text out of `:label`, and this app calls the
  # module by no name at all. 0.5.0 also fixes a picklist control that kept
  # displaying the previous selection after an edit, which is the surface
  # this app exists to demonstrate.
  #
  # The arm moves to the 0.6 line as of se-jqj. 0.6.0 adds
  # `StatifierUI.Trace.Replay.from_events/4`, which builds the v1 trace wire
  # format from a persisted event log with no live session, and gives the
  # wire `error` object a discriminated reason arm, which is what lets an
  # `error.execution` or `error.communication` event reach a consumer
  # instead of being dropped in normalization. It removes
  # `StatifierUI.Live.ExpressionInput.display_label/1`, whose only work -
  # lowercasing a word-shaped lexeme for a dropdown - the grammar's own
  # display phrases had already taken over. This app calls the module by no
  # name at all, so the removal reaches nothing here.
  #
  # The arm moves to the 0.7 line as of se-eoj. 0.7.0 grows the wire
  # vocabulary to 25 types with `trace.conds_evaluated`, a selection
  # round's guard outcomes, and stops `session.start`'s `data` rows
  # falling back to the element's own span for `value_location`, so that
  # key is absent when a `<data>` element wrote no value. The wire format
  # version stays 1 in both cases, and only a consumer that ASSERTS the
  # vocabulary size, or reads `value_location`, has to move. This app does
  # neither: it names no `StatifierUI` module at all, and takes the
  # package as the load-path presence that turns the editor's expression
  # fields into picklists plus the `StatifierUIHooks` export
  # `assets/js/app.js` registers. 0.7.0 also raises the `predicator` floor
  # to `~> 9.4`, which the resolved 9.4.0 already satisfies.
  #
  # The arm moves to the 0.8 line as of se-goj, and here this app has a
  # reason of its own for the first time. 0.8.0 gives the expression
  # editor's clause builder a `path_types` assign, so a clause's operator
  # list and value control come from the kind a host declares for the path
  # rather than from whatever literal the source happens to carry. This app
  # still names no `StatifierUI` module - `statifier_blocks` projects the
  # datamodel document and hands the map across - but the surface that
  # appears when it does is this package's, and
  # `priv/fixtures/card-processing.datamodel.json` is what fills it: the
  # risk branch's lone `risk_rating >= 70` opens on an integer-declared
  # path and offers the numeric operators. The trace wire format is
  # untouched at version 1 and 25 types, so the trace half re-pins nothing.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.7.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.8.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # The arm moves to the 0.9 line, the release that gives this package a
  # required runtime dependency of its own: `statifier_datamodel ~> 0.1`,
  # so the expression editor takes a decoded datamodel `:document` and
  # projects the declared path types itself rather than needing a host to
  # assemble `:path_types` by hand. This app assembles neither -
  # `statifier_blocks` projects the document and hands the map across,
  # exactly as at 0.8.0 - and the test above is what says the new
  # requirement did not turn into a direct arm here.
  # `StatifierUI.Live.State.configuration_ids/1` answers the selected
  # configuration as the chart's own state ids rather than wire-format
  # indexes, `StatifierUI.Kino.inspect_trace/3` becomes a stepper over a
  # persisted trace, and the diagram's active-configuration highlight
  # takes an `:active_style`. All of it is additive, and this app names no
  # `StatifierUI` module at all. The trace wire format is untouched at
  # version 1 and 25 types, so the trace half re-pins nothing.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.8.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.9.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the statifier_ui dep is a direct Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_ui, "~> 0.10"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_ui": )))

    assert lock_line, "statifier_ui has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_ui, "0.10.)
    refute lock_line =~ ":git,"
  end

  # The engine is held on the 2.5 line as of se-vrq, and 2.5.0 is REQUIRED
  # rather than tidy: `statifier_oban` 0.6.0 states `{:statifier, "~> 2.5"}`
  # - the first release carrying `%Statifier.Effect.Invoke{}.caller_context`
  # and `Statifier.Invoke.Answer.done/4` - so the 2.4 line no longer
  # resolves alongside the durable timers this app arms.
  #
  # 2.4.0 was the floor before that: the first release carrying
  # `Statifier.Session`'s `:inherit_invoke_handlers` option, without which a
  # child session holds no handler map and the `signup_onboarding` wizard
  # child parks at its first step (se-8zp). 2.3.0 carries
  # `Statifier.Invoke.SyncHandler` and its wrapping adapter (se-4dt.2) but
  # not the inherited map. No `override: true` remains - with every
  # statifier-family dep on Hex, each package states a requirement the
  # resolver satisfies at one version, and asserting the bare two-tuple here
  # is what would catch an override quietly returning.
  #
  # Sabotage: pointed the requirement expectation at the real-but-wrong
  # previous floor `"~> 2.4"` and left `mix.exs` alone; the membership
  # assertion went red reporting `"~> 2.5"` against the mutated
  # expectation. Reverted from a backup copy.
  test "the statifier dep is the Hex requirement, with no override" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier, "~> 2.5"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier": )))

    assert lock_line, "statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier, "2.5.)
  end

  # The durable stepper. 0.3.0 was the floor two release lines back, as
  # the first release carrying ADR-0007's asynchronous invocation
  # seam - the dispatch fun's `:pending` arm and the `done_invocation/5` /
  # `failed_invocation/5` re-entry doors an answer arriving from an Oban job
  # comes back through (se-d74). On 0.2.0 every call is answered inside the
  # step that made it, so the asynchronous handler this app registers has no
  # seam to hang on. The interim git pin this arm carried before the release
  # is retired.
  #
  # It is held on the 0.5 line as of se-a5y, and 0.5.0 is REQUIRED rather
  # than tidy. 0.4.0 carries all of ADR-0008's durable subchart machinery
  # except the one piece a host has to have: sp-2yx widened
  # `StatifierPersistence.Driver.dispatch_context/0` to carry `:invoke`,
  # the whole effect being dispatched, without which a dispatch fun cannot
  # reach `src` and `StatifierBlocks.Runtime.DurableSubchart` raises rather
  # than guess. sp-i21 then landed ADR-0009's storage-phase telemetry, and
  # `[:statifier_persistence, :run, :step, :start | :stop]` is the span
  # every durable macrostep nests inside and the one the capstone's trace
  # graph is built out of. Both are in 0.5.0 and neither is in 0.4.0.
  #
  # 0.4.0 was also breaking for a storage adapter that encodes
  # `run_status/0` by an exhaustive match, since it gains a fourth terminal
  # value `:cancelled`. `StatifierExamples.Persistence` delegates every
  # status-bearing callback to the package's own Ecto adapter and matches no
  # status itself, so it rides the library's encoding.
  #
  # The two interim git pins this arm carried across campaign 026 are
  # retired, and the `refute` below is what says neither came back.
  #
  # It moves to the 0.6 line as of se-vrq. 0.6.0 emits statifier's own
  # `[:statifier, :session, ...]` telemetry from a durably-stepped run,
  # tagged `driver: :persistence`, so the OTel bridge draws the same
  # macrostep spans and effect events for a durable run as for a
  # session-hosted one. This app asks for nothing new to get that, and
  # 0.5.0 remains what the durable subchart and the trace graph need.
  #
  # It moves to the 0.7 line as of se-i4v, after a hold se-eoj took on
  # this arm alone. 0.7.0's V03 DDL could not apply to this app's SQLite
  # database at all: `Migrations.V03.up/1` created a GIN index over
  # `metadata jsonb_path_ops` unconditionally, ecto_sqlite3 raises
  # ArgumentError on any index carrying `using:`, and the whole migration
  # rolled back taking the `outcome_blob` column with it - while staying
  # on V02 was no escape either, since `outcome_blob` is an unconditional
  # field on the generated runs schema and se-eoj measured 73 of this
  # suite's tests failing on `no such column: s0.outcome_blob`. 0.7.1 is
  # the fix (sp-11w): the index is created only on
  # `Ecto.Adapters.Postgres`, the column on every adapter.
  #
  # The requirement is `~> 0.7`, which PERMITS 0.7.0 - a requirement is
  # not the guard here, and saying otherwise would be the mistake the
  # statifier_oban arm above records for its own 0.3.1 floor, where the
  # patch-level spelling was the guard until a major-line move made it
  # unnecessary. Here the move is within the line, so the lock is what
  # says which release resolved, and the `refute` below is what keeps
  # 0.7.0 out of the tree.
  #
  # What comes with 0.7.1 is a refusal rather than a raise, and it is not
  # free. Off Postgres the Ecto adapter now declares
  # `supports_metadata?/1` false, because the two metadata queries it
  # ships are `jsonb` containment SQL. `StatifierExamples.Persistence`
  # delegated that callback, so taking 0.7.1 unchanged would have refused
  # every durable subchart this app starts, at open, with
  # `:child_listing_unsupported`. It now answers `true` for itself, on the
  # same grounds it already wrote `list_runs_by_metadata/2` in Elixir on:
  # this adapter issues none of that SQL. The durable subchart cases in
  # `durable_test.exs` are what hold that.
  #
  # The two capabilities a Tier A fan-out needs at open -
  # `supports_run_outcome?/1` and `list_run_states_by_metadata/2` - are
  # exported here as of se-j87, and the guards they satisfy are asserted
  # in `StatifierExamples.PersistenceTest`. Without them
  # `Driver.start_child_at/6` refuses a fan-out at open rather than
  # half-starting one.
  #
  # The lock moves to 0.7.2 as of se-goj, under the same requirement.
  # 0.7.2 fixes the fan-out this app runs: a settlement used to read a
  # sibling's status as terminal while that sibling's answer was still in
  # flight and assembled a completed child with a `nil` donedata, and it
  # now waits for every child's recorded answer rather than only for every
  # child's terminal status. The `refute` below still keeps 0.7.0 out; what
  # says 0.7.2 is in is the lock assertion.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release (`"0.7.1"`) and left `mix.lock` alone; it went red reporting
  # the resolved 0.7.2 entry against the mutated expectation. Reverted from
  # a backup copy.
  #
  # The requirement moves to the 0.8 line, and with it the `refute` that
  # kept 0.7.0 out of the tree goes away: `~> 0.8` cannot resolve back to
  # 0.7.0 at all, so the guarantee that bought the patch-level guard is
  # kept by the major-line move, exactly as the `statifier_oban` arm below
  # records for its own 0.3.1 floor. The lock assertion is what ties the
  # requirement to the resolved release, as before.
  #
  # 0.8.0 is REQUIRED rather than tidy, on two counts. A chart can now
  # fail its own run: settling in a top-level `<final>` whose `<donedata>`
  # carries `statifier_persistence:run_status` set to `"failed"` persists
  # the run as `:failed` with the failure string `"failed_final"`, so a
  # `:first_error` fan-out cancels the failed child's siblings with no
  # host-side translation (ADR-0008's amendment, accepted). And
  # `Migrations.down/1` takes `from:`, the ceiling a capped migration
  # needs to roll all the way back - which
  # `priv/repo/migrations/20260830210002_add_statifier_persistence.exs`
  # now spells beside its `up(version: 2)`, closing the rollback gap
  # se-i4v measured on this app's SQLite database. V04 rebuilds V03's
  # `metadata` GIN index concurrently and is a no-op off Postgres, so no
  # migration here takes it.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release (`"0.7.2"`) and left `mix.lock` alone; it went red reporting
  # the resolved 0.8.0 entry against the mutated expectation. Reverted
  # from a backup copy.
  # The requirement moves to the 0.9 line, and back to a bare Hex
  # two-tuple: 0.9.0 is published and carries what the interim git pin
  # `se-dh0` took bought, so `se-gty` retires the pin and the `refute`
  # below is what says it did not come back. `override: true` goes with
  # it, and asserting the bare two-tuple is what would catch it quietly
  # returning - the pin needed it only because `statifier_oban` and
  # `statifier_blocks` state their own Hex requirements on this package
  # and no git ref satisfies one.
  #
  # 0.9.0 is REQUIRED rather than tidy. It carries ADR-0010's durable
  # per-run input log: the three optional storage-adapter callbacks
  # `StatifierExamples.Persistence` exports, `Runs.inputs/2` and
  # `Storage.input_log_supported?/1` to read it back, and migration V05
  # as the table. That log is the only history a stored run has ever had,
  # and without it `StatifierExamples.Charts.Replay` has nothing to
  # replay and the editor page's Run pane is empty.
  #
  # Two other edges of the release reach here and cost nothing.
  # `[:statifier_persistence, :child, :answered]`'s `outcome` is now the
  # invocation's rather than the door's, and this app asserts no
  # `outcome` on that event; and `Storage.Ecto`'s two metadata queries
  # refuse with `{:error, :metadata_unsupported}` off Postgres instead of
  # raising, where this app issues neither and answers
  # `supports_metadata?/1` for itself.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.8.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.9.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the statifier_persistence dep is the Hex requirement, with no override" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.10"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.10.)
    refute lock_line =~ ":git,"
  end

  # The durable-timer package. An earlier
  # requirement here was the patch-level `~> 0.3.1`, not `~> 0.3`, because
  # 0.3.0's cancellation query matches the delivering job itself: the
  # wizard's reminder job cancels its own delivery mid-flight and the live
  # reminder never arrives (se-p22). `~> 0.4` cannot resolve back to 0.3.0
  # at all, so the guarantee that bought the patch-level spelling is kept by
  # the major-line move and the spelling is no longer needed.
  #
  # The lock assertion is what ties the requirement to the resolved Hex
  # release; without it the membership check alone would pass against a
  # tree still holding an older one.
  #
  # It is held on the 0.5 line as of se-a5y, and that floor is REQUIRED
  # too: sob-43q landed ADR-0006's eleven telemetry events after 0.4.0,
  # and two of them are edges the capstone's trace graph asserts -
  # `[:statifier_oban, :timer, :scheduled]` and `[..., :timer, :fired]`.
  # On 0.4.0 a timer arms and fires and the graph has no edge across the
  # gap. The interim git pin this arm carried for se-opg is retired, and
  # the `refute` below is what says it did not come back.
  #
  # It moves to the 0.6 line as of se-vrq. 0.6.0 stores an async
  # invocation's `caller_context` on its Oban job row and hands it back at
  # delivery, and adds the optional four-argument
  # `StatifierOban.Invoke.Delivery.deliver/4` and `deliver_failure/4`;
  # this app's delivery module defines the three-argument doors and is
  # called exactly as before. That release is also what raises the engine
  # requirement to `~> 2.5` above.
  #
  # It moves to the 0.7 line as of se-eoj. Everything 0.7.0 adds serves a
  # Tier A fan-out - `StatifierOban.Invoke.FanOut`, the
  # `StatifierOban.Invoke.ChildStarter` seam named by the new
  # `:child_starter` option, the `:max_fan_out` cap and
  # `cancel_unstarted/3` - and all of it is additive. This app arms timers
  # and answers asynchronous invocations; it registers no handler that
  # returns `{:fan_out, items}` and wires no starter, so nothing here
  # changes until `core.map` is put to work.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.6.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.7.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # It moves to the 0.8 line. 0.8.0 adds no public surface and changes
  # what one existing arm does: a fan-out whose `items` list comes back
  # empty used to fail the invocation and now completes it, answering
  # immediately with `[]`, and the `:empty_items` refusal reason is gone
  # (`sb-ADR-0009` decision 8). Nothing on this app's side has to change
  # for that to take effect - `StatifierExamples.Charts.FanOut` never
  # named the retired reason - but the fan-out shape the ruling is about
  # is the one this app drives, so the move is this app's to take.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.7.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.8.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  #
  # It moves to the 0.9 line. 0.9.0 makes a fan-out visible in the
  # telemetry stream: `StatifierOban.Telemetry.events/0` gains
  # `[:statifier_oban, :invoke, :fan_out]`, `[..., :invoke,
  # :child_started]` and `[..., :invoke, :unstarted_cancelled]`, going
  # from eleven names to fourteen. A fan-out delivers nothing, so no
  # `:delivered` event fired for one and a cancelled sibling was reported
  # nowhere at all. Those events describe work this app actually does:
  # `StatifierExamples.Charts.FanOut` implements
  # `StatifierOban.Invoke.ChildStarter`, so `:child_started` fires once
  # per child it creates. The release also changes
  # `StatifierOban.Invoke.FanOut.start/5` to return `{:ok, summary}`
  # where it returned a bare `:ok`; this app is called BY that function
  # through the starter behaviour and never calls it, so nothing here
  # moves with it.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.8.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.9.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the statifier_oban dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, "~> 0.9"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_oban": )))

    assert lock_line, "statifier_oban has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_oban, "0.9.)
    refute lock_line =~ ":git,"
  end

  # The OTel bridge, which this app had no dependency on before se-opg -
  # nothing here produced a trace, so there was nothing to bridge.
  #
  # Held on the 0.4 line as of se-vrq. 0.4.0 adds
  # `OpentelemetryStatifier.Parent.register/2` and `SpanContext.lookup/2`,
  # neither of which this app uses - it steps through
  # `statifier_persistence`, whose own step span already declares the
  # parent, and it has no subscriber resolving an open span by key - and
  # puts `statifier.driver` on the macrostep span, which is how a backend
  # tells this app's durable macrosteps from session-hosted ones.
  #
  # 0.3.0 remains the floor: the two SIBLING setup
  # calls the capstone needs, `OpentelemetryStatifier.Persistence.setup/1`
  # and `OpentelemetryStatifier.Oban.setup/1`, landed after 0.2.0. On
  # 0.2.0 only the interpreter half exists, which in a durable run bridges
  # nothing at all. The interim git pin this arm was introduced on for
  # se-opg is retired, and the `refute` below is what says so.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.3.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.4.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the opentelemetry_statifier dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:opentelemetry_statifier, "~> 0.5"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "opentelemetry_statifier": )))

    assert lock_line, "opentelemetry_statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :opentelemetry_statifier, "0.5.)
    refute lock_line =~ ":git,"
  end

  # The SDK behind the bridge. `opentelemetry_statifier` depends only on
  # `opentelemetry_api` on purpose - a bridge that dragged an SDK into
  # every host would be choosing the host's exporter for it - so the host
  # is where both are named, and this asserts they are Hex requirements
  # rather than pins that would need retiring with the others.
  #
  # Sabotage: changed the expected requirement for `opentelemetry` to
  # `"~> 1.4"`; it went red on the membership assertion, which is the
  # point - the resolved 1.7.0 satisfies `~> 1.4` perfectly well, so only
  # a check on the literal arm catches the requirement being loosened.
  # Reverted from a backup copy.
  test "the OpenTelemetry SDK and API are plain Hex requirements" do
    deps = Mix.Project.config()[:deps]

    assert {:opentelemetry_api, "~> 1.5"} in deps
    assert {:opentelemetry, "~> 1.5"} in deps
  end
end
