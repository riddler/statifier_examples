# Migrating waiting executions

A library loan waits for weeks. Its execution sits in `awaiting_return`
with a 21-day due-date timer stored as a job, and nothing runs until the
copy comes back or the timer fires. While it waits, someone edits the loan
document: `awaiting_return` is renamed, and the check-in step that comes
after it gains a `damaged` arm. The new revision is published. Every loan
already waiting is still on the old chart.

This guide moves those waiting loans onto the new revision and back again.
It covers publishing the revision, diffing the two charts, building the
migration plan from the blocks mapping, previewing it with a dry run,
applying it, checking that the old chart is drained, asking to retire the
old chart, and rolling back with a reverse plan. One command runs every
step against this app's own database:

    mix ecto.migrate
    mix statifier_examples.migrate_waiting

It prints one line per step. If a step does not answer as this guide says,
it stops with a non-zero exit and names the step. That covers a call that
answers an error, and also a batch that answers with other counts than the
ones quoted below: `migrate_batch/3` answers `{:ok, report}` even when it
refused every loan, so the task checks each report's counts itself. At the end it cancels
the two loans it opened, because the batch below takes every waiting
execution on a chart, not only the ones one run opened. The next run
starts from an empty chart.

## The pins

The migration surface is `statifier_persistence`'s. `mix.exs` asks for
`~> 0.20`, the release that adds `Executions.migrate_batch/3`, and
`mix.lock` resolves 0.21.0. The first line the command prints names the
version it loaded.

The migration surface is the verb and its report. A dry run is the
preview, an apply is the batch, and each execution gets its own result.
There is no migrate action in the editor. Choosing which charts to move,
and when, is the host's job.

## The two revisions

Both revisions are built inside the task, as block documents with the id
`bdoc_loan_waiting`:

- **Revision 1.** A `core.sequence` holding the waiting step, a
  `core.group` with the block id `blk_awaiting_return`. Its body is one
  `core.wait` of `21d`, the due date. Its interrupt is a `core.on_event`
  on `copy.returned`. The sequence then runs `blk_check_in`, a
  `core.branch` that closes the loan when `returned` is set and marks it
  `overdue` otherwise.
- **Revision 2.** The same document, with the waiting step renamed to the
  block id `blk_on_loan`. `blk_check_in` gains a first arm, `damaged`,
  that sets `repair`, and the datamodel declares `damaged` and `repair`.

The task opens two loans on revision 1 through
`StatifierExamples.FirstWorkflow.driver/2`. Each enters
`awaiting_return`, and the driver's executor stores the due-date timer as
a scheduled Oban job:

    waiting      2 loan(s) on revision 1, sha256:6bf4dcb6..., each with its due-date timer

## 1. Publish the new revision

Revision 2 goes through `StatifierExamples.Publish.check/2`, this app's
publish step. The first-workflow guide explains its seven checks. The
revision is then compiled with `terminate: true`. That is the same compile
option revision 1 used, and it matters because the content hash is taken
over the generated SCXML.
`StatifierPersistence.Storage.save_chart/3` stores the result under that
hash:

    published    revision 2, sha256:cfb4ad5f..., 0 warning(s)

Publishing moves nothing. Both charts are now registered, and every
waiting loan is still on revision 1's hash.

## 2. Diff the charts, and read the class

`Statifier.Chart.diff/3` sorts a pair of charts into one of four classes:
`:identical`, `:compatible`, `:mapped` or `:breaking`. It also lists the
reasons. The task diffs the pair twice, once with the blocks mapping from
step 3 and once with the completed plan:

    diff         breaking (5 unresolved) with the blocks mapping, breaking (0 unresolved) with the plan

With the blocks mapping alone, the five states of the renamed step have no
counterpart (`:state_unresolved`). With the plan they are all resolved.
The pair is still `:breaking`, though, because the renamed step also
renames the events its transitions listen for (`done.state.*` and the
interrupt events), and a removed event or transition is breaking.

That is the point of the class. It describes the two charts, not what a
waiting execution will do. A breaking pair can still be harmless to every
loan a host holds. The dry run, below, is what answers for each loan.

## 3. The plan from the blocks mapping

`StatifierBlocks.Migration.plan/2` reads the two compiled revisions and
maps each state of the old chart to the state with the same id and the
same owning block in the new chart. Its answer has the plan's own field
names (`"states"`, `"history"`, `"invocations"`), so a host copies them
straight into a `StatifierPersistence.Migration.Plan`. Everything it
cannot map is listed under `"unmapped"`, along with the block that owned
it:

    plan         the blocks mapping maps 16 state(s) and leaves 5 unmapped; the plan maps those to blk_on_loan

A rename that keeps a block's id maps with nothing left over. This rename
gives the step a new block id, so the five states that `blk_awaiting_return`
minted come back unmapped. The host knows what the rename was, so the task
completes the plan by hand. Each unmapped state of the old block maps to
the same role of the new one:

```elixir
{:ok, mapping} = StatifierBlocks.Migration.plan(old.compiled, new.compiled)

Plan.new(
  from: old.hash,
  to: new.hash,
  states: Map.merge(mapping["states"], %{
    "s_blk_awaiting_return" => "s_blk_on_loan",
    "s_blk_awaiting_return__run" => "s_blk_on_loan__run",
    # ... one entry per unmapped state of the renamed step
  }),
  datamodel: [{:add, "damaged", false}, {:add, "repair", false}]
)
```

The two datamodel operations give every moved loan the new keys, so the
`damaged` arm has something to read.

