defmodule StatifierExamples.HoldDesk do
  @moduledoc """
  A durable execution with an HTTP location of its own, in the library
  world: a patron's hold on a copy, at one branch's desk, taking its
  events through `statifier_router`'s BasicHTTP front.

  The chart is `priv/library/hold_desk.scxml`. One binding routes a hold
  request into a new execution keyed by the hold id. The execution tells
  the branch desk the hold was placed with a `<send type="basichttp">`,
  handing the desk its own location as `reply_to`, and waits; the desk
  POSTs `copy.shelved` at that location once the copy is on the holds
  shelf, and the execution finishes. The POST reaches
  `StatifierExamplesWeb.BasicHTTPController`, which hands it to
  `StatifierRouter.BasicHTTP.Front`.

  **A location is a bearer capability** (ruled by the operator,
  2026-09-30): anyone who holds it can post events to that execution, and
  the router authenticates nothing beyond possession of it. This module
  hands the location to the desk the hold request names and to nobody
  else, and never logs it; `StatifierExamplesWeb.BasicHTTPController`
  says what keeps it out of the request log.

  `config/0` is a router configuration of its own, separate from
  `StatifierExamples.RoutedWorkflow.config/0`: only this configuration
  sets `:basichttp`, so only the executions it creates get a location.

  ## The outbound half runs in this host's executor

  The router registers `StatifierRouter.BasicHTTP` for both of the
  processor's type strings, which is what lets the chart's `<send>` pass
  the engine's type check and read `_ioprocessors['basichttp']`. A
  durable execution has no session to perform the send, so the effect
  reaches `execute/2`, which plans it with the router's processor and
  performs what it planned, through the configuration's transport. That
  runs inside the delivery's transaction: one POST to the desk, made
  before the step commits. A POST the desk does not answer with a 2xx is
  a failed send, which `statifier_persistence` enters into the execution
  as `error.communication`, and the chart ends the hold unreached. A
  delayed BasicHTTP send, whose timer would live in this process rather
  than in the database, is refused, and enters the execution the same
  way.
  """

  @behaviour StatifierRouter.Resolver

  alias Statifier.Effect.{Send, SendDelayed}
  alias Statifier.Machine
  alias Statifier.Send.Event, as: SendEvent
  alias StatifierExamples.FirstWorkflow
  alias StatifierExamples.RoutedWorkflow.Stepper
  alias StatifierPersistence.Storage
  alias StatifierRouter.{BasicHTTP, Config}

  @chart "library/hold_desk.scxml"

  # The document id the binding and the resolver know the chart by.
  @document_id "hold_desk"

  @binding_id "hold_requests"
  @source "hold_requests"

  # The processor's URI and its short form: the two type strings the
  # router registers `StatifierRouter.BasicHTTP` under.
  @basichttp_types ["http://www.w3.org/TR/scxml/#BasicHTTPEventProcessor", "basichttp"]

  # The path the controller answers at, under the endpoint's URL.
  @front_path "/basichttp"

  @doc """
  The router configuration hold requests are routed with.

  One binding, `#{@binding_id}`, routes every hold request from the
  `#{@source}` source to the execution of `#{@document_id}` keyed by its
  `hold_id`. `:basichttp` names the base URL the controller answers at
  (`base_url/0`) and the transport outbound POSTs go through
  (`:transport` under this module's application environment, statifier's
  default when unset). Creates and steps go through
  `StatifierExamples.RoutedWorkflow.Stepper`, for this app's SQLite
  serialization.
  """
  @spec config() :: Config.t()
  def config do
    case Config.new(
           repo: StatifierExamples.Repo,
           store: FirstWorkflow.store(),
           executor: &execute/2,
           resolver: __MODULE__,
           chart_resolver: &chart/1,
           on_create: Stepper,
           on_step: Stepper,
           bindings: [hold_binding()],
           basichttp: basichttp()
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "the hold desk's router configuration: #{inspect(reason)}"
    end
  end

  @doc "The base URL every location starts with: the endpoint's URL and `#{@front_path}`."
  @spec base_url() :: String.t()
  def base_url, do: StatifierExamplesWeb.Endpoint.url() <> @front_path

  @doc "The document id the binding and the resolver share."
  @spec document_id() :: String.t()
  def document_id, do: @document_id

  @doc """
  Compiles the chart and stores it under its content hash, so the
  resolver answers it for `#{@document_id}`. Answers the content hash.
  """
  @spec register() :: {:ok, String.t()} | {:error, term()}
  def register do
    with {:ok, machine, scxml} <- compile(),
         :ok <- Storage.save_chart(FirstWorkflow.store(), machine, scxml) do
      {:ok, Machine.identity(machine).content_hash}
    end
  end

  @doc """
  Routes one hold request: `hold` carries `"hold_id"`, `"copy_id"` and
  `"desk"`, the URL of the branch desk the execution tells, in `scope`.
  """
  @spec request(String.t(), map()) :: {:ok, [StatifierRouter.outcome()]} | {:error, term()}
  def request(scope, %{"hold_id" => hold_id} = hold) do
    StatifierRouter.route(config(), %{
      scope: scope,
      source: @source,
      message_id: "hold-requested/" <> hold_id,
      data: Map.put(hold, "kind", "hold")
    })
  end

  # ------------------------------------------------------- the resolver

  @impl StatifierRouter.Resolver
  @spec resolve(String.t(), String.t()) :: StatifierRouter.Resolver.result()
  def resolve(_scope, @document_id) do
    with {:ok, machine, _scxml} <- compile(),
         content_hash = Machine.identity(machine).content_hash,
         {:ok, _chart} <- Storage.fetch_chart(FirstWorkflow.store(), content_hash) do
      {content_hash, machine}
    else
      _unregistered -> {:error, :not_published}
    end
  end

  def resolve(_scope, _document), do: {:error, :not_published}

  @doc "The chart registered under `content_hash`, compiled, or `:error`."
  @spec chart(String.t()) :: {:ok, Machine.t()} | :error
  def chart(content_hash) do
    with {:ok, chart} <- Storage.fetch_chart(FirstWorkflow.store(), content_hash),
         {:ok, machine} <- Statifier.compile(chart.chart_blob) do
      {:ok, machine}
    else
      _missing -> :error
    end
  end

  # ------------------------------------------------------- the executor

  @doc """
  The executor every create and step hands its effects to. A BasicHTTP
  `<send>` is planned with `StatifierRouter.BasicHTTP.deliver/3` and each
  instruction it plans is performed with the processor's `perform/2`; a
  delayed one is refused as `{:delayed_basichttp_send, send_id}`. Every
  other effect is passed.
  """
  @spec execute(Statifier.Effect.t(), StatifierPersistence.Executor.context()) ::
          :ok | {:error, term()}
  def execute({:send, %Send{type: type} = send}, %{execution_id: execution_id})
      when type in @basichttp_types do
    ctx = %{session_id: execution_id, opts: basichttp()}
    event = SendEvent.build(send, execution_id)
    {:ok, instructions} = BasicHTTP.deliver(send, event, ctx)
    perform(instructions, ctx, send)
  end

  def execute({:send_delayed, %SendDelayed{type: type} = send}, _context)
      when type in @basichttp_types,
      do: {:error, {:delayed_basichttp_send, send.send_id}}

  def execute(_effect, _context), do: :ok

  @spec perform([term()], map(), Send.t()) :: :ok | {:error, term()}
  defp perform(instructions, ctx, send) do
    Enum.reduce_while(instructions, :ok, fn
      {:handler, module, payload}, :ok ->
        case module.perform(payload, ctx) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end

      _unperformed, :ok ->
        {:halt, {:error, {:basichttp_send_not_planned, send.send_id}}}
    end)
  end

  # ---------------------------------------------------------- the parts

  @spec basichttp() :: keyword()
  defp basichttp do
    case Keyword.fetch(Application.get_env(:statifier_examples, __MODULE__, []), :transport) do
      {:ok, transport} -> [base_url: base_url(), transport: transport]
      :error -> [base_url: base_url()]
    end
  end

  @spec hold_binding() :: map()
  defp hold_binding do
    %{
      id: @binding_id,
      source: @source,
      match: ~s(event.kind == "hold"),
      key: "event.hold_id",
      document: @document_id,
      event: "hold.requested",
      data: ["hold_id", "copy_id", "desk"]
    }
  end

  @spec compile() :: {:ok, Machine.t(), String.t()} | {:error, term()}
  defp compile do
    scxml = :statifier_examples |> :code.priv_dir() |> Path.join(@chart) |> File.read!()

    with {:ok, machine} <- Statifier.compile(scxml), do: {:ok, machine, scxml}
  end
end
