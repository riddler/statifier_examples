import Config

config :upgrade_host, ecto_repos: [UpgradeHost.Repo]

# The host's own Oban instance. statifier_oban never owns or names one: the
# instance name travels in `UpgradeHost.Loans.oban_config/0`.
config :upgrade_host, Oban,
  name: UpgradeHost.Oban,
  repo: UpgradeHost.Repo,
  queues: [loan_timers: 5, loan_invocations: 5]

# opentelemetry_statifier depends on the API only; the SDK is test-only here
# and exports nothing unless a test points it somewhere.
config :opentelemetry, traces_exporter: :none

import_config "#{config_env()}.exs"
