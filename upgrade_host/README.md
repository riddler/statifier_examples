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
- **One durable chart from the library loan.** A copy goes out on loan and
  comes due on a delayed send; a renewal cancels the send and arms a fresh
  one; an overdue loan has its fine assessed and the patron notified
  through two invoke handlers, and waits for the copy to come back.
  `UpgradeHost.Loans` drives it with no process holding the execution:
  every timer and invocation is an Oban job, and every answer goes back in
  through a delivery module.
- **Telemetry.** The three OpenTelemetry bridges, with datamodel values
  kept out of every span; the suite exports spans to itself and checks
  them.
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
