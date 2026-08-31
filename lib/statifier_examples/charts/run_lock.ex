defmodule StatifierExamples.Charts.RunLock do
  @moduledoc """
  This app's per-run serialization strategy: the exclusion
  `StatifierPersistence.Runs` runs every fetch-to-persist tail inside.

  ## Why the host has to supply one at all

  `StatifierPersistence.Runs` defaults its `serialization:` option to
  `{StatifierPersistence.Serialization.AdapterLock, store}`, which asks
  the storage adapter for its optional `lock_run/3`.
  `StatifierExamples.Persistence` does not export that callback - SQLite
  has neither an advisory lock nor a row lock to take, and that module's
  moduledoc says why - so the default refuses with
  `{:error, {:serialization, :not_supported}}` before a run ever starts.

  The refusal is the contract working, not a gap: the strategy is a seam
  precisely so a host that orders deliveries some other way can say how.
  This is that answer for a single-node app - a lock server keyed by run
  id, which is the shape `StatifierPersistence.Serialization`'s own
  moduledoc names ("a single job-queue consumer per run id, for one").

  ## What it guarantees, and what it does not

  The behaviour asks for two things and this gives both: for one run id
  two `with_run/3` bodies never overlap, and a body that finishes before
  another starts is durable before the later one loads - the waiter is
  not woken until the holder has released, and the holder releases after
  its body has returned.

  Bodies for *different* run ids run concurrently, which is the whole
  reason this is keyed rather than a single global mutex. Waiters on one
  id are served first-in-first-out, which is more than the behaviour
  promises and is free here.

  The body runs in the **calling** process, never in this server: a
  stepper tail does storage work and executor work, and a lock server
  that ran it would serialize every run in the app behind one mailbox and
  would die with the first executor that raised. What the server holds is
  the bookkeeping.

  ## A holder that dies

  The caller is monitored for exactly as long as it holds the lock, so a
  crash between acquire and release hands the lock to the next waiter
  instead of stranding the run id forever. That is not a nicety in this
  app: the holder is usually a LiveView process, and a reader closing the
  tab mid-step is an ordinary thing to observe.

  This is a single-node strategy and says so. Two nodes would each have
  their own server and neither would exclude the other; a host running
  more than one node wants the adapter lock and therefore wants Postgres.
  """

  use GenServer

  @behaviour StatifierPersistence.Serialization

  @typep waiter :: GenServer.from()
  @typep held :: %{owner: reference(), waiting: :queue.queue(waiter())}
  @typep state :: %{locks: %{String.t() => held()}, owners: %{reference() => String.t()}}

  @acquire_timeout :timer.seconds(30)

  @doc """
  Starts the lock server. Registered under its own module name, which is
  also the `config` `with_run/3` is called with.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Runs `fun` under this app's exclusion for `run_id`.

  `config` is the server to ask, so a test can stand up its own rather
  than contend with the application's. Returns `{:ok, fun.()}`; this
  strategy has no refusal of its own, which is the point of writing one
  the database can honour.
  """
  @impl StatifierPersistence.Serialization
  @spec with_run(GenServer.server(), String.t(), (-> result)) :: {:ok, result} when result: var
  def with_run(config, run_id, fun) when is_binary(run_id) and is_function(fun, 0) do
    :ok = GenServer.call(config, {:acquire, run_id}, @acquire_timeout)

    try do
      {:ok, fun.()}
    after
      GenServer.call(config, {:release, run_id}, @acquire_timeout)
    end
  end

  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok), do: {:ok, %{locks: %{}, owners: %{}}}

  @impl GenServer
  def handle_call({:acquire, run_id}, {pid, _tag} = from, state) do
    case Map.fetch(state.locks, run_id) do
      :error -> {:reply, :ok, grant(state, run_id, pid)}
      {:ok, held} -> {:noreply, enqueue(state, run_id, held, from)}
    end
  end

  def handle_call({:release, run_id}, _from, state) do
    {:reply, :ok, hand_over(state, run_id)}
  end

  @impl GenServer
  def handle_info({:DOWN, owner, :process, _pid, _reason}, state) do
    case Map.fetch(state.owners, owner) do
      {:ok, run_id} -> {:noreply, hand_over(state, run_id)}
      :error -> {:noreply, state}
    end
  end

  # ---------------------------------------------------------- bookkeeping

  @spec grant(state(), String.t(), pid()) :: state()
  defp grant(state, run_id, pid) do
    owner = Process.monitor(pid)

    %{
      state
      | locks: Map.put(state.locks, run_id, %{owner: owner, waiting: :queue.new()}),
        owners: Map.put(state.owners, owner, run_id)
    }
  end

  @spec enqueue(state(), String.t(), held(), waiter()) :: state()
  defp enqueue(state, run_id, held, from) do
    held = %{held | waiting: :queue.in(from, held.waiting)}

    %{state | locks: Map.put(state.locks, run_id, held)}
  end

  # Releasing and granting to the next waiter are one step, so the lock is
  # never observable as free while somebody is queued for it.
  @spec hand_over(state(), String.t()) :: state()
  defp hand_over(state, run_id) do
    case Map.fetch(state.locks, run_id) do
      :error ->
        state

      {:ok, held} ->
        state = release(state, held)

        case :queue.out(held.waiting) do
          {:empty, _queue} ->
            %{state | locks: Map.delete(state.locks, run_id)}

          {{:value, {pid, _tag} = from}, waiting} ->
            state = grant(state, run_id, pid)
            GenServer.reply(from, :ok)
            put_in(state.locks[run_id].waiting, waiting)
        end
    end
  end

  @spec release(state(), held()) :: state()
  defp release(state, %{owner: owner}) do
    Process.demonitor(owner, [:flush])

    %{state | owners: Map.delete(state.owners, owner)}
  end
end
