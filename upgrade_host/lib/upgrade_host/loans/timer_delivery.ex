defmodule UpgradeHost.Loans.TimerDelivery do
  @moduledoc """
  Where a fired loan timer goes back in. The scope is the loan id; the
  loan is live while its execution takes events, and a loan that has
  already ended discards the event with its stored status. A store that
  cannot be reached raises, so Oban retries the job.
  """

  @behaviour StatifierOban.Timer.Delivery

  alias StatifierOban.Timer.Delivery
  alias UpgradeHost.Loans

  @impl Delivery
  def deliver(scope, effect) do
    case Loans.deliver(scope, Delivery.fired_event(scope, effect)) do
      {:ok, _execution, _machine_state} -> :delivered
      {:discarded, execution} -> {:discarded, execution.status}
      {:error, reason} -> raise "loan #{scope} could not take its timer: #{inspect(reason)}"
    end
  end
end
