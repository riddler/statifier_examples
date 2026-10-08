defmodule UpgradeHost.MixProject do
  use Mix.Project

  # A production host's family set, frozen at the versions it adopted.
  #
  # Every family pin is exact (`==`) and comes from Hex: no `path:`, no
  # `git:` and no `override:`, so what this project compiles is exactly
  # what a host on these versions compiles. Walking the host forward is one
  # package at a time, `mix deps.update <package>` after the pin moves, and
  # the lock diff of that step is the record of what moved with it.
  # `test/upgrade_host/lock_test.exs` reads the committed `mix.lock` and
  # fails on any family line that is not the version pinned here.
  def project do
    [
      app: :upgrade_host,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {UpgradeHost.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # The statifier family, at the set the host runs.
      {:statifier, "== 2.12.1"},
      {:statifier_blocks, "== 0.38.0"},
      {:statifier_persistence, "== 0.19.0"},
      {:statifier_oban, "== 0.15.0"},
      {:statifier_router, "== 0.7.0"},
      {:opentelemetry_statifier, "== 0.7.0"},
      {:statifier_ui, "== 0.10.2"},
      {:statifier_datamodel, "== 0.5.1"},
      {:predicator, "== 9.4.3"},
      {:uxid, "== 2.9.2"},

      # The infrastructure the family runs on in such a host.
      {:oban, "== 2.19.4"},
      {:ecto_sql, "== 3.14.0"},
      {:postgrex, "== 0.22.4"},
      {:opentelemetry_api, "== 1.5.0"},

      # The JSON library Postgres's jsonb columns encode through: Oban's
      # args and meta, and an execution's metadata.
      {:jason, "== 1.4.5"},

      # The SDK only in test, where the suite exports spans to itself.
      {:opentelemetry, "== 1.7.0", only: :test}
    ]
  end

  # `mix test` creates and migrates its own database first, so a fresh
  # checkout runs the suite against an empty Postgres server.
  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
