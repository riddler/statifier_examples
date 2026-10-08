defmodule UpgradeHost.ScopePlacement do
  @moduledoc """
  Places a loan's rows at a branch for the storage conformance suite's
  scoped prune case: writes the host's own `branch_id` column, which the
  package never writes, onto the execution row and its input log rows.
  """

  import Ecto.Query, only: [from: 2]

  alias StatifierPersistence.Ecto.Config

  @spec place(keyword(), String.t(), keyword()) :: :ok
  def place(_adapter_opts, execution_id, scope) do
    config = UpgradeHost.Persistence.__statifier_persistence__(:config)

    for table <- [Config.table(config, :executions), Config.table(config, :inputs)] do
      UpgradeHost.Repo.update_all(from(r in table, where: r.execution_id == ^execution_id),
        set: scope
      )
    end

    :ok
  end
end
