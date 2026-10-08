# The upgrade host

A production host's statifier family set, frozen at the versions it
adopted, so its way forward can be walked one package at a time.

A host that adopted the family and then held its pins has every package a
few minors behind. Moving all of them at once leaves it unable to tell
which change broke which call. This project is a host of the same shape,
on the same versions, making the same calls: it is moved forward one
package per step, and each step's lock diff and suite say exactly what that
package changed for a host. The upgrading pages in the packages' docs,
where a package has one, are the guide; this project is the evidence
behind them.

It is a standalone Mix project. statifier_examples does not compile it,
test it or depend on it, and nothing here depends on statifier_examples.

## What it holds

- **The set.** Every family package pinned exactly (`==`), from Hex, with a
  committed `mix.lock`. `test/upgrade_host/lock_test.exs` reads the lock
  and fails on any line that is not the pinned version, so a lock that
  drifts on its own is a red suite.
- **A host on Postgres and Oban.** An Ecto Postgres repo; the persistence
  and router tables migrated through the packages' own migration helpers,
  in the layout a multi-tenant host gives them (a table prefix, a leading
  `branch_id` column, leading timestamps, the `"C"` collation on
  `execution_id`); a persistence module with a key generator of its own;
  an Oban instance with a timers queue and an invocations queue.
- **One durable chart from the library loan, authored as a block
  document.** A copy goes out on loan and comes due on a delayed send; a
  renewal cancels the send and arms a fresh one; an overdue loan has its
  fine assessed and the patron notified through two invoke handlers, and
  waits for the copy to come back, which can come at any point. The chart
  is not written by hand: `UpgradeHost.Loans.LoanDocument` authors it as a
  `statifier_blocks` document, one edit at a time through the edit gate,
  and compiles it; the durable loan runs the compiled chart.
  `UpgradeHost.Loans` drives it with no process holding the execution:
  every timer and invocation is an Oban job, and every answer goes back in
  through a delivery module.
- **A palette of the host's own.** `UpgradeHost.Loans.Blocks` merges three
  block types over the core vocabulary: two invoke steps declared through
  `StatifierBlocks.InvokeStep`, one per handler, and one block type written
  against `StatifierBlocks.BlockType` directly. The document is checked
  against it the way a publish step checks one (expressible through the
  palette, the publish findings, the child graph) and read back through the
  view model as an outline. No editor, no LiveView and no Map: a host that
  mounts none of them still makes every one of these calls.
- **Patron registration through the router's webhook front.** A
  registration form post the host answers itself, keeping the patron's
  name and email in its own `patrons` table, and routes from an Oban job
  through `StatifierRouter.Webhook.handle/3`: one binding keyed on the
  patron's id, the message's `provider_id` and raw body both that id, its
  data the id alone. The post creates the registration's execution, a
  resubmission is answered from the dedupe store, the patron's
  confirmation ends it, and the host's sweep reaps its address once the
  dedupe horizon has passed, so the patron's next registration opens a new
  execution. `UpgradeHost.Registrations.Seams` runs every delivery inside
  the host's tenancy context through `:around_delivery`, and stands in for
  the create and the step, which read that context.
- **Telemetry.** The three OpenTelemetry bridges, with datamodel values
  kept out of every span; the suite exports spans to itself and checks
  them.
- **A loan moved onto a revised loan document.** Two revisions of the
  loan document, one lengthening the loan period and one withdrawing
  renewals, each compiled and saved; a live loan is moved onto each
  through `StatifierPersistence.Executions.migrate/4` with a plan, and
  the migrated point's `statifier_persistence.dropped` attribute is
  checked on the exported span: absent when the plan drops nothing, a
  sorted array of the dropped state ids when it drops some.
- **The packages' own conformance suites**, run over this host: the
  storage conformance suite over the repo, and the invoke handler case
  over each handler.

## Running it

It needs a Postgres server. The defaults are `localhost:5432` as
`postgres`/`postgres`; the `PG*` environment variables override them.

```bash
cd upgrade_host
mix deps.get
mix deps.get --check-locked
mix compile --warnings-as-errors
mix test        # creates and migrates its own database first
```

CI runs those steps in the `Upgrade host` job, on Elixir 1.18.4 and
OTP 26.2.5, the oldest pair a production host is known to run, against
Postgres 17.

## Taking a step

A step moves one package. Change its pin in `mix.exs`, run
`mix deps.update <package>`, and read the lock diff: every line that moved
is part of the step, and a line the step did not mean to move is a finding.
Update the pinned version in `test/upgrade_host/lock_test.exs` in the same
commit, then make the suite green again with the smallest change a host
would make. A step that crosses several minors of one package is one commit
per minor, so a break is pinned to the minor that introduced it.
