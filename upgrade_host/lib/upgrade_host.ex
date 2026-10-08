defmodule UpgradeHost do
  @moduledoc """
  A production host's statifier family set, frozen at the versions it
  adopted, so the host's way forward can be walked one package at a time.

  The host this mirrors runs on Postgres and Oban: durable executions in
  `statifier_persistence`, delayed sends and invocations as Oban jobs
  through `statifier_oban`, spans through `opentelemetry_statifier`, and
  `statifier_router`'s tables migrated though nothing calls the router yet.
  Its charts are `statifier_blocks` documents over a palette of its own,
  compiled at runtime. This project makes the same calls in the same
  shapes, over one chart from the library loan (`UpgradeHost.Loans`), so a
  release that breaks one of them breaks here first.

  The pieces:

    * `UpgradeHost.Repo` - the Ecto Postgres repo.
    * `UpgradeHost.Persistence` - `use StatifierPersistence.Ecto`, with a
      key generator of the host's own (`UpgradeHost.KeyGenerator`).
    * `UpgradeHost.Loans` - the chart, the store, the Oban configuration
      and the two doors a loan is driven through.
    * `UpgradeHost.Loans.LoanDocument` - the loan as a block document,
      authored edit by edit and compiled to the chart.
    * `UpgradeHost.Loans.Blocks` - the host's palette: the core vocabulary
      and the host's three block types under `UpgradeHost.Loans.Blocks`.
    * `UpgradeHost.Loans.Executor` - the `StatifierPersistence.Executor`
      that turns effects into Oban jobs.
    * `UpgradeHost.Loans.TimerDelivery` and
      `UpgradeHost.Loans.InvokeDelivery` - the two delivery seams a job
      feeds its answer back through.
    * `UpgradeHost.Loans.AssessFine` and `UpgradeHost.Loans.NotifyPatron` -
      the two invoke handlers.
    * `UpgradeHost.Telemetry` - the three OpenTelemetry bridges.
  """
end
