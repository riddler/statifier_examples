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
  hands the location to the one desk the hold request names and writes
  no log line of its own that carries it;
  `StatifierExamplesWeb.BasicHTTPController` says what keeps it out of
  the request log. Whoever can read this app's database holds the
  capability too: the router's location table holds the token; the
  location is part of the execution's persisted state, in
  `_ioprocessors` inside the execution's `position_blob`, in the clear
  (`StatifierExamples.Persistence` stores the blob as `:binary`); and the
  arguments of the `StatifierExamples.HoldDesk.DeskPost` job that carries
  the POST hold it, in a job row this app's Oban pruner deletes seven
  days after the job finishes (`config/config.exs`).

  **The `:debug` limit.** `statifier_router` 0.10.0 runs its own three
  statements that bind the token - the front's lookup, the location
  insert at create and the rotation upsert - with Ecto's `log: false`,
  so the router's query log no longer prints it. The token still reaches
  a `:debug` repo through statements that are not the router's.
  `statifier_persistence` binds the execution's position on the create
  and on every step, and Ecto's query log prints those writes with the
  blob cut short by its inspect limit, which makes the token unreadable
  in the line but not absent from the parameters. And Ecto's query
  telemetry event carries every statement's bound parameters whatever
  the `log` option says, so a handler on it receives the position writes
  and the desk post job's insert, whose own log line Oban suppresses. So
  this app keeps `:debug` out of production, as the router's ADR-0002
  advises in its Note on the location token and the query log, and
  rotates a location that may have leaked.

  `config/0` is a router configuration of its own, separate from
  `StatifierExamples.RoutedWorkflow.config/0`: only this configuration
  sets `:basichttp`, so only the executions it creates get a location.

  ## The outbound half runs in this host's executor

  The router registers `StatifierRouter.BasicHTTP` for both of the
  processor's type strings, which is what lets the chart's `<send>` pass
  the engine's type check and read `_ioprocessors['basichttp']`. A
  durable execution has no session to perform the send, so the effect
  reaches `execute/2`, which plans it with the router's processor. That
  runs inside the delivery's transaction, so the POST it planned is not
  made there: it is handed to a `StatifierExamples.HoldDesk.DeskPost` job,
  inserted in the same transaction and performed after the delivery
  commits, through the configuration's transport. A desk that is slow to
  answer then holds no transaction and no SQLite write lock, and no POST
  leaves for a step that rolled back, as `statifier_router` recommends
  (its ADR-0002, the Amendment on the outbound BasicHTTP send). A POST
  the desk does not answer with a 2xx is retried, and a send that still
  fails comes back into the execution as `error.communication`, delivered
  by the job, and the chart ends the hold unreached. A send with no
  target, which statifier plans as an `error.communication` raise and no
  request, plans no job: it fails at once, and `statifier_persistence`
  enters `error.communication` into the execution in the same step. A
  delayed BasicHTTP send, whose timer would live in this process rather
  than in the database, is refused, and enters the execution the same
  way.
  """

  @behaviour StatifierRouter.Resolver

  alias Statifier.Effect.{Send, SendDelayed}
  alias Statifier.Machine
  alias Statifier.Send.Event, as: SendEvent
  alias StatifierExamples.FirstWorkflow
  alias StatifierExamples.HoldDesk.DeskPost
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
  A hold that names no desk is not routed: the answer is
  `{:ok, [{:no_match, "#{@binding_id}"}]}`, and no execution starts.
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
  `<send>` is planned with `StatifierRouter.BasicHTTP.deliver/3`, and each
  POST it plans is handed to a `StatifierExamples.HoldDesk.DeskPost` job,
  inserted in the delivery's transaction and performed after it commits;
  a send with no target, which statifier plans as an `error.communication`
  raise and no request, fails as `{:basichttp_send_without_target,
  send_id}`, and a delayed one is refused as `{:delayed_basichttp_send,
  send_id}`. Every other effect is passed.
  """
  @spec execute(Statifier.Effect.t(), StatifierPersistence.Executor.context()) ::
          :ok | {:error, term()}
  def execute({:send, %Send{type: type} = send}, %{execution_id: execution_id})
      when type in @basichttp_types do
    ctx = %{session_id: execution_id, opts: basichttp()}
    event = SendEvent.build(send, execution_id)
    {:ok, instructions} = BasicHTTP.deliver(send, event, ctx)
    enqueue(instructions, ctx, send)
  end

  def execute({:send_delayed, %SendDelayed{type: type} = send}, _context)
      when type in @basichttp_types,
      do: {:error, {:delayed_basichttp_send, send.send_id}}

  def execute(_effect, _context), do: :ok

  @spec enqueue([term()], map(), Send.t()) :: :ok | {:error, term()}
  defp enqueue(instructions, ctx, send) do
    Enum.reduce_while(instructions, :ok, fn
      {:handler, _module, payload}, :ok ->
        case payload |> DeskPost.new(ctx, send) |> Oban.insert() do
          {:ok, _job} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      # Statifier plans a send with no target as a raise of
      # error.communication carrying the send id, and no request. There is
      # no internal queue to raise on here, so the send fails instead:
      # statifier_persistence enters a failed send as the same
      # error.communication, from the same send, with the same send id.
      {:raise, :platform, "error.communication", _origin, _opts}, :ok ->
        {:halt, {:error, {:basichttp_send_without_target, send.send_id}}}

      _unknown, :ok ->
        {:halt, {:error, {:basichttp_instruction_unknown, send.send_id}}}
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

  # The chart sends to the desk the request names, so a request that names
  # none (or names it as nil or the empty string) is not a hold this
  # binding routes: the comparison reads `:undefined` or `false`, and the
  # router answers `{:no_match, binding_id}` before any execution starts
  # or any send is planned.
  @spec hold_binding() :: map()
  defp hold_binding do
    %{
      id: @binding_id,
      source: @source,
      match: ~s(event.kind == "hold" and event.desk != ""),
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
