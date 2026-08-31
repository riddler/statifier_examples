# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :statifier_examples,
  ecto_repos: [StatifierExamples.Repo],
  generators: [timestamp_type: :utc_datetime]

# The repo is SQLite so that `mix setup` starts no service: the database is
# a file, created on demand, and a fresh clone runs the suite and the dev
# app with nothing installed alongside. Each environment names its own file
# in its own config; there is no shared default to accidentally share.
config :statifier_examples, StatifierExamples.Repo,
  pool_size: 5,
  # SQLite serializes writers at the database, so a busy write waits rather
  # than failing outright.
  busy_timeout: 5_000

# Durable timers, on the same SQLite file everything else lives in.
#
# `statifier_oban` never owns an Oban instance (its ADR-0002), so this is
# the host's own: `Oban.Engines.Lite` is the SQLite engine, and the
# notifier has to be named with it because the default one is Postgres'
# `LISTEN/NOTIFY`, which SQLite has no equivalent of. One queue, named
# here rather than defaulted, because the package refuses a queue it was
# not given.
config :statifier_examples, Oban,
  repo: StatifierExamples.Repo,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  queues: [statifier_timers: 5]

# How long an unverified signup waits before the wizard nudges it.
#
# Host configuration rather than a fact about the chart, and that is the
# point: a real product waits a day or two, and a demo cannot. The
# fixture ships the production framing (`2d`) and this value is what a
# running app arms - see `StatifierExamples.Signup`, which applies it to
# the reminder block when the document is loaded. Any duration
# `StatifierBlocks.Core.Duration` accepts.
config :statifier_examples, :signup_reminder_delay, "90s"

# Configure the endpoint
config :statifier_examples, StatifierExamplesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: StatifierExamplesWeb.ErrorHTML, json: StatifierExamplesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: StatifierExamples.PubSub,
  live_view: [signing_salt: "Sn4xKi9p"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  statifier_examples: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  statifier_examples: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
