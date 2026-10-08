defmodule UpgradeHost.Loans.NotifyPatron do
  @moduledoc """
  Serves `<invoke type="myapp:notify_patron">`: the overdue notice.

  The notice is filed against the loan, which the effect does not carry,
  so this handler is `run/2` and reads the loan id off the job's scope. The
  notice id is derived from the loan and the invocation, so a re-run files
  the same notice.
  """

  use StatifierOban.Invoke.Handler

  @impl StatifierOban.Invoke.Handler
  def config, do: UpgradeHost.Loans.oban_config()

  @impl StatifierOban.Invoke.Handler
  def run(%Statifier.Effect.Invoke{params: %{"patron" => patron}}, %{
        scope: loan_id,
        invoke_id: invoke_id
      }),
      do: {:ok, %{"notice" => "notice-#{loan_id}-#{invoke_id}", "patron" => patron}}
end
