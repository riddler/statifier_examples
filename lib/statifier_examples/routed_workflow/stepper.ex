defmodule StatifierExamples.RoutedWorkflow.Stepper do
  @moduledoc """
  The routed recipe's `:on_create` and `:on_step`: the two calls
  `StatifierRouter.Delivery` makes into `StatifierPersistence.Executions`,
  made here instead, with this app's serialization strategy added.

  The router calls `StatifierPersistence.Executions.create/4` and
  `StatifierPersistence.Executions.step/5` with no `serialization:`, so
  each takes the default, the storage adapter's own per-execution lock.
  `StatifierExamples.Persistence` offers none (SQLite has no row lock to
  take; that module's moduledoc says why), and the default refuses with
  `{:error, {:serialization, :not_supported}}`. So every create and every
  step the router makes goes through here, carrying
  `StatifierExamples.Charts.ExecutionLock`, exactly as
  `StatifierExamples.FirstWorkflow.driver/2` does for the driver.

  Each function takes the arguments the router would have handed the
  direct call, and answers that call's own return, so the router reads the
  answer exactly as it reads persistence's. It runs inside the delivery's
  transaction and savepoint. A host on Postgres, whose adapter offers the
  lock, sets neither hook.
  """

  alias StatifierExamples.Charts.ExecutionLock
  alias StatifierPersistence.Executions

  @serialization {ExecutionLock, ExecutionLock}

  @doc "`StatifierPersistence.Executions.create/4`, under this app's serialization."
  @spec create(StatifierPersistence.Storage.t(), String.t(), Statifier.Machine.t(), keyword()) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:error, term()}
  def create(store, execution_id, machine, opts),
    do: Executions.create(store, execution_id, machine, serialized(opts))

  @doc "`StatifierPersistence.Executions.step/5`, under this app's serialization."
  @spec step(
          StatifierPersistence.Storage.t(),
          String.t(),
          Statifier.Machine.t(),
          Statifier.Event.t(),
          keyword()
        ) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:discarded, StatifierPersistence.Execution.t()}
          | {:error, term()}
  def step(store, execution_id, machine, event, opts),
    do: Executions.step(store, execution_id, machine, event, serialized(opts))

  @spec serialized(keyword()) :: keyword()
  defp serialized(opts), do: Keyword.put(opts, :serialization, @serialization)
end
