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

      # The engine, held at its Hex release. `statifier_persistence`'s git
      # ref carries a git dependency on `statifier-ex`'s main branch, for a
      # queue-discard fix that release 2.2.0 lacked; 2.2.1 ships it (the fix
      # commit is an ancestor of the v2.2.1 tag), so the override keeps this
      # app on the released engine rather than inheriting a branch pin.
      {:statifier, "~> 2.2", override: true},

      # The durable stepper. INTERIM git pin: Hex 0.1.3 predates both the
      # `:blob_type` option and the run `metadata` column this app configures,
      # so the released package cannot express what is wired up here. Re-pin
      # to a Hex release once one carries them (se-p22).
      {:statifier_persistence,
       git: "https://github.com/riddler/statifier_persistence.git",
       ref: "ca8a7d8921a321491843934386e3ffa4ddf85f65"},

      # Durable timers. `statifier_oban` never owns an Oban instance
      # (its ADR-0002): this app supplies one, on Oban's SQLite engine, so
      # the wizard's abandonment reminder is a stored job rather than a
      # `Process.send_after/3` that dies with the node. Oban itself
      # arrives through this package rather than being named again here.
      #
      # 0.3.1 is REQUIRED, not merely permitted: 0.3.0's cancellation query
      # matches the delivering job itself, so the reminder job cancels its
      # own delivery mid-flight and the live 90s reminder never arrives.
      {:statifier_oban, "~> 0.3.1"},

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
  # The default arm is an INTERIM git pin, for the second time. It was one
  # for the length of campaign 021, on the commit carrying the host marking
  # seam, the drawer host-tab seam and the `invoke_types` assign; 0.9.0
  # shipped all three and the pin came out (se-p22). It is one again for
  # campaign 022: ADR-0001 decision 11 gives a block document a top-level
  # `datamodel` key, and the three fixtures under `priv/fixtures/` now use
  # it to declare the `<data>` roots their own guards and assigns read.
  # Hex 0.9.0 predates the key, and its decoder drops an envelope key it
  # does not recognize in silence - so on the release the fixtures decode,
  # compile without their roots, and raise `error.execution` on the first
  # guard that reads one. Decision 11e closes that hole with an
  # envelope-key allowlist, which is another reason the floor is this
  # commit and not the release. Re-pin to `~> 0.10` once that release
  # exists (se-1xc); the bead stays open until then.
  defp statifier_blocks_dep do
    case System.get_env("STATIFIER_BLOCKS_PATH") do
      path when is_binary(path) and path != "" ->
        {:statifier_blocks, path: path}

      _ ->
        {:statifier_blocks,
         git: "https://github.com/riddler/statifier_blocks.git",
         ref: "4561598f703fbae565be9e38bf540a764930fff2"}
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
