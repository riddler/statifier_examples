defmodule StatifierExamples.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias StatifierExamples.Charts.Tracing

  @impl true
  def start(_type, _args) do
    # The OTel bridge, attached before anything can emit. It is
    # `:telemetry.attach/4` and an ETS table, not a process, so it belongs
    # here rather than in the supervision tree - and attaching it after the
    # tree started would lose the spans for whatever the tree did on its
    # way up. `StatifierExamples.Charts.Tracing` says which three halves
    # and why.
    :ok = Tracing.setup()

    children = [
      StatifierExamplesWeb.Telemetry,
      StatifierExamples.Repo,
      {DNSCluster,
       query: Application.get_env(:statifier_examples, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StatifierExamples.PubSub},
      # The engine's own runtime: `Statifier.Registry` and
      # `Statifier.SessionSupervisor` (st-ADR-0027). A session started
      # anywhere in this app registers under that registry, which is how a
      # handler holding only a `session_id` - all the plan context carries -
      # finds the session to report its answer back to. That reporting is
      # `Statifier.Invoke.SyncHandler.Adapter`'s, generated into
      # `StatifierExamples.Charts.SyncAdapter`, which is one of this app's
      # two `Statifier.Invoke.Handler`s: `StatifierExamples.Charts` joins it
      # with `StatifierExamples.Charts.Subchart`, the host half of the
      # canonical `statifier_blocks:subchart` handler. Without the registry
      # the sessions still run and the handlers have no way home.
      Statifier.Supervisor,
      # The per-run exclusion durable runs step inside. It has to be this
      # app's own: `StatifierExamples.Persistence` declines the optional
      # `lock_run/3` that `StatifierPersistence.Runs`' default strategy
      # asks for, so without a strategy the host supplies, every durable
      # step refuses. See `StatifierExamples.Charts.RunLock`.
      StatifierExamples.Charts.RunLock,
      # The host's own Oban instance. `statifier_oban` never starts one
      # (its ADR-0002) and this app is the only thing that could, so the
      # wizard's abandonment reminder has a scheduler to be stored in.
      # It sits after the repo it runs on and before the endpoint, so a
      # fired timer can never reach a run before the store is up.
      {Oban, Application.fetch_env!(:statifier_examples, Oban)},
      # Start a worker by calling: StatifierExamples.Worker.start_link(arg)
      # {StatifierExamples.Worker, arg},
      # Start to serve requests, typically the last entry
      StatifierExamplesWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StatifierExamples.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StatifierExamplesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
