defmodule UpgradeHost.Loans do
  @moduledoc """
  The library loan, as a durable execution: the chart, the store it is
  kept in, the Oban configuration its jobs run under, and the two doors a
  loan is driven through - `open/3` for a new loan and `deliver/2` for
  every event after it.

  Each loan is one execution, keyed by the host's own loan id, which is
  also the scope its timer and invoke jobs are stored under and the
  session id its position carries. A loan is created with the host's
  identities in its metadata (`branch_id` and `loan_id`, never anything
  about the patron), which is what `by_branch/1` lists on.

  Nothing here holds an execution in memory between events. A fired timer
  or an answered invocation arrives in an Oban job, possibly on another
  node, and goes back in through `deliver/2` with the chart compiled from
  the source this module carries.
  """

  alias Statifier.{Event, Machine}
  alias Statifier.Invoke.Types
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias UpgradeHost.Loans.{AssessFine, Executor, InvokeDelivery, NotifyPatron, TimerDelivery}

  @external_resource Path.join([__DIR__, "..", "..", "priv", "charts", "library_loan.scxml"])
  @source File.read!(Path.join([__DIR__, "..", "..", "priv", "charts", "library_loan.scxml"]))

  # The handler serving each `<invoke type>` the chart writes.
  @invoke_handlers %{
    "myapp:assess_fine" => AssessFine,
    "myapp:notify_patron" => NotifyPatron
  }

  @timers_queue :loan_timers
  @invoke_queue :loan_invocations

  # How long one attempt of an invoke job may run before Oban fails it.
  @invoke_timeout 30_000

  @doc "The chart's SCXML source, exactly as it is registered."
  @spec source() :: binary()
  def source, do: @source

  @doc """
  The compiled chart. Compiled once per node and kept, because every
  delivery needs it and the source never changes under a running node.
  """
  @spec machine() :: Machine.t()
  def machine do
    case :persistent_term.get({__MODULE__, :machine}, nil) do
      nil ->
        {:ok, machine} = Statifier.compile(@source)
        :persistent_term.put({__MODULE__, :machine}, machine)
        machine

      machine ->
        machine
    end
  end

  @doc "The `<invoke type>` to handler map the executor dispatches on."
  @spec invoke_handlers() :: %{String.t() => module()}
  def invoke_handlers, do: @invoke_handlers

  @doc """
  The registered invoke types, derived from the handler map so the two
  cannot drift. Stamped onto every load: a stored position does not carry
  it.
  """
  @spec invoke_types() :: Types.t()
  def invoke_types, do: Types.from_handlers(@invoke_handlers)

  @doc "The store every loan is kept in."
  @spec store() :: Storage.t()
  def store do
    {:ok, store} =
      Storage.new(StatifierPersistence.Storage.Ecto, persistence: UpgradeHost.Persistence)

    store
  end

  @doc """
  The `statifier_oban` configuration the loan's jobs run under: the host's
  own Oban instance and queues, the two delivery seams, a bound on each
  invoke attempt, and `:retry` for a handler a node cannot resolve.
  """
  @spec oban_config() :: StatifierOban.Config.t()
  def oban_config do
    case StatifierOban.Config.new(
           oban: UpgradeHost.Oban,
           timers_queue: @timers_queue,
           invoke_queue: @invoke_queue,
           delivery: TimerDelivery,
           invoke_delivery: InvokeDelivery,
           invoke_timeout: @invoke_timeout,
           unresolved_handler: :retry
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  Registers the chart under its content hash, so a node that never
  compiled it can read it back.
  """
  @spec register() :: :ok | {:error, term()}
  def register, do: Storage.save_chart(store(), machine(), @source)

  @doc """
  Opens a loan: creates its execution with the loan's copy and patron in
  the datamodel and the host's identities in the metadata.
  """
  @spec open(String.t(), String.t(), map()) ::
          {:ok, Execution.t(), Statifier.MachineState.t()} | {:error, term()}
  def open(loan_id, branch_id, %{"copy" => _, "patron" => _} = loan) do
    Executions.create(store(), loan_id, machine(),
      executor: Executor,
      initialize: [
        session_id: loan_id,
        datamodel: Map.put(loan, "fine", nil),
        invoke_types: invoke_types()
      ],
      metadata: %{"branch_id" => branch_id, "loan_id" => loan_id}
    )
  end

  @doc """
  Delivers one event to a loan, or an event builder the loaded position
  decides on. Every event after the first comes through here: the host's
  own (`loan.renew`, `loan.returned`), a fired timer's, an invocation's
  answer.
  """
  @spec deliver(String.t(), Event.t() | Executions.event_builder()) ::
          {:ok, Execution.t(), Statifier.MachineState.t()}
          | {:discarded, Execution.t()}
          | {:error, term()}
  def deliver(loan_id, event) do
    Executions.step(store(), loan_id, machine(), event,
      executor: Executor,
      invoke_types: invoke_types()
    )
  end

  @doc "Every loan opened at `branch_id`, read through the metadata."
  @spec by_branch(String.t()) :: {:ok, [map()]} | {:error, term()}
  def by_branch(branch_id),
    do: Storage.list_executions_by_metadata(store(), %{"branch_id" => branch_id})
end
