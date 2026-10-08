defmodule UpgradeHost.Persistence do
  @moduledoc """
  The host's `statifier_persistence` module: the generated schemas and the
  configuration the migration reads, in the shape a multi-tenant host
  writes it. Every table opens with the host's own `branch_id` column, its
  timestamps come right after it, and `execution_id` takes the `"C"` collation.
  """

  use StatifierPersistence.Ecto,
    repo: UpgradeHost.Repo,
    key: {UpgradeHost.KeyGenerator, []},
    leading_columns: [branch_id: {:text, null: true}],
    timestamps_position: :leading,
    column_collations: [execution_id: "C"]
end
