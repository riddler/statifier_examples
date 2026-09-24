# The first workflow, end to end, on current pins

This guide takes one workflow from a block document to a finished durable
execution: it publishes the document through the publish-time checks,
registers the compiled chart, opens an execution, lets an invoke handler do
the work under a bounded run time, lets a chart timer fire, and reads the
trace. Every step is code in this app, and one command runs them all:

    mix ecto.migrate
    mix statifier_examples.first_workflow

The command prints one line per step and stops with a non-zero exit, naming
the step, if any of them does not hold.

## The pins

The recipe is written and checked against these releases, which are what
`mix.exs` requires and `mix.lock` resolves:

| Package | Version | What the recipe uses it for |
|---|---|---|
| `statifier` | 2.8.1 | compiling the chart and running it |
| `statifier_blocks` | 0.35.0 | the document, `Plan.expressible/3`, the compile |
| `statifier_persistence` | 0.17.0 | the chart registry, the execution, the input log, `ended_at` |
| `statifier_oban` | 0.13.0 | the invoke job and its `:invoke_timeout`, the timer job |
| `statifier_router` | 0.4.1 | two of the publish-time checks |

`statifier_datamodel` 0.4.0 arrives through `statifier_blocks`. The first
line the command prints names the versions it actually loaded.

## The workflow

The document is `priv/first_workflow/hold_pickup.json`. A patron has placed
a hold on a library copy, and the hold does two things in order:

1. **Set the copy aside.** A `core.invoke` of `myapp:set_aside` hands the
   hold to the branch, and writes the branch's answer to `shelved`.
2. **Wait out the pickup window.** A `core.wait` holds the execution for the
   window. The document says `1s` so the command finishes quickly; a real
   branch would say days.

When both are done, the execution completes.

The code is `StatifierExamples.FirstWorkflow`. The sections below follow its
`run/1`, one step at a time.

## 1. Check the document against the palette

`StatifierBlocks.Plan.expressible/3` asks whether the editor could hold this
document: every block's type resolves in the palette the host mounts, every
block sits in a slot that admits it, and every required slot can be filled.
It answers `:ok` or `{:no, reasons}`, one reason per refusal, each naming
the rule and the block. `Plan.expressible?/3` asks the same question and
answers a boolean.

This check is for a document that did not come out of the editor: one
written by hand, generated, or imported, like this one.

## 2. Publish it through the publish-time checks

`StatifierExamples.Publish.check/2` is this app's publish step. The packages
ship check functions but no publish step, so every host writes its own; this
one runs seven checks in order and stops at the first that refuses:

1. `StatifierBlocks.Publish.findings/3`, the findings the editor shows;
2. `StatifierBlocks.Compiler.compile/3` and `Statifier.compile/2`;
3. `Statifier.Send.Types.unsupported_sends/2`;
4. `StatifierRouter.Routes.unregistered/2`;
5. `StatifierRouter.Contracts.check/3`;
6. `Statifier.Chart.check_accepts/2`;
7. `StatifierBlocks.Graph.check/2`.

The host state it judges against is a map: the palette, the datamodel
document, the send types the host registers, the router configuration, and
two lookups (what a receiving document accepts, and a child document's
published artifact). This document sends nothing and names no child
document, so the recipe hands over an empty send-type map, a router
configuration with no routes, and two lookups that find nothing.

`check/2` answers `{:ok, compiled, accepts, warnings}` or
`{:refused, %{stage: stage, findings: findings}}`.

## 3. Register the compiled chart

The chart an execution runs is compiled once more for running:

```elixir
Compiler.compile(document, palette,
  known_invoke_types: ["myapp:set_aside"],
  terminate: true
)
```

`terminate: true` gives the finished sequence a top-level final, so the
execution completes rather than resting after the last block. It changes
the generated SCXML, and the SCXML is what the chart's content hash is
taken over, so every place a host compiles a chart it means to run must
pass the same `terminate:` and `declare:` options. `known_invoke_types:`
changes nothing in the SCXML: it adds a compile warning for every
`core.invoke` whose type the host has not listed.

`StatifierPersistence.Storage.save_chart/3` then stores the SCXML under that
content hash. This is what lets a process that never saw the document
continue an execution: the execution record carries the content hash, and
`StatifierExamples.FirstWorkflow.machine_for/2` rebuilds the chart from the
registered SCXML. Both jobs below rely on it.

## 4. Open the execution

`StatifierPersistence.Driver.create/3` opens the execution. It calls
`StatifierPersistence.Executions.create/4` and then drives the chart until
there is nothing left to answer. The driver is built by
`StatifierExamples.FirstWorkflow.driver/2` with four things:

- `dispatch:` answers each `<invoke>`. For `myapp:set_aside` it answers
  `:pending`: the call has started and will be answered later.
- `effects:` is the executor. It stores an Oban job for the set-aside call
  (`StatifierOban.Invoke.Handler.perform_start/3`) and for each delayed
  `<send>` (`StatifierOban.Timer.schedule/3`), and cancels them on the
  matching cancel effects.
