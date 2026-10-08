import Config

# One database per checkout, so two checkouts of statifier_examples (the
# main one and a worktree, say) never run this suite against one database.
# PGDATABASE, when set, wins (CI sets it).
checkout_hash =
  Path.expand("..", __DIR__)
  |> :erlang.phash2(0x100000000)
  |> Integer.to_string(16)
  |> String.downcase()

config :upgrade_host, UpgradeHost.Repo,
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  database:
    System.get_env("PGDATABASE", "upgrade_host_test_#{checkout_hash}") <>
      System.get_env("MIX_TEST_PARTITION", ""),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Nothing runs a job until a test drains a queue.
config :upgrade_host, Oban, testing: :manual

# The simple processor exports on the process that ended the span, so a test
# that points the exporter at itself reads exactly its own spans.
config :opentelemetry, :processors, [{:otel_simple_processor, %{}}]

config :logger, level: :warning