The plan's `timers` field is `%{keep_mapped: true}`, the only value it
takes. `statifier_persistence` stores no timer and changes none. A pending
timer stays in the host's queue with its deadline, and a plan that maps
the state around it keeps it. The due-date timer is armed in
`s_blk_due_date__waiting`, which the blocks mapping maps, so no pin source
is needed. A plan that left such a state unmapped, or dropped it, would be
refused with `{:no_pin_source, states}` unless the host passed its timer
queue as a pin source.

## 4. The dry run is the preview

`Executions.migrate_batch/3` with `dry_run: true` reads each `:active` and
`:needs_migration` execution on the plan's `from` hash and runs every
check the apply would run. It writes nothing. Each execution answers
`:would_migrate` (with the states the plan would drop and whether the
position is `compatible_at?` the new chart), `:would_refuse` (with the
refusal) or `:skipped`. The task previews both plans:

    dry run      blocks mapping alone: skipped 0, would_migrate 0, would_refuse 2; the plan: skipped 0, would_migrate 2, would_refuse 0

The plan made from the blocks mapping alone would refuse both loans with
`{:migration_refused, findings}`, and the findings name the unmapped
states each loan is standing in. That refusal is what the preview is for:
the same plan applied would have moved nothing. The completed plan would
move both.

The dry run is advice, not a lock. It holds no exclusion past each
execution's own check, and the apply checks everything again.

## 5. The apply

The same call without `dry_run:` moves each execution, one at a time and
in ascending id order. Each one moves whole or not at all, under its own
exclusion:

```elixir
Executions.migrate_batch(store, plan,
  from_machine: old.machine,
  to_machine: new.machine,
  serialization: {ExecutionLock, ExecutionLock}
)
```

    applied      migrated 2, parked 0, refused 0, skipped 0

`serialization:` is this app's own strategy, as in the first-workflow
guide, because its SQLite adapter offers no per-execution lock.

`on_failure:` defaults to `:refuse`. A loan the plan cannot move is
written nothing: it stays `:active` on the old chart and keeps waiting
there, and the report says why. `on_failure: :park` parks it instead, in
the `:needs_migration` quarantine, where it steps no further until it is
migrated or unparked (`Executions.unpark/3`). Parking is the only thing
"parked" means. This task parks nothing.

A batch is not one unit. An interrupted apply leaves the loans it reached
moved or refused and the rest untouched on the old chart, and calling it
again with the same plan carries on from there.

The whole call is one telemetry span,
`[:statifier_persistence, :execution, :migrate_batch, :start | :stop | :exception]`,
whose `:stop` carries the report's counts. Each moved execution also emits
the existing per-execution `[:statifier_persistence, :execution, :migrated]`
event. The dry run opens the span but emits no `:migrated` event.

## 6. The old chart, drained

`Executions.executions_on/2` counts the executions on a hash in each
stored status (`active`, `needs_migration`, `completed`, `failed`,
`cancelled`), plus `children`, the durable-child pins on it:

    drained      revision 1: active 0, needs_migration 0; revision 2: active 2, needs_migration 0
    timers       2 due-date timer(s) still scheduled, untouched by the move

Nothing is waiting on revision 1 any more. The two due-date jobs are
still scheduled with their original deadlines. When one fires, the
delivery rebuilds the chart from the hash the loan is on at that moment
(`StatifierExamples.FirstWorkflow.machine_for/2`), which is now revision
2's.

This count reads a chart's traffic. It is not a retirability test. The
retirement makes its own decision, in the next step.

## 7. Retiring the old chart

`Executions.retire_chart/4` tombstones a hash nothing still needs: it
keeps the row and nulls the chart's bytes. It refuses with
`{:error, {:pinned, counts}}` while anything is still on the chart,
whether an execution, a position, a durable child's pin or a count from a
pin source the host passes. It is irreversible.

Tombstoning is a capability of a store that supports it, such as Postgres
after the package's V07 migration. It needs the two chart blob columns to
be nullable, and V07 can only make them nullable on Postgres. On this
app's SQLite database they stay `NOT NULL`, so `StatifierExamples.Persistence`
declares no chart retirement, and the call refuses at open, before
anything is counted:

    retire       revision 1: :chart_retirement_unsupported; this store cannot tombstone a chart

The old chart stays registered, and that is what keeps the next step
possible.

## 8. Rollback is a reverse plan

A rollback goes through the same function, with a plan that runs the other
way. `Migration.plan/2` is called with the revisions swapped. The renamed
step's states map back by hand, as before. The `damaged` arm's two states
have no counterpart in revision 1 and hold no loan, so the plan drops them
on purpose (`drop:`). The two datamodel keys are removed:

    rollback     the reverse plan, revision 2 to 1: skipped 0, would_migrate 2, would_refuse 0, then migrated 2, parked 0, refused 0, skipped 0

A reverse plan works only while its target chart is not retired. A batch
whose `to` hash is tombstoned is refused whole with
`{:error, {:chart_retired, info}}`. On this database the old chart can
never be retired, so the rollback is always available. On a store that can
tombstone, retire a chart only after the host no longer wants a way back
to it.

A reverse plan moves every execution on the new chart, including any
created there after the forward batch. A host that wants only the moved
executions back reads the forward report's `results`, which has one entry
per execution.

## What the task leaves behind

Both loans are back on revision 1, and the task then cancels them
(`Executions.cancel/3`) so the next run starts from an empty chart:

    tidied       cancelled the 2 loan(s) this run opened

Their due-date jobs stay in the queue. If one fires, the delivery finds a
cancelled execution and discards it.
