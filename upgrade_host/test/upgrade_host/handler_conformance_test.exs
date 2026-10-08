defmodule UpgradeHost.AssessFineConformanceTest do
  # statifier's handler contract over the fine handler. Its perform/2 stores
  # an Oban job, so the observation point is the jobs stored for the
  # invocation.
  use UpgradeHost.DataCase

  use Statifier.Testing.HandlerCase,
    handler: UpgradeHost.Loans.AssessFine,
    type: "myapp:assess_fine"

  def observed_effects(invoke_id), do: UpgradeHost.HandlerJobs.for_invocation(invoke_id)
end

defmodule UpgradeHost.NotifyPatronConformanceTest do
  # The same contract over the notice handler, the run/2 one.
  use UpgradeHost.DataCase

  use Statifier.Testing.HandlerCase,
    handler: UpgradeHost.Loans.NotifyPatron,
    type: "myapp:notify_patron"

  def observed_effects(invoke_id), do: UpgradeHost.HandlerJobs.for_invocation(invoke_id)
end
