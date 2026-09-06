defmodule StatifierExamples.Charts.FanOut do
  @moduledoc """
  This app's half of a Tier A fan-out: the job that starts one, the seam
  that creates each child, and the door that cancels the ones that never
  started (se-j87).

  A `core.map` block is one `<invoke>` that becomes N child runs, one per
  item, whose answers are assembled into one dense list. Three packages
  meet here and none of them is a host: `statifier_blocks` names the
  invoke type and nothing else, `statifier_oban` schedules and does not
  create runs, and `statifier_persistence` creates and settles runs and
  does not schedule. What is left over is this module.

  ## The shape is `StatifierExamples.Charts.AsyncCalls`', one layer up

  `fan_out?/1` is read on the executor's way in and on the dispatch fun's
  way out, one predicate for both decisions for that module's reason: a
  job stored for an invocation that was then answered inline would run
  against a call nobody is waiting for, and a `:pending` nobody enqueued
  would rest forever. The parent's own step therefore creates no children
  at all - it stores one fan-out job and rests durably with the
  invocation live, which is what makes N children an ordinary
  asynchronous invocation from the parent's point of view.

  ## `items` is a path, and this is what evaluates it

  `core.map` carries its four config values into the invocation as
  **quoted literals** (sb ADR-0009 decision 3), so the effect's params
  hold `items` as the datamodel PATH the author typed - `"chunks"` - and
  not the list. The list is deliberately not resolved by the parent: a
  compile never sees N, and a `<param>` evaluated at dispatch would put
  the whole list on the wire.

  So the handler evaluates it, and by then there is no session and no
  live datamodel - only the effect and the run id the job was scoped to.
  `run/2` reads the parent run's own persisted position through
  `StatifierExamples.Charts.Durable.machine_state/1` and walks the dotted
  path over it. `start_child/5` does the same, because the start jobs
  carry the fan-out's original effect and not the evaluated list: N reads
  of one run's position, on a database that is a file, for a batch of
  ten. A deployment where that mattered would put the snapshot on the job
  args, which is a packaging change and not a design one.

  A path naming nothing at all is a refusal rather than an empty fan-out.
  `statifier_oban` refuses the empty list too, and for the harder reason:
  a fan-out of zero children has no child whose settlement could answer
  the invocation. The record question is `statifier_blocks`' (sb-kha0)
  and nothing here decides it.

  ## The two cancel doors

  `first_error` cancels the rest as soon as one child fails, and the two
  halves live in two packages because they can. A child that exists is a
  run, cancelled by `StatifierPersistence.Runs.cascade_cancel/3` inside
  the settlement section. An index whose start job has not run yet has no
  run record at all, so it is invisible there - and
  `StatifierOban.Invoke.FanOut.cancel_unstarted/3` is the other door,
  reached through the driver's `child_canceller:` seam.

  `canceller/0`'s wrapper takes the driver's three arguments and uses two
  of them: the package's cancel matches `{scope, invoke_id}` across every
  index and every generation, so the list of unstarted indices is
  information the driver has and this door does not need. Dropping it is
  a fact worth stating rather than a value quietly ignored.

  ## The queue

  `config/0` reuses `StatifierExamples.Charts.AsyncCalls`' queue, because
  `config/config.exs` defines exactly one invoke queue and says why there
  are two queues and not three. Giving a fan-out its own queue - so a
  batch of ten thousand chunk starts cannot delay an ordinary
  asynchronous call behind it - is a deployment change a real host would
  make, and this app is not that host.

  The cap is left at the package default. It is runtime-only by campaign
  ruling: `core.map` validates nothing about N because a compile of one
  document never sees N, and a fan-out wider than the cap is refused on
  the invocation's ordinary error route with the count and the cap in
  `detail`, before a single child starts.
  """

  @behaviour StatifierOban.Invoke.ChildStarter

  use StatifierOban.Invoke.Handler

  require Logger

  alias Statifier.Effect.{CancelInvoke, Invoke}
  alias Statifier.Invoke.Types
  alias StatifierBlocks.Core.Map, as: MapBlock
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Timers}
  alias StatifierOban.Config
  alias StatifierOban.Invoke.FanOut, as: Scheduling
  alias StatifierOban.Invoke.Handler

  @doc """
  Whether `type` is the invoke type a `core.map` block emits.

  The constant is read off `StatifierBlocks.Core.Map` rather than spelled
  here, for the reason that type's own moduledoc gives: there is one
  definition site, and a host that spelled it a second time would be
  registering a name rather than serving one. It is deliberately a
  different string from a subchart's, so this app's single-child handler
  is not taken for a fan-out handler.
  """
  @spec fan_out?(String.t() | nil) :: boolean()
  def fan_out?(type), do: type == MapBlock.invoke_type()

  @doc "The invoke type this module serves."
  @spec invoke_type() :: String.t()
  def invoke_type, do: MapBlock.invoke_type()

  @doc """
  The `statifier_oban` configuration a fan-out runs under.

  `AsyncCalls.config/0`'s, plus the one option that makes a fan-out
  possible: `:child_starter`, naming this module, because the scheduling
  package creates no runs and has no dependency on the one that does.
  `:max_fan_out` is left at the package's default - see the moduledoc.

  Built on every call, for `Timers.config/0`'s reason: these are
  constants, and a memoised copy is one more thing that can be stale.
  """
  @impl StatifierOban.Invoke.Handler
  @spec config() :: Config.t()
  def config do
    options = [
      oban: Timers.oban(),
      timers_queue: Timers.queue(),
      delivery: Timers.Delivery,
      invoke_queue: AsyncCalls.queue(),
      invoke_delivery: AsyncCalls.Delivery,
      child_starter: __MODULE__
    ]

    case Config.new(options) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  Turns one fan-out invocation into the list it fans out over.

  `{:fan_out, descriptors}` is the base's "this invocation is N children,
  not an answer": the job enqueues the starts and completes without
  delivering, and the invocation stays open until the settlement side
  answers it once on behalf of all N.

  The list comes out of the parent run's own datamodel, at the path the
  block's `items` names. A path that resolves to nothing is
  `{:error, {:items_undefined, path}}` and a value that is not a list is
  `{:error, {:items_not_a_list, path}}`; both fail the invocation
  permanently, which is right - neither is a condition that a retry
  changes.
  """
  @impl StatifierOban.Invoke.Handler
  @spec run(Invoke.t(), map()) :: {:fan_out, list()} | {:error, term()}
  def run(%Invoke{} = invoke, %{scope: parent_run_id}) do
    case descriptors(parent_run_id, invoke) do
      {:ok, descriptors} ->
        Logger.info("fanning #{invoke.invoke_id} out over #{length(descriptors)} items")

        {:fan_out, descriptors}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Creates child `index` of `count` for `invoke`, under `parent_run_id`.

  `StatifierOban.Invoke.ChildStarter`'s callback. It is called from an
  Oban job and therefore at least once per index, and it is idempotent on
  `{parent_run_id, invoke.invoke_id, index}` because
  `StatifierPersistence.Driver.start_child_at/6` is: the child's run id is
  derived from that triple, and a second call adopts the child the first
  one created.

  The descriptor the child is seeded with is this index's item, so the
  list is evaluated again here - see the moduledoc. A refusal becomes
  `{:error, reason}`, which retries the start job: every refusal the
  package makes is environment-shaped or deploy-shaped, and an index that
  can never be created exhausts its retries and is visible on the job row.
  """
  @impl StatifierOban.Invoke.ChildStarter
  @spec start_child(String.t(), Invoke.t(), non_neg_integer(), pos_integer(), keyword()) ::
          :ok | {:error, term()}
  def start_child(parent_run_id, %Invoke{} = invoke, index, count, opts) do
    with {:ok, descriptors} <- descriptors(parent_run_id, invoke),
         {:ok, descriptor} <- at(descriptors, index) do
      parent_run_id
      |> Durable.start_child_at(invoke, %{"chunk" => descriptor}, index, count, opts)
      |> started()
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The `child_canceller:` fun `StatifierPersistence.Driver` is built with.

  It is handed the parent run id, the invocation id and the indices with
  no run record, and it uses the first two: the package's cancel matches
  every `ChildStartWorker` job for `{scope, invoke_id}` that has not run,
  across every index and generation, so the index list is a narrowing
  this door does not need. A cancel matching nothing answers `{:ok, 0}`
  and is not an error.
  """
  @spec canceller() :: (String.t(), String.t(), [non_neg_integer()] -> :ok)
  def canceller do
    fn parent_run_id, invoke_id, _unstarted_indices ->
      {:ok, cancelled} = Scheduling.cancel_unstarted(config(), parent_run_id, invoke_id)

      Logger.info("cancelled #{cancelled} unstarted children of #{invoke_id}")

      :ok
    end
  end

  @doc """
  Consumes one effect on behalf of the run named by `run_id`.

  `AsyncCalls.consume/2`'s twin, for the one effect this module claims:
  a `{:invoke, %Invoke{}}` whose type is a `core.map`'s becomes one
  stored fan-out job, keyed on `{run_id, invoke_id, macrostep}` by the
  base. A `{:cancel_invoke, _}` is handed to the base as well - the
  invoking state exiting has to take the fan-out job with it - and a
  cancel matching nothing is a no-op by the base's own contract.

  Every other effect passes through untouched and answers `:ok`, because
  the caller is an executor whose whole vocabulary is `:ok` and
  `{:error, _}`, and "this effect is not a fan-out" is not an error.
  """
  @spec consume(String.t(), Statifier.Effect.t()) :: :ok
  def consume(run_id, {:invoke, %Invoke{} = invoke}) when is_binary(run_id) do
    if fan_out?(invoke.type) do
      start!(run_id, invoke)
    else
      :ok
    end
  end

  def consume(run_id, {:cancel_invoke, %CancelInvoke{} = effect}) when is_binary(run_id) do
    case Handler.perform_cancel(__MODULE__, effect.invoke_id, ctx(run_id)) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "could not cancel the fan-out #{effect.invoke_id} for #{run_id}: " <>
                inspect(reason)
    end
  end

  def consume(run_id, _other) when is_binary(run_id), do: :ok

  @spec start!(String.t(), Invoke.t()) :: :ok
  defp start!(run_id, %Invoke{} = invoke) do
    case Handler.perform_start(__MODULE__, invoke, ctx(run_id)) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "could not start the fan-out #{invoke.invoke_id} for #{run_id}: " <>
                inspect(reason)
    end
  end

  # The descriptor list, evaluated out of the parent run's own persisted
  # datamodel at the path the block's `items` names.
  @spec descriptors(String.t(), Invoke.t()) :: {:ok, list()} | {:error, term()}
  defp descriptors(parent_run_id, %Invoke{} = invoke) do
    with {:ok, path} <- items_path(invoke),
         {:ok, machine_state} <- machine_state(parent_run_id) do
      resolve(machine_state.datamodel, path)
    end
  end

  @spec items_path(Invoke.t()) :: {:ok, String.t()} | {:error, term()}
  defp items_path(%Invoke{params: %{"items" => path}}) when is_binary(path) and path != "",
    do: {:ok, path}

  defp items_path(%Invoke{invoke_id: invoke_id}), do: {:error, {:items_missing, invoke_id}}

  @spec machine_state(String.t()) :: {:ok, Statifier.MachineState.t()} | {:error, term()}
  defp machine_state(parent_run_id) do
    case Durable.machine_state(parent_run_id) do
      {:ok, machine_state} -> {:ok, machine_state}
      {:error, reason} -> {:error, {:parent_unreadable, reason}}
    end
  end

  # A dotted path over the string-keyed datamodel. The engine's own
  # expression language would evaluate the same path the same way; this
  # walk is here because what the block emits is a path and not an
  # expression, and a host that compiled it as one would be inventing a
  # capability `core.map` deliberately did not give the field.
  @spec resolve(map(), String.t()) :: {:ok, list()} | {:error, term()}
  defp resolve(datamodel, path) do
    case get_in(datamodel, String.split(path, ".")) do
      items when is_list(items) -> {:ok, items}
      nil -> {:error, {:items_undefined, path}}
      _other -> {:error, {:items_not_a_list, path}}
    end
  end

  @spec at(list(), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  defp at(descriptors, index) do
    case Enum.fetch(descriptors, index) do
      {:ok, descriptor} -> {:ok, descriptor}
      :error -> {:error, {:index_out_of_range, index, length(descriptors)}}
    end
  end

  @spec started(:ok | {:refused, term()}) :: :ok | {:error, term()}
  defp started(:ok), do: :ok
  defp started({:refused, reason}), do: {:error, reason}

  # The context the base reads its scope out of, `AsyncCalls.ctx/1`'s copy
  # and for its reason: this host has no session, so the run id is what
  # goes in the field a session host puts its session id in.
  @spec ctx(String.t()) :: Statifier.Invoke.Handler.ctx()
  defp ctx(run_id) do
    %{session_id: run_id, invoke_types: Types.new(types: []), invoke_handlers: %{}}
  end
end
