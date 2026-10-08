defmodule UpgradeHost.Loans.InvokeDelivery do
  @moduledoc """
  Where an invocation's answer goes back into a loan, built with
  `Statifier.Invoke.Answer` and carrying the invocation's caller context.

  The answer is built against the loaded position: an invocation the loan
  already left (a copy returned while its fine was being assessed) is no
  longer live there, and its answer is discarded rather than stepped.
  """

  @behaviour StatifierOban.Invoke.Delivery

  alias Statifier.Invoke.Answer
  alias UpgradeHost.Loans

  @impl StatifierOban.Invoke.Delivery
  def deliver(scope, invoke_id, donedata), do: deliver(scope, invoke_id, donedata, [])

  @impl StatifierOban.Invoke.Delivery
  def deliver(scope, invoke_id, donedata, opts) do
    answer(scope, invoke_id, fn ->
      Answer.done(scope, invoke_id, donedata, caller_context: Keyword.get(opts, :caller_context))
    end)
  end

  @impl StatifierOban.Invoke.Delivery
  def deliver_failure(scope, invoke_id, failure),
    do: deliver_failure(scope, invoke_id, failure, [])

  @impl StatifierOban.Invoke.Delivery
  def deliver_failure(scope, invoke_id, failure, opts) do
    answer(scope, invoke_id, fn ->
      Answer.failed(scope, invoke_id, failure, caller_context: Keyword.get(opts, :caller_context))
    end)
  end

  defp answer(scope, invoke_id, build) do
    builder = fn machine_state ->
      if invoke_id in Map.values(machine_state.active_invocations),
        do: {:ok, build.()},
        else: :discard
    end

    case Loans.deliver(scope, builder) do
      {:ok, _execution, _machine_state} -> :delivered
      {:discarded, execution} -> {:discarded, execution.status}
      {:error, reason} -> raise "loan #{scope} could not take its answer: #{inspect(reason)}"
    end
  end
end
