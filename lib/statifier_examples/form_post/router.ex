defmodule StatifierExamples.FormPost.Router do
  @moduledoc """
  The router configuration the card application form's applications are
  routed with: how one stored application reaches one execution of the
  card application document.

  `StatifierExamples.FormPost.IntakeJob` hands each stored application to
  `StatifierRouter.Webhook.handle/3` with this configuration, carrying the
  application's id and nothing else. The configuration says what happens
  next:

    * **One binding**, `card_applications`, takes every event from the
      `card_application_form` source, keys it by the application id and
      hands the execution `application.received`, with the id as the
      event's only data. It creates under the router's default,
      `create: :if_absent`, written out because a host copying it should
      see it: one execution per application. The binding sets no
      `:dedupe`, so it has the router's default, a horizon of 72 hours
      (259_200_000 ms): a repeat of the same message inside the horizon is
      answered by the router's dedupe, which never reaches the execution.
      Past the horizon the router counts the dedupe row as absent, reaped
      or not, and the message is new again: `:if_absent` reads the
      application's address row, which the router keeps while the
      execution is active and until a reap that first sees it finished
      has been followed by a horizon. An execution still active is
      stepped with the event, a second `application.received`; a
      finished one is not stepped, and the router answers the message as
      dropped.
    * **The doors the router drives itself are wrapped** in the library
      system the application was stored under: `:route`, which
      `StatifierRouter.Webhook.handle/3` goes through, and the router's
      other doors. `:around_delivery` is `StatifierExamples.FormPost.Scope`,
      this app's stand-in for a host's tenancy context. The `:target` door,
      a send's delivery to an execution target, is wrapped only on a
      configuration that sets `:wrap_target`, and this one does not.
    * **Every create and step** goes through this app's execution door,
      `StatifierExamples.FormPost.Stepper` (`:on_create` and `:on_step`),
      which runs only inside a library system and adds the serialization
      SQLite needs.
    * **The two routes** the document's sends reach are registered under
      their own names: `StatifierExamples.FormPost.PatronSystemRoute` and
      `StatifierExamples.FormPost.NewsletterRoute`, under the send type
      `myapp:route`.
    * **The three steps' invoke types** go with every create and step as
      the `:invoke_types` persistence option
      (`StatifierExamples.FormPost.Steps.invoke_types/0`), so the
      document's `<invoke>`s reach the executor rather than being refused
      as unsupported.
    * **The executor** hands each effect to
      `StatifierExamples.FormPost.Steps.execute/2` first, which stores
      the steps' jobs and the deadline timers on this app's Oban through
      `statifier_oban`, and then to the router's own handler, which
      answers the typed sends. The deadline timers are `statifier_oban`'s:
      the configuration has no `:timer_queue`, because the document sends
      no delayed typed send, so the router holds no timer of its own.

  A step's answer and a fired deadline come back through
  `StatifierExamples.FormPost.Delivery`, outside any door of the router's;
  that module's moduledoc says how they are stepped.

  The router's tables are the ones the routed recipe migrated
  (`priv/repo/migrations/20260925120001_add_statifier_router.exs`), with
  this app's own `depot_id` column first. A card application's rows leave
  that column empty: it is the parcel route's, and the router never
  writes a host column. The routed recipe's two reapers delete expired
  dedupe and address rows from those same tables, so they cover these
  rows too.

  The configuration is built on the first call and kept in
  `:persistent_term`, as `StatifierExamples.RoutedWorkflow.config/0` keeps
  its own; every later call, the executor's on each effect included, reads
  that same struct back.
  """

  alias StatifierExamples.{FirstWorkflow, Repo}

  alias StatifierExamples.FormPost.{
    NewsletterRoute,
    PatronSystemRoute,
    PublishedCharts,
    Scope,
    Stepper,
    Steps
  }

  alias Statifier.Invoke.Types
  alias StatifierRouter.{Config, SendHandler}

  # The document id, which is also the name the binding, the resolver and
  # a publish check know the document by.
  @document_id "bdoc_card_application"

  @binding_id "card_applications"
  @source "card_application_form"
  @event "application.received"

  # The one `<send>` type the router's handler answers to, the routed
  # recipe's spelling.
  @send_type "myapp:route"

  @config_key {__MODULE__, :config}

  @doc """
  The router configuration card applications are routed with; the
  moduledoc describes it.
  """
  @spec config() :: Config.t()
  def config do
    case :persistent_term.get(@config_key, nil) do
      %Config{} = config ->
        config

      nil ->
        config = build_config()
        :persistent_term.put(@config_key, config)
        config
    end
  end

  @spec build_config() :: Config.t()
  defp build_config do
    case Config.new(
           repo: Repo,
           store: FirstWorkflow.store(),
           executor: &execute/2,
           resolver: PublishedCharts,
           chart_resolver: &PublishedCharts.chart/1,
           on_create: Stepper,
           on_step: Stepper,
           around_delivery: Scope,
           persistence_options: [invoke_types: Types.new(types: Steps.invoke_types())],
           bindings: [application_binding()],
           send_type: @send_type,
           route_adapters: %{
             PatronSystemRoute.route_name() => {PatronSystemRoute, %{}},
             NewsletterRoute.route_name() => {NewsletterRoute, %{}}
           }
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_router is misconfigured: #{inspect(reason)}"
    end
  end

  # The match takes an event that carries an application id; one without
  # is no event of this binding's. The key is the id as a string: the
  # router keys an address by a non-empty string, and the id arrives as
  # the integer the host's table gave it.
  @spec application_binding() :: map()
  defp application_binding do
    %{
      id: @binding_id,
      source: @source,
      match: "event.application_id > 0",
      key: "event.application_id::string",
      document: @document_id,
      event: @event,
      data: ["application_id"],
      create: :if_absent
    }
  end

  @doc """
  The executor every create and step hands its effects to: first
  `StatifierExamples.FormPost.Steps.execute/2`, which stores the steps'
  jobs and the deadline timers on this app's Oban, then the router's own
  handler, which answers a `<send>` of `#{@send_type}` and passes every
  other effect.
  """
  @spec execute(Statifier.Effect.t(), map()) :: :ok | {:error, term()}
  def execute(effect, context) do
    :ok = Steps.execute(effect, context)
    SendHandler.handle_effect(config(), effect, context)
  end

  @doc "The card application document's id."
  @spec document_id() :: String.t()
  def document_id, do: @document_id

  @doc "The one binding's id."
  @spec binding_id() :: String.t()
  def binding_id, do: @binding_id

  @doc "The source the intake job routes each application from."
  @spec source() :: String.t()
  def source, do: @source
end
