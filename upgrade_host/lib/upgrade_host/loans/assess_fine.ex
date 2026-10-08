defmodule UpgradeHost.Loans.AssessFine do
  @moduledoc """
  Serves `<invoke type="myapp:assess_fine">`: the fine on an overdue copy.

  The work keys on the invocation alone, so it is `run/1`. It is a pure
  function of the copy, which makes a re-run after a crash the same answer
  rather than a second fine.
  """

  use StatifierOban.Invoke.Handler

  # A flat fine, in cents. Fictional, like every value here.
  @fine_cents 250

  @impl StatifierOban.Invoke.Handler
  def config, do: UpgradeHost.Loans.oban_config()

  @impl StatifierOban.Invoke.Handler
  def run(%Statifier.Effect.Invoke{params: %{"copy" => copy}}) when is_binary(copy),
    do: {:ok, %{"copy" => copy, "amount" => @fine_cents}}

  def run(%Statifier.Effect.Invoke{params: params}), do: {:error, {:no_copy, params}}
end
