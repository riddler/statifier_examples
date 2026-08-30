import Config

# Each test checks out its own sandbox connection, so the suite shares one
# database file and rolls every test's rows back.
config :statifier_examples, StatifierExamples.Repo,
  database: Path.expand("../priv/repo/statifier_examples_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :statifier_examples, StatifierExamplesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zvEQjPaLe2NJmjkbJ3nhekZUl0EmrLsuWssesOsvVVUHa+B2paa/MMj1kh6Tdg9T",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
