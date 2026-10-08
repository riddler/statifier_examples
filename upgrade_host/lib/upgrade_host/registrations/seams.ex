defmodule UpgradeHost.Registrations.Seams do
  @moduledoc """
  The host's engine around the router's deliveries of a registration:
  every seam of `StatifierRouter.Config` the delivery calls into.

    * `around_delivery/3` runs a whole delivery inside the host's tenancy
      context: the branch the router hands it as the scope, set with
      `UpgradeHost.Tenancy.run/2` around the work.
    * `create/4` and `step/5` stand in for statifier_persistence's two
      doors, the way a host whose own engine wraps them does. Both read the
      tenancy context and raise outside it; the create stamps the branch
      onto the execution's metadata, the host's identity and never the
      patron's.
    * `resolve/2` and `chart/1` answer the registration chart for any
      branch, and for its content hash.
    * `execute/2` is the executor: the chart has no effect with work
      behind it.
  """

  @behaviour StatifierPersistence.Executor
  @behaviour StatifierRouter.Resolver

  alias Statifier.Machine
  alias StatifierPersistence.Executions
  alias UpgradeHost.{Registrations, Tenancy}

  @doc "Runs the router's `work` for one door under `scope`, as the branch."
  @spec around_delivery(String.t(), atom(), (-> result)) :: result when result: term()
  def around_delivery(scope, _door, work), do: Tenancy.run(scope, work)

  @doc "statifier_persistence's create, inside the branch's context."
  @spec create(StatifierPersistence.Storage.t(), String.t(), Machine.t(), keyword()) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:error, term()}
  def create(store, execution_id, machine, opts) do
    branch_id = Tenancy.current!()

    Executions.create(
      store,
      execution_id,
      machine,
      opts ++ [metadata: %{"branch_id" => branch_id}]
    )
  end

  @doc "statifier_persistence's step, inside the branch's context."
  @spec step(StatifierPersistence.Storage.t(), String.t(), Machine.t(), term(), keyword()) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:discarded, StatifierPersistence.Execution.t()}
          | {:error, term()}
  def step(store, execution_id, machine, event, opts) do
    _branch_id = Tenancy.current!()
    Executions.step(store, execution_id, machine, event, opts)
  end

  @impl StatifierRouter.Resolver
  def resolve(_scope, document) do
    if document == Registrations.document() do
      machine = Registrations.machine()
      {Machine.identity(machine).content_hash, machine}
    else
      {:error, :not_published}
    end
  end

  @doc "The registration chart, for the content hash an execution records."
  @spec chart(String.t()) :: {:ok, Machine.t()} | :error
  def chart(content_hash) do
    machine = Registrations.machine()
    if Machine.identity(machine).content_hash == content_hash, do: {:ok, machine}, else: :error
  end

  @impl StatifierPersistence.Executor
  def execute(_effect, _context), do: :ok
end
