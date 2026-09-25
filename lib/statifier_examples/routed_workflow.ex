defmodule StatifierExamples.RoutedWorkflow do
  @moduledoc """
  The recipe `docs/guides/first-workflow-routed.md` walks, as code: one
  durable workflow whose every event arrives through `statifier_router`,
  on this app's own database and Oban instance.

  The document is `priv/first_workflow/parcel_route.json`, a parcel's way
  from a depot to a doorstep in two scans: the depot scans it out, then
  the courier scans it at the door. One binding routes every scan of a
  parcel to that parcel's execution, keyed by the parcel id. `run/1` takes
  it through ten steps and checks each one before the next:

    1. `:migrated` - the router's four tables exist, and this app's own
       `depot_id` column sits at position 2 on every one of them
       (`priv/repo/migrations/20260925120001_add_statifier_router.exs`).
    2. `:published` - `StatifierExamples.Publish.check/2` passes the
       document against the router configuration `config/0` builds, so
       `StatifierRouter.Contracts.check/3` judges the binding's event
       against what the document accepts.
    3. `:guarded` - the same check refuses at its `:contracts` stage when
       the binding names an event the document does not accept.
    4. `:registered` - the runtime compile, stored under its content hash,
       and the resolver (`StatifierExamples.RoutedWorkflow.PublishedCharts`)
       answering that hash for the document and refusing any other.
    5. `:created` - the depot scan, routed with `StatifierRouter.route/3`:
       the address is empty, so the delivery creates the execution and
       steps the scan into it.
    6. `:duplicate` - the same message routed again is recognized by its
       message id and touches nothing.
    7. `:completed` - the doorstep scan reaches the same execution through
       its address and finishes it, and the route `:on_complete` names
       (`StatifierExamples.RoutedWorkflow.DoorstepRoute`) queues one
       doorstep notice inside that same delivery.
    8. `:finished` - a late scan for a finished parcel is dropped as
       `:finished`, and the routing ledger holds one row per attempt, none
       of which writes `depot_id`.
    9. `:reaped` - once the binding's dedupe horizon has passed, the two
       reapers (`StatifierExamples.RoutedWorkflow.DedupeReaper` and
       `StatifierExamples.RoutedWorkflow.AddressReaper`), run as jobs on
       this app's Oban and scheduled by its cron entries, remove the
       parcel's dedupe rows and its address row.
    10. `:traced` - the execution's input log holds the two scans that
        stepped it, and the finished execution carries its `ended_at`.

  Every delivery steps the execution through
  `StatifierExamples.RoutedWorkflow.Stepper`, the configuration's
  `:on_create` and `:on_step`: this app's SQLite adapter offers no
  per-execution lock, so the router's direct calls to
  `StatifierPersistence.Executions` would refuse, and the stepper hands
  them this app's serialization strategy instead.

  `run/1` answers `{:ok, lines}`, the lines the mix task prints, or
  `{:error, step, reason}` naming the first step that did not hold.
  """

  import Ecto.Query, only: [from: 2]

  alias Statifier.Machine
  alias StatifierBlocks.{Compiled, Compiler, Decode, Document}
  alias StatifierExamples.{Charts, FirstWorkflow, Publish, Repo}

  alias StatifierExamples.RoutedWorkflow.{
    AddressReaper,
    DedupeReaper,
    DoorstepNotice,
    DoorstepRoute,
    PublishedCharts,
    Stepper
  }

  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.{Config, SendHandler}
  alias StatifierRouter.Schema.{Address, Dedupe, Ledger}

  @document "first_workflow/parcel_route.json"

  # The document id, which is also the name the binding, the resolver and
  # the contracts lookup know the document by.
  @document_id "bdoc_parcel_route"

  @binding_id "parcel_scans"
  @source "parcel_scans"
  @event "parcel.scanned"

  # The one `<send>` type the router's handler answers to, and the one
  # route this host registers.
  @send_type "myapp:route"
  @route "doorstep_notices"

  # The scope every scan is routed under: one depot. Opaque to the router.
  @scope "depot_eastside"

  # How long a message id is remembered, and how long a finished parcel's
  # address row outlives it. One second so the command finishes quickly;
  # a real host would keep days.
  @horizon_ms 1_000

  # How long the recipe polls for a job's work before it names the step
  # that never finished.
  @deadline_ms 15_000
  @poll_ms 50

  @notices_queue :parcel_notices
  @maintenance_queue :router_maintenance

  # The host column the migration places after `id` on every router table.
  @leading_column "depot_id"
  @tables [:addresses, :dedupe, :routing_ledger, :subscriptions]

  @typedoc "The step `run/1` names when it stops; see the moduledoc."
  @type step ::
          :decoded
          | :migrated
          | :published
          | :guarded
          | :registered
          | :created
          | :duplicate
          | :completed
          | :finished
          | :reaped
          | :traced
          | :unexpected

  @doc """
  Runs the recipe once, for a fresh parcel, and answers the lines the mix
  task prints or the first step that did not hold.

  `opts` takes `:parcel_id` (default a fresh fictional id) for a caller
  that wants to name the parcel. The parcel id is the binding's key, so a
  second run for the same parcel id inside the horizon finds its address.
  """
  @spec run(keyword()) :: {:ok, [String.t()]} | {:error, step(), term()}
  def run(opts \\ []) do
    parcel_id = Keyword.get_lazy(opts, :parcel_id, &new_parcel_id/0)
    config = config()

    with {:ok, document} <- step(:decoded, decode()),
         :ok <- step(:migrated, migrated()),
         {:ok, _compiled, accepts, warnings} <- step(:published, publish(document, config)),
         :ok <- step(:guarded, guarded(document)),
         {:ok, content_hash} <- step(:registered, register(document)),
         {:ok, execution_id} <- step(:created, created(config, parcel_id)),
         :ok <- step(:duplicate, duplicate(config, parcel_id, execution_id)),
         {:ok, notices} <- step(:completed, completed(config, parcel_id, execution_id)),
         {:ok, outcomes} <- step(:finished, finished(config, parcel_id, execution_id)),
         {:ok, reaped} <- step(:reaped, reaped(config, parcel_id)),
         {:ok, ended, inputs} <- step(:traced, traced(execution_id)) do
      {:ok,
       [
         "first workflow routed on " <> pins(),
         "migrated     #{length(@tables)} router tables, #{@leading_column} at position 2 on each",
         "published    #{@document_id} accepts #{Enum.join(accepts, ", ")}; " <>
           "every publish-time check passed, #{length(warnings)} warning(s)",
         "guarded      a binding naming an event #{@document_id} does not accept " <>
           "is refused at the contracts stage",
         "registered   chart #{content_hash}, the resolver's answer for #{@document_id}",
         "created      parcel #{parcel_id}: execution #{execution_id}, created and delivered",
         "duplicate    the depot scan routed again: duplicate, no execution read or stepped",
         "completed    the doorstep scan delivered to #{execution_id}: " <>
           "completed, #{notices} doorstep notice sent",
         "finished     a late scan dropped: finished; the ledger reads " <>
           Enum.join(outcomes, ", "),
         "reaped       past the #{@horizon_ms} ms horizon: " <>
           "#{reaped.dedupe} dedupe row(s) and #{reaped.addresses} address row(s) removed",
         "ended        #{ended.status} at #{DateTime.to_iso8601(ended.ended_at)}",
         "trace        the input log, oldest first:"
       ] ++ Enum.map(inputs, &trace_line/1)}
    else
      {:error, _step, _reason} = error -> error
      other -> {:error, :unexpected, other}
    end
  end

  @doc """
  The router configuration the recipe routes with.

  One binding, `parcel_scans`, routes every scan from the `parcel_scans`
  source to the execution of `#{@document_id}` keyed by the scan's
  `parcel_id`, and remembers each message id for the horizon. The
  resolver and the chart resolver are
  `StatifierExamples.RoutedWorkflow.PublishedCharts`; `:on_create` and
  `:on_step` are `StatifierExamples.RoutedWorkflow.Stepper`; the one route
  is `#{@route}`, served by `StatifierExamples.RoutedWorkflow.DoorstepRoute`
  and named by `:on_complete`, so a delivery that finishes an execution
  hands its donedata there.
  """
  @spec config() :: Config.t()
  def config do
    case Config.new(
           repo: Repo,
           store: FirstWorkflow.store(),
           executor: &execute/2,
           resolver: PublishedCharts,
           chart_resolver: &PublishedCharts.chart/1,
           on_create: Stepper,
           on_step: Stepper,
           bindings: [scan_binding(@event)],
           send_type: @send_type,
           route_adapters: %{@route => {DoorstepRoute, %{queue: @notices_queue}}},
           on_complete: @route
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_router is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  The executor every create and step hands its effects to: the router's
  own handler, which answers a `<send>` of `#{@send_type}` and passes
  every other effect.
  """
  @spec execute(Statifier.Effect.t(), map()) :: :ok | {:error, term()}
  def execute(effect, context), do: SendHandler.handle_effect(config(), effect, context)

  @doc """
  The chart an execution of `#{@document_id}` runs: the document compiled
  for running, with `terminate: true` so a parcel scanned at the doorstep
  completes.
  """
  @spec runtime_chart() :: {:ok, Machine.t(), String.t()} | {:error, term()}
  def runtime_chart do
    with {:ok, document} <- decode(),
         {:ok, %Compiled{scxml: scxml}} <-
           Compiler.compile(document, Charts.palette(), terminate: true),
         {:ok, machine} <- Statifier.compile(scxml) do
      {:ok, machine, scxml}
    end
  end

  @doc "The document id the binding, the resolver and the lookup share."
  @spec document_id() :: String.t()
  def document_id, do: @document_id

  # ------------------------------------------------------------ the steps

  @spec step(step(), term()) :: term()
  defp step(_step, :ok), do: :ok
  defp step(_step, {:ok, _} = ok), do: ok
  defp step(_step, {:ok, _, _} = ok), do: ok
  defp step(_step, {:ok, _, _, _} = ok), do: ok
  defp step(step, {:refused, refusal}), do: {:error, step, refusal}
  defp step(step, {:error, reason}), do: {:error, step, reason}

  @spec decode() :: {:ok, Document.t()} | {:error, term()}
  defp decode do
    :statifier_examples
    |> :code.priv_dir()
    |> Path.join(@document)
    |> File.read!()
    |> Decode.decode()
  end

  # SQLite numbers a table's columns from 0 in `PRAGMA table_info`, so
  # ordinal position 2 is `cid` 1.
  @spec migrated() :: :ok | {:error, term()}
  defp migrated do
    config = config()

    misplaced =
      for table <- @tables,
          name = Config.table(config, table),
          %{rows: rows} = Repo.query!("PRAGMA table_info(#{name})"),
          not match?([_id, [1, @leading_column | _] | _], rows),
          do: name

    if misplaced == [], do: :ok, else: {:error, {:leading_column_misplaced, misplaced}}
  end

  # The host state the publish step judges against. The router's own send
  # type is the one send type this host registers, and the contracts
  # lookup answers the document's own `accepts` list, which is what
  # `Contracts.check/3` judges the binding's event against.
  @spec publish(Document.t(), Config.t()) :: Publish.result()
  defp publish(document, config) do
    Publish.check(document, %{
      palette: Charts.palette(),
      datamodel: nil,
      send_types: %{@send_type => SendHandler},
      router_config: config,
      accepts_lookup: accepts_lookup(document),
      document_resolver: fn _document -> {:error, :not_published} end
    })
  end

  # A binding that names an event the document does not accept is a
  # contract the publish gate has to refuse, before any event is routed.
  @spec guarded(Document.t()) :: :ok | {:error, term()}
  defp guarded(document) do
    config = %{config() | bindings: [built_binding("parcel.lost")]}

    case publish(document, config) do
      {:refused, %{stage: :contracts, findings: [%{anchor: {:binding, @binding_id}} | _]}} ->
        :ok

      other ->
        {:error, {:not_refused, other}}
    end
  end

  @spec accepts_lookup(Document.t()) :: StatifierRouter.Contracts.lookup()
  defp accepts_lookup(%Document{id: id, accepts: accepts}) do
    fn
      ^id -> {:ok, accepts}
      _other -> {:error, :not_published}
    end
  end

  # The runtime compile, stored under its content hash, and the resolver
  # asked for the document the binding names.
  @spec register(Document.t()) :: {:ok, String.t()} | {:error, term()}
  defp register(_document) do
    with {:ok, machine, scxml} <- runtime_chart(),
         :ok <- Storage.save_chart(FirstWorkflow.store(), machine, scxml),
         content_hash = Machine.identity(machine).content_hash,
         {^content_hash, %Machine{}} <- PublishedCharts.resolve(@scope, @document_id),
         {:error, :not_published} <- PublishedCharts.resolve(@scope, "bdoc_unpublished") do
      {:ok, content_hash}
    else
      {:error, _reason} = error -> error
      other -> {:error, {:resolver, other}}
    end
  end

  @spec created(Config.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp created(config, parcel_id) do
    with {:ok, [{:created_and_delivered, @binding_id, execution_id}]} <-
           route(config, parcel_id, "depot"),
         {:ok, %Execution{status: :active}} <- fetch(execution_id) do
      {:ok, execution_id}
    else
      other -> {:error, other}
    end
  end

  # The claim finds the message id already handled: the ledger records the
  # duplicate, and the execution is neither read nor stepped, so its input
  # log still holds the one scan.
  @spec duplicate(Config.t(), String.t(), String.t()) :: :ok | {:error, term()}
  defp duplicate(config, parcel_id, execution_id) do
    with {:ok, [{:duplicate, @binding_id}]} <- route(config, parcel_id, "depot"),
         {:ok, [_one_scan]} <- Executions.inputs(FirstWorkflow.store(), execution_id) do
      :ok
    else
      other -> {:error, other}
    end
  end

  # The doorstep scan finishes the execution, and the `:on_complete` route
  # queues the notice inside the same delivery. Draining the notices queue
  # runs it.
  @spec completed(Config.t(), String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp completed(config, parcel_id, execution_id) do
    with {:ok, [{:delivered, @binding_id, ^execution_id}]} <-
           route(config, parcel_id, "doorstep"),
         {:ok, %Execution{status: :completed}} <- fetch(execution_id),
         [_notice] <- notices(execution_id),
         :ok <- await(fn -> Enum.map(notices(execution_id), & &1.state) == ["completed"] end) do
      {:ok, 1}
    else
      other -> {:error, other}
    end
  end

  # A late scan reaches a finished execution: dropped, with the address
  # row stamped as seen finished. The ledger holds one row per attempt,
  # and the host column is left to its default on every one of them.
  @spec finished(Config.t(), String.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp finished(config, parcel_id, execution_id) do
    with {:ok, [{:dropped, @binding_id, :finished}]} <- route(config, parcel_id, "late"),
         %Address{execution_id: ^execution_id, terminal_seen_at: %DateTime{}} <-
           address(config, parcel_id),
         [_, _, _, _] = rows <- ledger(config, parcel_id),
         [] <- written_depot_ids(config, parcel_id) do
      {:ok, Enum.map(rows, & &1.outcome)}
    else
      other -> {:error, other}
    end
  end

  # Waits out the horizon, then runs both reapers as jobs on this app's
  # Oban, the way its cron entries schedule them.
  @spec reaped(Config.t(), String.t()) :: {:ok, map()} | {:error, term()}
  defp reaped(config, parcel_id) do
    dedupe_before = length(dedupe(config, parcel_id))

    with :ok <- scheduled(),
         :ok <- Process.sleep(@horizon_ms + 100),
         {:ok, _} <- Oban.insert(DedupeReaper.new(%{})),
         {:ok, _} <- Oban.insert(AddressReaper.new(%{})),
         :ok <-
           await(fn -> dedupe(config, parcel_id) == [] and address(config, parcel_id) == nil end) do
      {:ok, %{dedupe: dedupe_before, addresses: 1}}
    else
      other -> {:error, other}
    end
  end

  # Both reapers are on this app's cron.
  @spec scheduled() :: :ok | {:error, term()}
  defp scheduled do
    crontab =
      :statifier_examples
      |> Application.fetch_env!(Oban)
      |> Keyword.get(:plugins, [])
      |> Enum.find_value([], fn
        {Oban.Plugins.Cron, opts} -> Keyword.get(opts, :crontab, [])
        _plugin -> nil
      end)

    workers = Enum.map(crontab, &elem(&1, 1))

    if DedupeReaper in workers and AddressReaper in workers,
      do: :ok,
      else: {:error, {:reapers_not_scheduled, crontab}}
  end

  @spec traced(String.t()) :: {:ok, Execution.t(), [Storage.input()]} | {:error, term()}
  defp traced(execution_id) do
    with {:ok, %Execution{status: :completed} = execution} <- fetch(execution_id),
         true <- Executions.ended?(execution),
         {:ok, [_, _] = inputs} <- Executions.inputs(FirstWorkflow.store(), execution_id) do
      {:ok, execution, inputs}
    else
      other -> {:error, other}
    end
  end

  # ---------------------------------------------------- the router calls

  # One scan of `parcel_id` at `at`. The message id is the scan's own, so
  # routing the same scan twice is the same message.
  @spec route(Config.t(), String.t(), String.t()) ::
          {:ok, [StatifierRouter.outcome()]} | {:error, term()}
  defp route(config, parcel_id, at) do
    StatifierRouter.route(config, %{
      scope: @scope,
      source: @source,
      message_id: message_id(parcel_id, at),
      data: %{"kind" => "scan", "parcel_id" => parcel_id, "at" => at}
    })
  end

  @spec scan_binding(String.t()) :: map()
  defp scan_binding(event) do
    %{
      id: @binding_id,
      source: @source,
      match: ~s(event.kind == "scan"),
      key: "event.parcel_id",
      document: @document_id,
      event: event,
      data: ["parcel_id", "at"],
      dedupe: %{by: :message_id, horizon_ms: @horizon_ms}
    }
  end

  @spec built_binding(String.t()) :: StatifierRouter.Binding.t()
  defp built_binding(event) do
    {:ok, binding} = StatifierRouter.Binding.new(scan_binding(event))
    binding
  end

  # ------------------------------------------------------- the reads

  @spec fetch(String.t()) :: {:ok, Execution.t()} | {:error, term()}
  defp fetch(execution_id) do
    with {:ok, record} <- Storage.fetch_execution(FirstWorkflow.store(), execution_id) do
      {:ok, Execution.from_record(record)}
    end
  end

  @spec address(Config.t(), String.t()) :: Address.t() | nil
  defp address(config, parcel_id) do
    Repo.one(
      from(a in Config.queryable(config, Address),
        where: a.scope == ^@scope and a.document == ^@document_id and a.key == ^parcel_id
      )
    )
  end

  @spec dedupe(Config.t(), String.t()) :: [Dedupe.t()]
  defp dedupe(config, parcel_id) do
    Repo.all(
      from(d in Config.queryable(config, Dedupe),
        where: d.binding_id == ^@binding_id and d.message_id in ^message_ids(parcel_id)
      )
    )
  end

  @spec ledger(Config.t(), String.t()) :: [Ledger.t()]
  defp ledger(config, parcel_id) do
    Repo.all(
      from(l in Config.queryable(config, Ledger),
        where: l.binding_id == ^@binding_id and l.key == ^parcel_id,
        order_by: l.id
      )
    )
  end

  # The ledger rows of this parcel that carry a `depot_id`. The package's
  # schemas do not declare the column, so this reads it with SQL.
  @spec written_depot_ids(Config.t(), String.t()) :: [term()]
  defp written_depot_ids(config, parcel_id) do
    %{rows: rows} =
      Repo.query!(
        "SELECT #{@leading_column} FROM #{Config.table(config, :routing_ledger)} " <>
          "WHERE key = ?1 AND #{@leading_column} IS NOT NULL",
        [parcel_id]
      )

    rows
  end

  @spec notices(String.t()) :: [Oban.Job.t()]
  defp notices(execution_id) do
    worker = inspect(DoorstepNotice)

    Repo.all(
      from(j in Oban.Job,
        where: j.worker == ^worker,
        where: fragment("json_extract(?, '$.execution_id')", j.args) == ^execution_id
      )
    )
  end

  # Polls `done?` until it holds or the deadline passes, running every job
  # already due in the recipe's two queues on each pass. In the dev app the
  # queues also run on their own, so the check is on what the jobs did,
  # never on who ran them.
  @spec await((-> boolean())) :: :ok | {:error, :timed_out}
  defp await(done?), do: await(done?, System.monotonic_time(:millisecond) + @deadline_ms)

  defp await(done?, deadline) do
    for queue <- [@notices_queue, @maintenance_queue] do
      Oban.drain_queue(queue: queue, with_scheduled: DateTime.utc_now())
    end

    cond do
      done?.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timed_out}

      true ->
        Process.sleep(@poll_ms)
        await(done?, deadline)
    end
  end

  # ----------------------------------------------------------- the output

  @spec trace_line(Storage.input()) :: String.t()
  defp trace_line(%{seq: seq, door: door, event: nil}),
    do: "  #{seq} #{door} (the log was closed here)"

  defp trace_line(%{seq: seq, door: door, event: event}),
    do: "  #{seq} #{door} #{event.name} at #{event.data["at"]}"

  @spec pins() :: String.t()
  defp pins do
    ~w(statifier_router statifier_persistence statifier_blocks statifier)a
    |> Enum.map_join(", ", fn app -> "#{app} #{Application.spec(app, :vsn)}" end)
  end

  @spec message_id(String.t(), String.t()) :: String.t()
  defp message_id(parcel_id, at), do: "#{parcel_id}-#{at}"

  @spec message_ids(String.t()) :: [String.t()]
  defp message_ids(parcel_id), do: Enum.map(~w(depot doorstep late), &message_id(parcel_id, &1))

  @spec new_parcel_id() :: String.t()
  defp new_parcel_id,
    do: "parcel-" <> (4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))
end
