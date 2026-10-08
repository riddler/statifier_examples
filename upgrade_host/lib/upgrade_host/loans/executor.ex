defmodule UpgradeHost.Loans.Executor do
  @moduledoc """
  The loan's `StatifierPersistence.Executor`: every effect with durable
  work behind it becomes an Oban job, inside the step that produced it.

    * a delayed send is a timer job (`StatifierOban.Timer.schedule/3`),
      and a `<cancel>` cancels the timer jobs under its send id;
    * an `<invoke>` is planned by its handler's own `start/2` and the
      instructions performed (`StatifierOban.Invoke.Handler` inserts the
      job); leaving the invoking state is the same through `cancel/2`.

  The scope every job is stored under is the loan's execution id. A job
  that cannot be stored raises rather than answering `{:error, _}`: an
  error here would re-enter the chart as `error.communication`, steering
  the loan with an infrastructure fact, where a raise rolls the step back
  and leaves the event to be delivered again.
  """

  @behaviour StatifierPersistence.Executor

  alias Statifier.Effect.{Cancel, CancelInvoke, Invoke, SendDelayed}
  alias UpgradeHost.Loans

  # The chart writes its invoke ids, so the handler that served each one is
  # known by id when the cancel comes.
  @invocations %{"fine" => Loans.AssessFine, "notice" => Loans.NotifyPatron}

  @impl StatifierPersistence.Executor
  def execute({:send_delayed, %SendDelayed{target: nil} = effect}, %{execution_id: scope}) do
    {:ok, %Oban.Job{}} = StatifierOban.Timer.schedule(Loans.oban_config(), scope, effect)
    :ok
  end

  def execute({:cancel, %Cancel{} = effect}, %{execution_id: scope}) do
    {:ok, _cancelled} = StatifierOban.Timer.cancel(Loans.oban_config(), scope, effect)
    :ok
  end

  def execute({:invoke, %Invoke{type: type} = invoke}, %{execution_id: scope}) do
    handler = Map.fetch!(Loans.invoke_handlers(), type)
    ctx = plan_ctx(scope)
    {:ok, instructions} = handler.start(invoke, ctx)
    perform(instructions, ctx)
  end

  def execute({:cancel_invoke, %CancelInvoke{invoke_id: invoke_id}}, %{execution_id: scope}) do
    handler = Map.fetch!(@invocations, invoke_id)
    ctx = plan_ctx(scope)
    {:ok, instructions} = handler.cancel(invoke_id, ctx)
    perform(instructions, ctx)
  end

  def execute(_effect, _context), do: :ok

  defp perform(instructions, ctx) do
    Enum.each(instructions, fn {:handler, module, payload} ->
      :ok = module.perform(payload, ctx)
    end)
  end

  # The plan context a handler's callbacks take: the scope rides as the
  # session id, which is what `StatifierOban.Invoke.Handler` stores the job
  # under.
  defp plan_ctx(scope) do
    %{
      session_id: scope,
      invoke_types: Loans.invoke_types(),
      invoke_handlers: Loans.invoke_handlers()
    }
  end
end
