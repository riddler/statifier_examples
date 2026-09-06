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
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.20"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.20.)
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
    assert lock_line =~ ~s({:hex, :statifier_datamodel, "0.1.)
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
  test "the statifier_ui dep is a direct Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_ui, "~> 0.8"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_ui": )))

    assert lock_line, "statifier_ui has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_ui, "0.8.)
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
  test "the statifier_persistence dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.7"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.7.2")
    refute lock_line =~ ~s({:hex, :statifier_persistence, "0.7.0")
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
  test "the statifier_oban dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, "~> 0.7"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_oban": )))

    assert lock_line, "statifier_oban has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_oban, "0.7.)
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

    assert {:opentelemetry_statifier, "~> 0.4"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "opentelemetry_statifier": )))

    assert lock_line, "opentelemetry_statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :opentelemetry_statifier, "0.4.)
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
