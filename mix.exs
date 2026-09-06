defmodule StatifierExamples.MixProject do
  use Mix.Project

  def project do
    [
      app: :statifier_examples,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [tool: ExCoveralls],
      dialyzer: [plt_add_apps: [:ex_unit, :mix]],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {StatifierExamples.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.13"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},

      # Persistence. SQLite keeps `mix setup` zero-service: the database is a
      # file under `priv/`, so a fresh clone needs no server to run the suite
      # or the dev app (se-cnv, campaign-021 ruling R11).
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.22"},

      # The engine. 2.4.0 is the floor: the first release carrying
      # `Statifier.Session`'s `:inherit_invoke_handlers` option, without
      # which a child session starts with no `:invoke_handlers` at all and
      # the `signup_onboarding` wizard child cannot answer its own
      # `myapp:signup` call. 2.3.0 - the floor this arm held before it -
      # carries `Statifier.Invoke.SyncHandler` and its wrapping adapter,
      # which this app's handlers are written against (se-4dt.2), but not
      # the inherited handler map. The interim git pin this arm carried
      # between the two releases is retired (se-p22's pattern).
      #
      # No `override: true` remains: with every statifier-family dep on
      # Hex, `statifier_blocks`, `statifier_persistence` and
      # `statifier_oban` each state a requirement on `statifier` the
      # resolver satisfies at one version. The override existed only to
      # make a git ref win over requirements no git ref can satisfy.
      #
      # The requirement moves to the 2.5 line, and 2.5.0 is REQUIRED
      # rather than tidy: `statifier_oban` 0.6.0 states
      # `{:statifier, "~> 2.5"}` - the first release carrying
      # `%Statifier.Effect.Invoke{}.caller_context` and
      # `Statifier.Invoke.Answer.done/4` - so the 2.4 line no longer
      # resolves alongside the durable timers this app arms.
      {:statifier, "~> 2.5"},

      # The durable stepper, and `StatifierPersistence.Driver` - the
      # run-to-quiescence loop `StatifierExamples.Charts.Durable` used to
      # write for itself (se-4dt.3). 0.3.0 is the floor: the first release
      # carrying ADR-0007's asynchronous invocation seam - the dispatch
      # fun's `:pending` arm, and the
      # `StatifierPersistence.Driver.done_invocation/5` and
      # `failed_invocation/5` doors an answer arriving from an Oban job
      # re-enters through. On 0.2.0 a call cannot outlive the step that
      # made it, which is the whole of se-d74. The interim git pin this
      # arm carried before the release is retired (se-p22's pattern).
      #
      # The requirement moves to the 0.4 line to keep the reference
      # embedder on what is published, not because this app consumes
      # 0.4.0's durable subcharts (ADR-0008) yet - it does not. 0.4.0 is
      # breaking for a storage adapter that encodes `run_status/0` by an
      # exhaustive match, since it gains a fourth terminal value
      # `:cancelled`. `StatifierExamples.Persistence` delegates every
      # status-bearing callback to the package's own Ecto adapter and
      # matches no status itself, so it rides the library's encoding and
      # needs no new clause.
      #
      # The requirement moves again, to the 0.5 line, and 0.5.0 is the
      # floor rather than a convenience. This app now DOES consume
      # ADR-0008's durable subcharts, and two pieces they need landed
      # after 0.4.0. sp-2yx widened
      # `StatifierPersistence.Driver.dispatch_context/0` to carry
      # `:invoke`, the whole `Statifier.Effect.Invoke` being dispatched:
      # without it a dispatch fun sees `type` and `params` only, cannot
      # reach `src` - the document id it resolves the child chart by -
      # and `StatifierBlocks.Runtime.DurableSubchart` raises rather than
      # guess. sp-i21 then landed ADR-0009's storage-phase telemetry, and
      # `[:statifier_persistence, :run, :step, :start | :stop]` is the
      # one paired seam in the family - the span every macrostep of a
      # durable step nests inside, and what the capstone's trace graph is
      # built out of. On 0.4.0 the durable subchart cannot resolve its
      # child, and on the interim pin before the telemetry it ran
      # correctly and emitted nothing at all.
      #
      # Everything else the durable subchart needs (the dispatch fun's
      # `{:start_child, _, _}` arm, the `chart_resolver:` option,
      # `parent_link/2`, `answer_parent/3`, `Runs.cascade_cancel/3`,
      # `list_runs_by_metadata/2` on the storage behaviour) was already in
      # 0.4.0. The two interim git pins this arm carried across
      # campaign 026 are retired here (se-p22's pattern).
      #
      # The requirement moves to the 0.6 line to keep the reference
      # embedder on what is published. 0.6.0 emits statifier's own
      # `[:statifier, :session, ...]` telemetry from a durably-stepped
      # run, tagged `driver: :persistence`, so the OTel bridge draws the
      # same macrostep spans and effect events for a durable run as for a
      # session-hosted one. This app asks for nothing new to get that -
      # it is the bridge's doing, not the host's - and 0.5.0 remains what
      # the durable subchart and the capstone's trace graph actually need.
      #
      # The requirement moves to the 0.7 line, and getting there took two
      # releases. 0.7.0's V03 DDL could not apply to this app's SQLite
      # database: `Migrations.V03.up/1` created a GIN index over
      # `metadata jsonb_path_ops` unconditionally, ecto_sqlite3 raises
      # ArgumentError on any index carrying `using:`, and the whole
      # migration rolled back - while staying on V02 was no escape, since
      # `outcome_blob` is an unconditional field on the generated runs
      # schema from 0.7.0 on. se-eoj measured both ends and held this arm
      # alone at 0.6 while its three siblings moved; the defect went
      # upstream as sp-11w. 0.7.1 is the fix - the index is created only on
      # `Ecto.Adapters.Postgres`, the column on every adapter.
      #
      # The requirement below is `~> 0.7` and NOT `~> 0.7.1`, which means it
      # permits 0.7.0 - the one release on this line this app cannot migrate.
      # What keeps 0.7.0 out is `mix.lock`, and the guard test asserts that
      # directly rather than trusting the requirement to do it.
      #
      # Taking V03 is two migrations rather than one, and the pair is in
      # `priv/repo/migrations`: the migration that has already run on every
      # database this app has is capped at `version: 2`, and V03 arrives in
      # its own `from: 3` migration, so a fresh clone and an upgraded
      # database take the same steps in the same order.
      #
      # 0.7.1 also makes the Ecto adapter declare `supports_metadata?/1`
      # false off Postgres, which is a refusal at open for a durable
      # subchart rather than a raise from inside one.
      # `StatifierExamples.Persistence` answers that callback for itself
      # now, on the same grounds it already wrote `list_runs_by_metadata/2`
      # in Elixir on.
      #
      # The LOCK moves to 0.7.2 under that same `~> 0.7` requirement.
      # 0.7.2 fixes the fan-out this app runs: a settlement used to read a
      # sibling's status as terminal while that sibling's answer was still
      # in flight, and assembled a completed child with a `nil` donedata;
      # it now waits for every child's recorded answer rather than only
      # for every child's terminal status. The hybrid fan-out
      # `StatifierExamples.Charts.FanOut` drives is exactly the shape that
      # loses a child's result to it.
      #
      # The requirement moves to the 0.8 line. 0.8.0 is what lets a chart
      # fail its own run: settling in a top-level `<final>` whose
      # `<donedata>` carries `statifier_persistence:run_status` set to
      # `"failed"` persists the run as `:failed` with the failure string
      # `"failed_final"`, so a `:first_error` fan-out cancels the failed
      # child's siblings with no host in the loop (ADR-0008's amendment,
      # accepted). The host-side translation this app writes for exactly
      # that case is deleted by that amendment's decision 6, and cannot be
      # yet: see `StatifierExamples.Charts.Durable`'s `fail_child/3` for
      # what is still missing on the block side.
      #
      # 0.8.0 also gives `Migrations.down/1` a `from:` ceiling, which the
      # capped migration in `priv/repo/migrations` now spells beside its
      # `up(version: 2)` - the rollback gap se-i4v measured on this app's
      # SQLite database is closed, and `mix ecto.rollback --all` runs
      # clean. Its V04 rebuilds V03's `metadata` GIN index with `CREATE
      # INDEX CONCURRENTLY`; that is a Postgres-only step and a no-op on
      # SQLite, so no migration here takes it. And the package's own
      # conformance suite now tags its four Postgres-only cases
      # `@tag :postgres`, which is the documented way to run the Ecto
      # adapter off Postgres - `docs/non-postgres-backends.md` there - and
      # what this app has been doing in Elixir all along.

      # PINNED to `statifier_persistence` MAIN, at the commit carrying the
      # durable per-run input log (its ADR-0010, `sp-80g`). 0.9.0 is not
      # published yet, and the log is what this app's editor page replays a
      # stored run from: the two optional adapter callbacks the record adds -
      # append one input, list a run's inputs in order - are the only door to
      # the ordered `%Statifier.Event{}` entries `StatifierUI.Trace.Replay`
      # needs. `se-gty` moves this arm back to `{:statifier_persistence, "~>
      # 0.9"}` once the operator publishes.
      {:statifier_persistence,
       github: "riddler/statifier_persistence",
       ref: "27a7a15b6ebb8dd2bfd6a1c3b5779c2bbd042feb",
       override: true},

      # Durable timers. `statifier_oban` never owns an Oban instance
      # (its ADR-0002): this app supplies one, on Oban's SQLite engine, so
      # the wizard's abandonment reminder is a stored job rather than a
      # `Process.send_after/3` that dies with the node. Oban itself
      # arrives through this package rather than being named again here.
      #
      # The 0.3.1 floor this arm held was REQUIRED, not merely permitted:
      # 0.3.0's cancellation query matches the delivering job itself, so the
      # reminder job cancels its own delivery mid-flight and the live 90s
      # reminder never arrives. The 0.4 line carries that fix and cannot
      # resolve back to 0.3.0, so the pin-forward keeps the guarantee
      # without needing the patch-level spelling.
      #
      # Nothing here consumes 0.4.0's additions yet - an invoke handler's
      # `run/2` scope arm, and `StatifierOban.Timer.Delivery.fired_event/2`.
      #
      # The requirement moves to the 0.5 line, and that floor is REQUIRED
      # too: sob-43q landed ADR-0006's eleven telemetry events after
      # 0.4.0, and two of them are edges the one-trace-graph proof
      # asserts - `[:statifier_oban, :timer, :scheduled]`, the span event
      # that records the arming, and `[..., :timer, :fired]`, the
      # detached span that links back to the arming trace through
      # `caller_context`. On 0.4.0 a timer arms and fires and the trace
      # graph has no edge across the gap. The interim git pin this arm
      # carried for se-opg is retired here.
      #
      # The requirement moves to the 0.6 line. 0.6.0 stores an async
      # invocation's `caller_context` on its Oban job row and hands it
      # back at delivery, and adds the optional four-argument
      # `StatifierOban.Invoke.Delivery.deliver/4` and
      # `deliver_failure/4` a process-less host builds its own answer
      # event from. This app's delivery module defines the three-argument
      # doors and is called exactly as before. The release is also what
      # raises the engine requirement to `~> 2.5` above.
      #
      # The requirement moves to the 0.7 line to keep the reference
      # embedder on what is published. Everything 0.7.0 adds serves a
      # Tier A fan-out - `StatifierOban.Invoke.FanOut`, the
      # `StatifierOban.Invoke.ChildStarter` seam named by the new
      # `:child_starter` option, the `:max_fan_out` cap, and
      # `cancel_unstarted/3` - and all of it is additive. This app arms
      # timers and answers asynchronous invocations; it registers no
      # handler that returns `{:fan_out, items}` and wires no starter, so
      # nothing here changes until `core.map` is put to work (se-j87).
      #
      # The requirement moves to the 0.8 line. 0.8.0 adds no public
      # surface and changes what one existing arm does: a fan-out whose
      # `items` list comes back empty used to fail the invocation and now
      # completes it, answering immediately with `[]`, and the
      # `:empty_items` refusal reason is gone (`sb-ADR-0009` decision 8).
      # Nothing on this app's side has to change for that to take effect -
      # `StatifierExamples.Charts.FanOut` returns whatever the parent's
      # list holds and never named the retired reason - but the shape it
      # fans out over is exactly the one the ruling is about, so the move
      # is this app's to take rather than one it merely follows.
      {:statifier_oban, "~> 0.8"},

      # The OTel bridge for the family, and the app's telemetry consumer.
      # This app had no dependency on it before se-opg: nothing here
      # produced a trace, so there was nothing to bridge.
      #
      # 0.3.0 is the floor: the two SIBLING setup calls this app needs -
      # `OpentelemetryStatifier.Persistence.setup/1` and
      # `OpentelemetryStatifier.Oban.setup/1`, and with them the whole of
      # ots-ADR-0004's bridge-owned nesting - landed after 0.2.0. On
      # 0.2.0 only `OpentelemetryStatifier.setup/1` exists, which bridges
      # the interpreter's family alone: the macrostep spans would arrive
      # as unrelated roots with no step span to nest inside and no timer
      # seam at all, which is the proof's whole subject. The interim git
      # pin this arm was introduced on is retired here.
      #
      # The requirement moves to the 0.4 line. 0.4.0 adds
      # `OpentelemetryStatifier.Parent.register/2` and
      # `SpanContext.lookup/2`, neither of which this app uses: it steps
      # through `statifier_persistence`, whose own step span already
      # declares the parent the macrostep spans nest inside, and it has
      # no subscriber resolving an open span by key. What it does get for
      # free is `statifier.driver` on the macrostep span, which is how a
      # backend tells this app's durable macrosteps from session-hosted
      # ones. 0.3.0 remains the floor the capstone needs.
      {:opentelemetry_statifier, "~> 0.4"},

      # The SDK behind that bridge. `opentelemetry_statifier` depends only
      # on `opentelemetry_api` on purpose - a bridge that dragged an SDK
      # into every host would choose the host's exporter for it - so the
      # host is where the SDK and the exporter are named. This app
      # configures a processor per environment rather than here; see
      # `config/config.exs` and `StatifierExamples.Charts.Tracing`.
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry, "~> 1.5"},

      # The authoring layer this app is the reference embedder for.
      # `phoenix_live_view` is optional there and supplied by this app above.
      statifier_blocks_dep(),

      # The observing/authoring component library, declared DIRECTLY rather
      # than taken transitively. `statifier_ui` is an OPTIONAL dependency of
      # `statifier_blocks` (0.18.0), exactly as `phoenix_live_view` is, so it
      # does not arrive with the editor: an optional dependency is a
      # requirement the resolver honours only if something else asks for the
      # package, and here nothing else does. Without this line the editor
      # renders every `:expression` as the plain source input and the
      # picklists never appear.
      #
      # 0.4.0 is the floor, as the release carrying both halves this app
      # needs: `StatifierUI.Live.ExpressionInput`'s picklist mode, and the
      # `StatifierUIExpressionPicklist` hook that writes the composed source
      # string back into the one named input the config form serializes. The
      # hook is registered in `assets/js/app.js`; the component without it
      # renders picklists that operate and change nothing (se-21f).
      #
      # The arm moves to the 0.5 line to keep the reference embedder on what
      # is published. 0.5.0 reads per-value-kind operator eligibility from
      # `Predicator.Simple.operators/1` rather than a table of its own, so a
      # picklist offers what the grammar offers, in the grammar's order; the
      # entries it returns gain `:lexeme` for the source spelling while
      # `:label` becomes the display phrase, which is a migration only for a
      # caller that builds source text from `:label`, and this app calls the
      # module by no name at all. It also fixes a picklist control that kept
      # showing the previous selection after an edit, which is exactly the
      # surface this app demonstrates. 0.4.0 remains the floor, as the
      # release carrying the picklist mode and its hook.
      #
      # The arm moves to the 0.6 line to keep the reference embedder on what
      # is published. 0.6.0 adds `StatifierUI.Trace.Replay.from_events/4`,
      # which builds the v1 trace wire format from a persisted event log with
      # no live session, and gives the wire `error` object a discriminated
      # reason arm, which is what lets an `error.execution` or
      # `error.communication` event reach a consumer instead of being dropped
      # in normalization. It removes
      # `StatifierUI.Live.ExpressionInput.display_label/1`, whose only work -
      # lowercasing a word-shaped lexeme for a dropdown - the grammar's own
      # display phrases had already taken over; this app called it by no name
      # at all, so the removal reaches nothing here. 0.4.0 remains the floor,
      # as the release carrying the picklist mode and its hook.
      #
      # The arm moves to the 0.7 line to keep the reference embedder on what
      # is published. The wire vocabulary grows to 25 types with
      # `trace.conds_evaluated`, a selection round's guard outcomes; the
      # format version stays 1, and only a consumer that ASSERTS the
      # vocabulary size rather than reading it has to move.
      # `session.start`'s `data` rows also stop falling back to the
      # element's own span for `value_location`, so the key is absent now
      # when a `<data>` element wrote no value. This app pins no vocabulary
      # count and reads no `value_location`: it names no `StatifierUI`
      # module at all, taking the package as the load-path presence that
      # turns the editor's expression fields into picklists plus the
      # `StatifierUIHooks` export `assets/js/app.js` registers. So neither
      # change reaches it. 0.7.0 also raises the `predicator` floor to
      # `~> 9.4`, which the resolved 9.4.0 already satisfies.
      #
      # The arm moves to the 0.8 line, and here the reference embedder
      # finally has a reason of its own rather than a tidiness one. 0.8.0
      # gives the expression editor's clause builder a `path_types`
      # assign: a clause's operator list and value control come from the
      # kind a host declares for the path rather than from whatever
      # literal the source happens to carry. This app still names no
      # `StatifierUI` module - `statifier_blocks` 0.20.0 is what projects
      # the datamodel document's declarations and hands the map across -
      # but the surface that appears when it does is this package's, and
      # the card-processing document's `types` key is what fills it. The
      # trace wire format is untouched at version 1 and 25 types, so the
      # trace half of this app re-pins nothing. 0.4.0 remains the floor,
      # as the release carrying the picklist mode and its hook.
      #
      # The arm moves to the 0.9 line. 0.9.0 is the release that gives
      # this package a required runtime dependency of its own,
      # `statifier_datamodel ~> 0.1`, so the expression editor takes a
      # decoded datamodel `:document` and projects the declared path types
      # itself instead of needing a host to assemble `:path_types` by
      # hand. This app assembles neither: `statifier_blocks` projects the
      # document and hands the map across, exactly as at 0.8.0. Beside
      # that, `StatifierUI.Live.State.configuration_ids/1` answers the
      # selected configuration as the chart's own state ids rather than
      # wire-format indexes, `StatifierUI.Kino.inspect_trace/3` becomes a
      # stepper over a persisted trace, and the diagram's
      # active-configuration highlight takes an `:active_style` - all of
      # it additive, and all of it reached through modules this app names
      # nowhere. The trace wire format is untouched at version 1 and 25
      # types, so the trace half of this app re-pins nothing.
      statifier_ui_dep(),

      # Dev / test. The gate is ex_quality's; see `.quality.exs`.
      {:ex_quality, "~> 0.14", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  # The editor package. Setting `STATIFIER_BLOCKS_PATH` to a local
  # `statifier_blocks` checkout swaps in a path dep on that directory, which is
  # how a host-side change is tried against an unreleased editor. The arm is a
  # local convenience: the `mix.lock` (and `mix.exs`) changes it produces are
  # never committed, and CI sets no env, so CI resolves the default arm.
  #
  # The default arm is a Hex requirement on the 0.14 line, and 0.14.0 is
  # the floor: `StatifierBlocks.Runtime.DurableSubchart` - the handler
  # that answers `core.subchart` by starting the child as its own persisted
  # `statifier_persistence` run - landed after 0.13.0 and is what this
  # app's durable subchart proof is written against. 0.13.0 carries only
  # the in-memory `StatifierBlocks.Runtime.Subchart`, whose
  # `{:start_child, _, _}` nothing but `Statifier.Session` executes. The
  # sixth interim git pin this arm carried is retired here.
  #
  # The Hex requirement this arm held before that pin was the 0.13 line.
  # 0.12.0 was the floor before that, as the first release carrying the
  # drafts shelf -
  # `core.drafts` and
  # `core.placeholder`, `StatifierBlocks.Shelf`, and the `.sb-slot--tray`
  # strip the editor draws a parked fragment in. On 0.11.0 the
  # `card_processing_sketch` fixture names two types no palette resolves,
  # so the reference embedder cannot show the tray it exists to show; that
  # release does carry the two earlier surfaces this app is written
  # against, ADR-0007's block-type defaults layer with
  # `StatifierBlocks.InvokeStep` (se-4dt.1) and `StatifierBlocks.Runtime`'s
  # `Subchart` handler (se-4dt.4). Five interim git pins served this arm
  # across the campaign era (se-p22's pattern); they are retired.
  #
  # 0.13.0 changes what the editor shows first: a non-empty drafts shelf
  # now opens folded, so a document with parked work opens showing its flow
  # rather than its shelf. The shelf's placement rules, its compile output
  # and the fold control itself are unchanged, so this app's tray coverage
  # holds as written.
  #
  # The arm moves to the 0.15 line to keep the reference embedder on what
  # is published. 0.15.0 adds two more drawer tabs - Fixtures, which
  # drives every attached fixture row through the compiled chart, and
  # Datamodel, a read-only grid of the declared paths - plus the
  # `core.resumable_group` deadline advisory, and polishes the drawer's
  # tab strip and the truth table. All of that is the editor's own
  # surface, reached through the drawer this app already renders, so no
  # host-side registration changes. 0.14.0 remains the floor, as the
  # release carrying `StatifierBlocks.Runtime.DurableSubchart`.
  #
  # The arm moves to the 0.16 line, and 0.16.0 is REQUIRED rather than
  # tidy: it is the release that fills the expression seam. A condition's
  # `:expression` field now renders statifier-ui's expression editor -
  # picklists of field, operator and value over the source that editor can
  # round-trip, and the plain source input over the rest - so a guard like
  # `amount >= 500` is composed rather than typed. That rendering is
  # conditional on `statifier_ui` being on the load path, which is why the
  # requirement below exists. On 0.15.0 an `:expression` is a text field
  # and the picklists this app demonstrates do not exist at all.
  #
  # The arm moves to the 0.17 line to keep the reference embedder on what is
  # published. 0.17.0 makes a stored duration mean one thing: a `:duration`
  # field reads the duration strings `Predicator.Duration` parses and
  # refuses every other spelling, which is what lets `500ms` and `1.5s`
  # through, and the intermediate canonical form between them and the engine
  # is gone along with the two public functions that served it. This app
  # calls neither, so the removal reaches nothing here. Alongside it the
  # editor grows an inspector Fixtures tab, a fixture-derived hint beside a
  # condition field, datamodel-derived value candidates, done-event chips
  # drawn as the block they name, and an `on_select` callback for a host
  # panel that follows the canvas - all of it the editor's own surface,
  # reached through what this app already renders, so no host-side
  # registration changes. 0.16.0 remains the floor, as the release that
  # fills the expression seam.
  #
  # The arm moves to the 0.18 line to keep the reference embedder on what is
  # published. 0.18.0 lets a palette put down more than one block at a time:
  # a palette may name recipes beside block types, and the core palette ships
  # one, `deadline`, whose single pick writes the `core.send` /
  # `core.on_event` pair that spells a clock interrupt - so this app's
  # palette browser gains an entry it registers nothing for. Alongside it a
  # palette entry may declare `singleton:`, `core.wait` and `core.send`
  # rewrite a duration stored in the retired spelling as the block resolves -
  # so a document saved before the 0.17 duration pivot opens clean - and the
  # editor toolbar's `:selected?` attribute is renamed `:fittable?`. This app
  # renders the editor whole and passes that attribute nowhere, and declares
  # `singleton:` on none of its own block types, so neither reaches it.
  # 0.16.0 remains the floor, as the release that fills the expression seam.
  #
  # The arm moves to the 0.19 line to keep the reference embedder on what is
  # published. 0.19.0 is about what a chart does with the world outside it:
  # `core.map` runs another chart once per item of a datamodel list,
  # `core.await` holds until a named event arrives, `core.on_event` gains a
  # `capture` map, and the editor learns the datamodel's shape through a new
  # `{:path, opts}` field type and a `chart_outcomes` assign. All of it is
  # additive and reached through the editor this app renders whole. Two are
  # worth naming because this app could have felt them and does not:
  # `core.map` compiles to one `<invoke>` of the constant type
  # `statifier_blocks:map`, a DIFFERENT string from
  # `statifier_blocks:subchart`, so the single-child handler this app
  # registers is not silently taken for a fan-out handler - the gap is
  # reported by `StatifierBlocks.Compiler.InvokeTypes` at deploy time, and
  # no chart here names `core.map` yet (se-j87 is where it will). And
  # `core.subchart`'s `assign_to` is redeclared `{:path, %{}}` rather than
  # `:string`, which changes the control the editor draws for it and not
  # what it accepts, so this app's stored documents are unaffected.
  #
  # The arm moves to the 0.20 line, and this is a release this app was
  # waiting for rather than one it follows. 0.20.0 makes the datamodel
  # document's declarations something the whole package reads:
  # `StatifierBlocks.Environment` carries the path-to-type map at any
  # position in a document, a field naming a datamodel path may declare
  # what it reads or writes there, and an unsatisfied read is a validation
  # error naming the block, the field and the path. The path/type index
  # itself is `statifier_datamodel`'s, which arrives TRANSITIVELY at
  # `~> 0.1`: this app names it nowhere and depends on it not at all,
  # because the `types` key its fixture writes is data the compiler reads
  # through the editor package's own dependency. Two breaking edges come
  # with it and neither reaches here - `StatifierBlocks.Predicates.Datamodel`
  # is gone, and this app called it by no name; and a type expression
  # spelled exactly `unknown` reads as the permissive `:unknown`, and this
  # app spells no such type. 0.16.0 remains the floor, as the release that
  # fills the expression seam.
  #
  # The arm moves to the 0.21 line, the release that makes the editor
  # a debugger and widens what a block can say. The drawer gains a
  # Source tab over the compiled SCXML, the canvas takes a seat in a
  # run pane, `core.branch` declares a third slot for a condition that
  # cannot be decided, a host can state a rule about a whole document
  # through `validate_document/1` and the palette's `:validators`
  # list, `core.map` names what a child sees its item and its position
  # under, and `core.invoke`'s `assign_to` takes any datamodel path
  # and declares the path it writes. All of it is additive: a
  # `core.branch` that leaves `undecided` empty and every type that
  # classes no outcome as a failure compile to the bytes they compiled
  # to at 0.20.0, so this app's stored documents are unaffected.
  #
  # The half this app was waiting for is the failure seam: a block
  # type may class one of its outcomes as a failure through the new
  # `failure_outcomes/1` callback, and the compiler stamps the
  # reserved `statifier_persistence:run_status` `<donedata>` param on
  # that outcome's top-level `<final>`. At 0.21.0 `core.map` and
  # `core.subchart` classed their `error` outcome and every other type
  # classed nothing - `core.invoke` included - which is what kept the
  # host-side translation in `StatifierExamples.Charts.Durable` alive
  # through that release; the paragraph below is where it ends.
  # `statifier_ui`
  # becomes an optional dependency at `~> 0.9` with this release, and
  # is declared directly above at that line;
  # `statifier_datamodel` still arrives TRANSITIVELY, at `~> 0.1`,
  # which the resolved 0.2.0 satisfies - this app names it nowhere,
  # through this dependency or through `statifier_ui`'s new one,
  # because the `types` key its fixtures write is data the compiler
  # reads for it. 0.2.0 narrows the read check rather than widening
  # it: a record field a document declares optional no longer covers a
  # shape field the document marks required. This app's datamodel
  # documents declare no `types` record that leans on the looser
  # reading, so the narrowing reaches nothing here.
  #
  # The default arm is PINNED to `statifier_blocks` MAIN, the way the
  # `statifier_ui` clause below describes its own git leg: 0.22.0 is not
  # published yet and two unreleased commits are load-bearing here. The
  # first is the Run pane's `compile_options` assign (`sb-hgjk`), because
  # the editor page has to hand the pane the same three compile options
  # `StatifierExamples.Charts.Durable.compile/3` passes - `terminate:
  # true`, the known invoke types and the datamodel - or the pane reads
  # its marks off a differently compiled chart than the one the run
  # executed. The pin moves forward to the second (`sb-hxs5`): `core.invoke`
  # now classes its `error` outcome as a failure like `core.map` and
  # `core.subchart` do, and an unhandled failure-classed completion is
  # carried to the document's top-level `<final>`, which is what stamps
  # the reserved `statifier_persistence:run_status` param on the chunk
  # chart's error final. That is what let `se-cqr` delete the host-side
  # translation `StatifierExamples.Charts.Durable` used to do instead.
  # `STATIFIER_BLOCKS_PATH` still wins over the pin, so a local checkout
  # is unaffected; `se-gty` moves the default arm back to
  # `{:statifier_blocks, "~> 0.22"}` once the operator publishes.
  defp statifier_blocks_dep do
    case System.get_env("STATIFIER_BLOCKS_PATH") do
      path when is_binary(path) and path != "" ->
        {:statifier_blocks, path: path}

      _ ->
        {:statifier_blocks,
         github: "riddler/statifier_blocks", ref: "0f9f2cd7d2fb1b840941fafb54949cb958edf975"}
    end
  end

  # The authoring/observing package, and the one dependency whose
  # `assets/js` this app's bundle check exists to look at. Setting
  # `STATIFIER_UI_REF` to a git ref takes it from the statifier-ui
  # repository at that ref instead of from Hex, which is what the CI
  # bundle job's second matrix leg does: the Hex leg bundles the last
  # published release, the git leg bundles that repository's `main`, so
  # a bundler break lands on a statifier-ui merge rather than on its
  # next release. The override is the environment's alone - nothing is
  # pinned here, and `mix.lock` is committed at the Hex resolution - and
  # `override: true` is what lets it win over `statifier_blocks`'
  # optional `~> 0.9` requirement on the same package.
  defp statifier_ui_dep do
    case System.get_env("STATIFIER_UI_REF") do
      ref when is_binary(ref) and ref != "" ->
        {:statifier_ui,
         git: "https://github.com/riddler/statifier-ui.git", ref: ref, override: true}

      _ ->
        {:statifier_ui, "~> 0.9"}
    end
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind statifier_examples", "esbuild statifier_examples"],
      # The JavaScript half of assets.build, self-contained enough for CI to
      # run as one command. It is esbuild only on purpose: what CI is here to
      # catch is a dependency's assets/js that no longer bundles - a syntax
      # error or a bad import in statifier_ui or statifier_blocks - and the
      # Tailwind pass cannot fail for that reason. Skipping it also skips
      # downloading a second standalone binary and building the CSS, which is
      # what keeps this check cheap enough to run on every pull request.
      # `compile` stays: the bundle resolves colocated hooks out of
      # Mix.Project.build_path(), which exists only once the app has compiled.
      "assets.bundle": [
        "esbuild.install --if-missing",
        "compile",
        "esbuild statifier_examples"
      ],
      "assets.deploy": [
        "tailwind statifier_examples --minify",
        "esbuild statifier_examples --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
