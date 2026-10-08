defmodule UpgradeHost.HandlerJobs do
  @moduledoc """
  The observation point the handler conformance cases judge `perform/2`
  by: the invoke jobs stored for one invocation, as `{id, state}` pairs.
  """

  import Ecto.Query, only: [from: 2]

  @spec for_invocation(String.t()) :: [{integer(), String.t()}]
  def for_invocation(invoke_id) do
    UpgradeHost.Repo.all(
      from(j in Oban.Job,
        where: fragment("?->>'invoke_id' = ?", j.args, ^invoke_id),
        order_by: j.id,
        select: {j.id, j.state}
      )
    )
  end
end
