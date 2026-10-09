defmodule StatifierExamples.FormPost.Stepper do
  @moduledoc """
  The card application router's `:on_create` and `:on_step`: this app's
  execution door, which every create and every step the router makes for
  a card application goes through, and so does every step
  `StatifierExamples.FormPost.Delivery` makes for a step's answer or a
  fired deadline.

  A host whose own engine wraps statifier_persistence's two doors hands
  the router a stand-in for each, and the router calls it where it would
  have called persistence, inside the delivery's transaction and
  savepoint. This door does two things before it calls through:

    * it refuses with `{:error, :no_library_system}` when no library
      system is held (`StatifierExamples.FormPost.Scope.fetch/0`), the
      way a host's own door refuses to run outside a tenant. Every door
      the router drives itself runs inside
      `StatifierExamples.FormPost.Scope.around_delivery/3`, and so does
      every step `StatifierExamples.FormPost.Delivery` makes, so the
      refusal is only ever met by a call made outside both;
    * it adds this app's serialization strategy, through
      `StatifierExamples.RoutedWorkflow.Stepper`: SQLite has no
      per-execution lock for the router's default calls to take, and that
      module's moduledoc says why.

  Each function takes the arguments the router hands the direct call and
  answers that call's own return, so the router reads the answer exactly
  as it reads persistence's.
  """

  alias StatifierExamples.FormPost.Scope
  alias StatifierExamples.RoutedWorkflow.Stepper

  @doc "`StatifierPersistence.Executions.create/4`, in a library system, serialized."
  @spec create(StatifierPersistence.Storage.t(), String.t(), Statifier.Machine.t(), keyword()) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:error, term()}
  def create(store, execution_id, machine, opts) do
    with {:ok, _library_system} <- Scope.fetch() do
      Stepper.create(store, execution_id, machine, opts)
    end
  end

  @doc "`StatifierPersistence.Executions.step/5`, in a library system, serialized."
  @spec step(
          StatifierPersistence.Storage.t(),
          String.t(),
          Statifier.Machine.t(),
          Statifier.Event.t() | StatifierPersistence.Executions.event_builder(),
          keyword()
        ) ::
          {:ok, StatifierPersistence.Execution.t(), Statifier.MachineState.t()}
          | {:discarded, StatifierPersistence.Execution.t()}
          | {:error, term()}
  def step(store, execution_id, machine, event, opts) do
    with {:ok, _library_system} <- Scope.fetch() do
      Stepper.step(store, execution_id, machine, event, opts)
    end
  end
end
