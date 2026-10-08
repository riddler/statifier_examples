defmodule UpgradeHost.StorageConformanceTest do
  # statifier_persistence's own conformance suite, over this host's repo and
  # its persistence module: the key generator, the leading branch column,
  # the leading timestamps and the collation included. The scoped prune
  # case runs on the host's branch column.
  use StatifierPersistence.Testing.StorageConformance,
    async: true,
    adapter: StatifierPersistence.Storage.Ecto,
    opts: [persistence: UpgradeHost.Persistence, sandbox: true],
    prune_scope: [
      inside: [branch_id: "branch-eastside"],
      outside: [branch_id: "branch-westside"],
      place: {UpgradeHost.ScopePlacement, :place}
    ]
end