- `invoke_types:` registers `myapp:set_aside` with the interpreter.
- `serialization:` is how steps on one execution are kept from overlapping.
  The default is the storage adapter's own lock, which this app's SQLite
  adapter does not offer, so it passes its own
  (`StatifierExamples.Charts.ExecutionLock`). A host on Postgres takes the
  default and leaves this option out.

The hold goes in as the datamodel's starting value, through `initialize:`.
After `create/3` the execution is `:active` and stored, with the set-aside
call pending and one job in the `statifier_invocations` queue. No process
holds it.

## 5. The act, with a bounded run time

`StatifierExamples.FirstWorkflow.SetAside` is the invoke handler: its
`run/1` does the work and answers `{:ok, donedata}` or `{:error, reason}`.
It runs inside an Oban job, and a job may run more than once for the same
invocation, so the work must be idempotent. A handler that writes something
keys the write on the invocation's `invoke_id`.

Its `config/0` returns the `StatifierOban.Config` the job runs under, and
that configuration sets `invoke_timeout: 5_000`. An attempt that runs past
five seconds fails with `Oban.TimeoutError` and retries while attempts
remain. If the last attempt times out, the chart receives
`error.communication.invoke.<invoke_id>` with `reason: "run_crashed"`, the
same event a handler that raises sends. The default is `:infinity`, no
bound. Two things change when you set a bound:

- the handler runs in a task linked to the job process, so `self()` and the
  process dictionary are the task's, not the job's;
- if you run `Oban.Plugins.Lifeline`, its `:rescue_after` must be larger
  than the bound plus the 5-second margin the invoke worker adds.

When the job finishes, `StatifierExamples.FirstWorkflow.Delivery` sends the
answer back through `StatifierPersistence.Driver.done_invocation/5`, which
steps the chart with `done.invoke.<invoke_id>`. A permanent failure goes
through `failed_invocation/5` instead. Either way the delivery starts from
nothing but the execution id: it rebuilds the chart from the registry (step
3) and the driver loads the stored position.

The answer lands in `shelved`, and the chart enters the wait.

## 6. The chart timer

Entering the `core.wait` produces a delayed `<send>`. The executor stores it
as a job in the `statifier_timers` queue, scheduled for when the window
ends. The job is a row in the database, so the timer outlasts a restart; an
in-memory `Statifier.Session` would have used `Process.send_after/3` and
lost it.

When the job comes due, the same delivery module sends the event back
through `StatifierPersistence.Driver.send_event/4`. The wait ends, the
sequence finishes, and the execution completes. Leaving the wait early
would produce the cancel the compiler emits in the wait's `<onexit>`, and
the executor would remove the job.

`run/1` waits for both jobs by polling the stored execution. On each poll
it runs every job that is already due, and never a timer early. In the dev
app the queues also run on their own, and in the test configuration
(`testing: :manual`) nothing runs unless something drains the queue, so the
same code finishes in both.

## 7. Read the trace

When the timer has fired, the stored record is `:completed`, and its
`ended_at` holds the time it ended. `StatifierPersistence.Executions.ended?/1`
answers whether that stamp is set.

The trace is the input log, from `StatifierPersistence.Executions.inputs/2`:
every event that entered the execution, oldest first, with the door it came
in through. For this workflow it has two entries:

    0 done_invocation done.invoke.<invoke_id>
    1 step statifier_blocks.wait.blk_hp_pickup_window

The log is stored with the execution, so it can be read at any time and
from any process. The editor's Run pane replays the same log
(`StatifierExamples.Charts.Replay`).

## Moving an existing host to these pins

Each package's `docs/upgrading.md` lists what a host changes, version by
version. This is what moving this app from statifier 2.7.0,
statifier_persistence 0.13.0, statifier_oban 0.10.0, statifier_blocks
0.33.0 and statifier_router 0.3.0 took:

- **statifier_persistence 0.17.0 needs migration V08** before the new code
  reads an execution. V08 adds the `ended_at` column and an index on it. This
  app added it in a migration of its own,
  `priv/repo/migrations/20260924120001_add_statifier_persistence_ended_at.exs`,
  and every statement in it runs on SQLite. V08 fills in no values:
  executions that had already ended before it ran read `ended_at` as `nil`.
- **statifier_persistence 0.14.0 added the `:needs_migration` status.** This
  app's storage adapter maps each status string to an atom with no catch-all,
  so it gained a clause for the new one. A host that uses the package's own
  Ecto adapter and does not match on status changes nothing.
- **statifier_router 0.4.0 wraps a refused send's ledger write in a
  transaction and a savepoint.** A test double for the repository that only
  answers `one/1` now also needs `transaction/1` and `query!/1`.
- statifier 2.8.1, statifier_blocks 0.34.0 and 0.35.0, and statifier_oban
  0.11.0 to 0.13.0 needed nothing. Every option statifier_oban 0.13.0 adds
  keeps the old behaviour by default; `:unresolved_handler` defaults to
  `:retry`.
