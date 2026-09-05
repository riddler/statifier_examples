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
      {:statifier_persistence, "~> 0.6"},

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
      {:statifier_oban, "~> 0.6"},

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
      {:statifier_ui, "~> 0.6"},

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
  defp statifier_blocks_dep do
    case System.get_env("STATIFIER_BLOCKS_PATH") do
      path when is_binary(path) and path != "" ->
        {:statifier_blocks, path: path}

      _ ->
        {:statifier_blocks, "~> 0.18"}
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
      "assets.deploy": [
        "tailwind statifier_examples --minify",
        "esbuild statifier_examples --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
