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
      {:statifier, "~> 2.4"},

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
      # INTERIM GIT PIN, re-pin to Hex owed (se-6ag, campaign-026). This
      # app now DOES consume ADR-0008's durable subcharts, and the one
      # piece it needs is not in 0.4.0: sp-2yx widened
      # `StatifierPersistence.Driver.dispatch_context/0` to carry
      # `:invoke`, the whole `Statifier.Effect.Invoke` being dispatched.
      # Without it a dispatch fun sees `type` and `params` only, and the
      # subchart handler cannot reach `src` - the document id it resolves
      # the child chart by - so `StatifierBlocks.Runtime.DurableSubchart`
      # raises rather than guess. Everything else the durable subchart
      # needs (the dispatch fun's `{:start_child, _, _}` arm, the
      # `chart_resolver:` option, `parent_link/2`, `answer_parent/3`,
      # `Runs.cascade_cancel/3`, `list_runs_by_metadata/2` on the storage
      # behaviour) is already in 0.4.0. The pin retires the moment the
      # operator publishes the release carrying sp-2yx.
      {:statifier_persistence,
       github: "riddler/statifier_persistence", ref: "1416a7b98ce70efe0511050d23dd9cc8f12d0d3e"},

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
      {:statifier_oban, "~> 0.4"},

      # The authoring layer this app is the reference embedder for.
      # `phoenix_live_view` is optional there and supplied by this app above.
      statifier_blocks_dep(),

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
  # The default arm is an INTERIM GIT PIN, re-pin to Hex owed (se-6ag,
  # campaign-026). `StatifierBlocks.Runtime.DurableSubchart` - the handler
  # that answers `core.subchart` by starting the child as its own persisted
  # `statifier_persistence` run - landed after 0.13.0 and is what this
  # app's durable subchart proof is written against. 0.13.0 carries only
  # the in-memory `StatifierBlocks.Runtime.Subchart`, whose
  # `{:start_child, _, _}` nothing but `Statifier.Session` executes. The
  # pin retires the moment the operator publishes the release carrying
  # sb-2i04.
  #
  # The Hex requirement this arm held before the pin was the 0.13 line.
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
  defp statifier_blocks_dep do
    case System.get_env("STATIFIER_BLOCKS_PATH") do
      path when is_binary(path) and path != "" ->
        {:statifier_blocks, path: path}

      _ ->
        {:statifier_blocks,
         github: "riddler/statifier_blocks", ref: "05f0a4ab0c9a1adb1c8857d0b5642a8b19cc7e98"}
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
