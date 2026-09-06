# The hybrid fan-out, end to end Implementation Plan

## Overview

Build the Tier A hybrid fan-out in the examples app, end to end and live: a
document whose `core.map` runs over **ten chunk descriptors**, one bulk
data-plane handler per chunk writing per-row outcomes to the app's own table,
and **one promoted row** that gets a durable run of its own. The host wires
`StatifierPersistence.Driver.start_child_at/6` into `statifier_oban`'s
`:child_starter` seam and a canceller into the driver's `child_canceller:`
seam, and both aggregation policies - `all` and `first_error` - are proved
through the parent's own door with tests and screen captures. Bead: se-j87.

This is the live proof of the Tier A spine and the first place the boundary
rule is stated in the app's own words: **the chart orchestrates batches; the
data plane processes rows. A row gets its own run only when its processing
has to wait or branch on its own state.**

## Current State Analysis

The app is the reference embedder and already runs durable charts, durable
subcharts, durable timers and one asynchronous invocation. What exists:

- `lib/statifier_examples/charts/durable.ex` - the whole durable spine.
  `driver/1` (`:689`) builds `StatifierPersistence.Driver.new/3` with
  `dispatch:`, `effects:`, `invoke_types:`, `serialization:` and
  `chart_resolver:`. There is **no** `child_canceller:`.
  `dispatch/1` (`:882`) has three arms - subchart, async, synchronous -
  and no fan-out arm.
- `lib/statifier_examples/charts/async_calls.ex` - the working precedent for
  an asynchronous invocation: `async?/2` (`:153`) is read on both the
  executor's way in and the dispatch fun's way out, `consume/2` (`:238`)
  enqueues through `StatifierOban.Invoke.Handler.perform_start/3`, `config/0`
  (`:182`) builds the `StatifierOban.Config`, and the dispatch fun answers
  `:pending`.
- `lib/statifier_examples/persistence.ex` - the storage adapter. It answers
  `supports_metadata?/1` (`:169`) `true` and writes
  `list_runs_by_metadata/2` (`:190`) in Elixir over a whole-table scan with a
  private recursive `contains?/2` (`:206`) and a `validate_match!/1`
  (`:222`) guard. Its moduledoc says at `:92-95` that
  `supports_run_outcome?/1` and `list_run_states_by_metadata/2` are **not**
  exported because nothing here fans out yet. `StatifierPersistence.Driver.start_child_at/6`
  refuses a fan-out at open without both (`driver.ex:687-701`), so the
  example cannot run until they are.
- `lib/statifier_examples/charts.ex` - `invoke_types/0` (`:144`) and
  `invoke_handlers/0` (`:157`), the union of `SyncAdapter.invoke_types/0` and
  `StatifierBlocks.Runtime.Subchart`'s one type; `dispatch/3` (`:230`) routes
  and refuses the subchart type as `{:subchart_not_a_sync_call, _}`.
- `lib/statifier_examples/charts/sync_adapter.ex:42` - the one place a domain
  handler module is named.
- `lib/statifier_examples/signup.ex` - the signup domain, its three fixtures
  (`:64-68`) and its own loader. This is the domain that already carries
  durable subcharts (`signup_onboarding` -> `signup_wizard`), so it is the
  domain this example joins.
- App-owned tables: exactly one, `users`
  (`priv/repo/migrations/20260830210001_create_users.exs`,
  `lib/statifier_examples/signup/user.ex`,
  `lib/statifier_examples/signup/accounts.ex`).
- `test/statifier_examples/charts/durable_test.exs` - `async: false`, an
  explicit `Sandbox.checkout/1`, and `Oban.drain_queue/1` at `:394` and
  `:662`. `config/test.exs:13` sets `testing: :manual`, so jobs are inserted
  for real and executed only by an explicit drain.

Published dependencies (verified in `mix.lock` and in the worktree's `deps`):
statifier 2.5.0, statifier_blocks 0.19.0, statifier_oban 0.7.0,
statifier_persistence 0.7.1. No pins, no git refs, no version bump - this is
an app.

## Desired End State

`mix quality` is green, and:

1. `StatifierExamples.Persistence` exports and answers
   `supports_run_outcome?/1` (`true`) and `list_run_states_by_metadata/2`,
   both in Elixir on the grounds this adapter already wrote
   `list_runs_by_metadata/2` on - it issues none of the `jsonb` SQL the
   shipped Ecto adapter refuses off Postgres.
2. Three new shipped fixtures exist and compile:
   `signup_bulk_invites` (`on: "all"`), `signup_bulk_invites_strict`
   (`on: "first_error"`) and the chunk child `signup_invite_chunk`.
3. `myapp:process_rows` is a registered bulk handler that writes one
   `invite_outcomes` row per invitee in its chunk, idempotently, and starts a
   run of the signup wizard for the one row that needs chart semantics.
4. `StatifierExamples.Charts.FanOut` implements
   `StatifierOban.Invoke.Handler` (returning `{:fan_out, items}`),
   `StatifierOban.Invoke.ChildStarter` (delegating to
   `Driver.start_child_at/6`), and supplies the `child_canceller:` fun that
   calls `StatifierOban.Invoke.FanOut.cancel_unstarted/3`.
5. A durable run of `signup_bulk_invites` fans out to ten chunk children,
   every child completes, and the parent's `results` holds a dense,
   index-ordered ten-entry list assembled through the parent's own door.
6. A durable run of `signup_bulk_invites_strict` whose first executed chunk
   refuses cancels its nine unstarted siblings: their start jobs read
   `cancelled` and their indices read `"cancelled"` in the same dense list.
7. `README.md` carries a fan-out section stating the boundary rule in the
   repo's own words, and the module table gains its row.
8. Screen captures of both policies exist under the campaign's captures
   directory.

### Key Discoveries:

- `core.map` emits every `<param>` as a **quoted literal**
  (`deps/statifier_blocks/lib/statifier_blocks/core/map.ex:429-451`), so the
  handler receives `%{"items" => "chunks", "chart" => "bdoc_...", "collect"
  => "results", "on" => "all"}` - `items` is a **path**, not the list. The
  handler evaluates it. `statifier_oban`'s README example at `:296-299`
  reads `invoke.params["items"]` as if it were already the list; that is a
  documentation looseness to report upstream, not something to copy.
- `%Statifier.Effect.Invoke{}` carries no datamodel
  (`deps/statifier/lib/statifier/effect/invoke.ex:61-90`), and
  `StatifierPersistence.Driver`'s `dispatch_context` is only
  `%{run_id, content_hash, invoke_id, invoke}` (`driver.ex:205-210`). The
  path is therefore evaluated **inside the fan-out job**, from the parent
  run's persisted position. The chain is four steps and not three -
  `Storage.fetch_run/2` for the record, `Durable`'s private `chart_for/1`
  (`durable.ex:651`) for the recipe, **`Statifier.compile/1` on the
  emitted SCXML** for the `Machine.t()`, and only then
  `Storage.load_run_position/3`
  (`deps/statifier_persistence/lib/statifier_persistence/storage.ex:561-575`)
  for the `MachineState` whose `datamodel` field is the answer. Every
  existing caller inserts that compile step (`durable.ex:220`, `:250`),
  and `chart_for/1` is private, so `Durable` gains one public function -
  `machine_state/1` - wrapping the whole chain, rather than `FanOut`
  reaching into a sibling's privates or re-deriving the recipe. That
  function is new surface this bead forces and is reported under
  Provenance.
- A child's datamodel is seeded by name-matching:
  `Statifier.Session.Invocations.seed_datamodel/2`
  (`deps/statifier/lib/statifier/session/invocations.ex:292-319`) keeps only
  the `params` keys that name a top-level `<data>` id in the child document.
  The chunk document must therefore declare `chunk`, and the starter must
  hand `params: %{"chunk" => descriptor}`.
- The child's chart comes off the **resolved effect**, never off the
  driver's machine (`driver.ex:606-608`, `:1314-1321`), so the starter sets
  `content:` to the child SCXML exactly as
  `StatifierBlocks.Runtime.DurableSubchart.dispatch/4` does
  (`durable_subchart.ex:191-199`). `StatifierExamples.Charts.Subchart.child_compile/1`
  is the one child recipe, and `Durable`'s `chart_resolver:` already walks
  both compiles of every shipped fixture - which is why the two parent
  documents must be **shipped fixtures** and not test-built ones.
- `StatifierOban.Config` gains `:child_starter` and `:max_fan_out` (default
  `1_000`) (`deps/statifier_oban/lib/statifier_oban/config.ex:117-126`).
  The cap is runtime-only; `core.map` validates nothing about N
  (`core/map.ex:24-31`).
- The empty fan-out is **refused** by `StatifierOban.Invoke.FanOut`
  (`fan_out.ex:190-198`), and sb-kha0 owns the record question. Campaign
  amendment RQ-031-2 says the example must not depend on N = 0.
- `first_error` cancels in two halves: live children through
  `StatifierPersistence.Runs.cascade_cancel/3` and unstarted ones through
  the driver's `child_canceller:` (`driver.ex:292-296`, `:913-928`), which
  the host points at `StatifierOban.Invoke.FanOut.cancel_unstarted/3`
  (`fan_out.ex:181-185`). Both read `"cancelled"` at their index in the
  assembled list (`driver.ex:986-996`).
- `core.assign`'s `value` is source text with **no whitespace**
  (`deps/statifier_blocks/lib/statifier_blocks/core/assign.ex:11-27`), and
  predicator parses list literals (`parser.ex:1746`), so
  `['su-c01','su-c02',...]` is a legal authored literal and is how the
  example seeds its ten descriptors.
- Campaign ruling D31-9 / decisions.md D14 bind this bead: descriptors
  never row payloads, no slices, cap runtime-only, `first_error` cancels.
  A worker who thinks a ruling is wrong reports it rather than re-deciding.

## What We're NOT Doing

- **No version bump and no release.** `statifier_examples` is an app; its
  `CLAUDE.md` authority table forbids both outright.
- **Not deciding the empty fan-out.** N = 0 is refused upstream and sb-kha0
  owns the record question; nothing here depends on N = 0 (RQ-031-2).
- **Not building capture's authoring surface** (sb-th97). The two parent
  documents author `collect` directly.
- **Not implementing the four deferred `core.map` fields** - `item_as`,
  `index_as`, `max_concurrency`, `params` (sb ADR-0009 d4 Note). The
  descriptor reaches the child through the starter's `params`, which is the
  seeding path the package already ships.
- **Not honouring `max_concurrency`.** Ruling R31-11: no slices at Tier A;
  the queue's limit is the bound.
- **Not adding a `/runs` page.** Captures go through the existing
  `/editor?doc=...&run=...` drawer, which is the app's only run surface.
- **Not working around anything upstream.** A defect in sb, sob or sp is
  reported with `file:line`, never patched app-side - this app is the
  reference embedder and a local workaround hides the finding.
- **Not widening `Subchart.references/1`** to see `core.map`'s `chart`.
  The `subcharts` metadata pin is host provenance for `core.subchart`;
  extending it to the map is a separate decision with its own record, and
  chart resolution here is by content hash and does not need it. Recorded
  here so a reader does not read the omission as an oversight.

## Implementation Approach

Follow the shape the app already proved for an asynchronous invocation, one
layer up. The parent's step never creates ten runs: the executor stores one
fan-out job for the `statifier_blocks:map` effect and the dispatch fun
answers `:pending`, so the parent rests durably with the invocation live. The
fan-out job evaluates the descriptor path from the parent's persisted
datamodel, hands the list to `statifier_oban`, and that package enqueues ten
start jobs. Each start job calls the host's `start_child/5`, which resolves
the chunk document, seeds its descriptor, and calls
`Driver.start_child_at/6`. Each chunk child runs one bulk call and
terminates; `statifier_persistence` settles the tenth and answers the parent
once, with the dense list.

Promotion takes D14's first door - **the host's existing entry door**. The
bulk handler starts an ordinary durable run of the signup wizard for the one
invitee whose processing has to wait on a person, records its run id on that
row, and returns it in the chunk's donedata. That keeps the chunk chart one
block, keeps the promoted run openable by URL like any other, and states the
boundary rule in code rather than only in prose.

---

## Phase 1: The adapter's fan-out capabilities

### Overview

Export the two callbacks `Driver.start_child_at/6` checks at open, so a
fan-out is startable at all. Nothing else in the app changes behaviour: the
callbacks are optional and previously absent.

### Changes Required:

#### 1. The storage adapter
**File**: `lib/statifier_examples/persistence.ex`
**Changes**: add `supports_run_outcome?/1` answering `true`, and
`list_run_states_by_metadata/2` written in Elixir beside
`list_runs_by_metadata/2`, reusing the same `validate_match!/1` guard and
`contains?/2` test and projecting rather than materialising. Replace the
moduledoc paragraph at `:92-95` that says this adapter does not export them.

```elixir
@impl StatifierPersistence.Storage.Adapter
@spec supports_run_outcome?(Adapter.opts()) :: boolean()
def supports_run_outcome?(_opts), do: true

@impl StatifierPersistence.Storage.Adapter
@spec list_run_states_by_metadata(Adapter.opts(), Adapter.metadata()) ::
        {:ok, [Adapter.run_state()]} | {:error, Adapter.error()}
def list_run_states_by_metadata(_opts, match) do
  validate_match!(match)

  states =
    StatifierExamples.Repo.all(
      from(r in __MODULE__.Run, select: {r.run_id, r.status, r.metadata})
    )
    |> Enum.filter(fn {_id, _status, metadata} -> contains?(metadata || %{}, match) end)
    |> Enum.map(fn {run_id, status, metadata} ->
      %{run_id: run_id, status: status(status), child_index: child_index(metadata)}
    end)

  {:ok, states}
end
```

`child_index/1` reads
`metadata[StatifierPersistence.Run.Linkage.reserved_key()]["child_index"]`
and answers `nil` for a matched run carrying no linkage;
`status/1` normalises the stored column to the
`:active | :completed | :failed | :cancelled` atom the projection's type
names.

#### 2. Tests
**File**: `test/statifier_examples/persistence_test.exs`
**Changes**: a test that the two callbacks are exported and that the
projection answers `run_id`, `status` and `child_index` for runs carrying a
fan-out linkage and `child_index: nil` for one that does not; a test that an
empty or non-string-keyed match raises `ArgumentError`, matching
`list_runs_by_metadata/2`'s refusal. Each carries its `# Sabotage:` line.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (`mix quality`, bare, read in full)
- [ ] `Storage.run_outcome_supported?/1` and `Storage.run_states_supported?/1`
      both answer `true` for a store opened on `StatifierExamples.Persistence`
- [ ] The existing 264 tests still pass

#### Manual Verification:
- [ ] Nothing in the durable-subchart walkthrough behaves differently

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead
of blocking here.

---

## Phase 2: The app's own per-row table

### Overview

The data plane's destination. One app-owned table, written by the bulk
handler, keyed so an at-least-once redelivery records one outcome per row
rather than two.

### Changes Required:

#### 1. Migration
**File**: `priv/repo/migrations/20260905180001_create_invite_outcomes.exs`
**Changes**: a new table following `create_users`' shape - `use
Ecto.Migration`, `def change`, `timestamps(type: :utc_datetime_usec)`, a real
`@moduledoc` saying why the table exists (the data plane's rows are the
host's, not the chart's).

```elixir
create table(:invite_outcomes) do
  add :chunk_id, :string, null: false
  add :email, :string, null: false
  add :status, :string, null: false
  add :run_id, :string, null: false
  add :promoted_run_id, :string
  timestamps(type: :utc_datetime_usec)
end

create unique_index(:invite_outcomes, [:chunk_id, :email])
```

#### 2. Schema and context
**Files**: `lib/statifier_examples/signup/invite_outcome.ex`,
`lib/statifier_examples/signup/invites.ex`
**Changes**: an `Ecto.Schema` with a typed `@type t` and `changeset/2`, and a
context exposing `record_rows/3` (an upsert-per-row on the
`{chunk_id, email}` conflict target, so a replayed chunk is one write set,
not two), `for_chunk/1` and `count_for_run/1`.

#### 3. Tests
**File**: `test/statifier_examples/signup/invites_test.exs`
**Changes**: rows are written; recording the same chunk twice leaves the same
row count and the same rows (the at-least-once property); `for_chunk/1` reads
back in a stable order. Each carries its `# Sabotage:` line.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes
- [ ] `mix ecto.reset` ends with the new migration in `schema_migrations`
      and an `invite_outcomes` table with the unique index
- [ ] `mix ecto.migrate --to <previous>` then `mix ecto.migrate` runs the new
      migration alone

#### Manual Verification:
- [ ] The table's columns read as the host's own data, with nothing the
      chart owns duplicated into them

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead
of blocking here.

---

## Phase 3: The documents, the bulk handler, the fan-out wiring, and `all`

### Overview

The example itself, and the first policy proved end to end. This phase is one
phase and not four because none of its parts is separately gate-verifiable: a
fixture naming an unregistered invoke type is a compile finding, a handler
nothing dispatches is uncovered code, and a `child_starter` with no fan-out
to start proves nothing.

### Changes Required:

#### 1. The chunk child document
**File**: `priv/fixtures/signup_invite_chunk.json`
**Changes**: id `bdoc_su_invite_chunk`, `metadata.domain` `signup`,
`datamodel` declaring `chunk` (the descriptor the starter seeds) and
`outcome`. Root `core.sequence` holding one `core.invoke`
`blk_ic_process` - `invoke_type` `myapp:process_rows`, `params`
`chunk=chunk`, `assign_to` `outcome`. One block, because one chunk is one
bulk call.

#### 2. The two parent documents
**Files**: `priv/fixtures/signup_bulk_invites.json`,
`priv/fixtures/signup_bulk_invites_strict.json`
**Changes**: ids `bdoc_su_bulk_invites_demo` and
`bdoc_su_bulk_invites_strict_demo`; `datamodel` declaring `chunks` and
`results`. Root `core.sequence`:

- `core.assign` `blk_bi_chunks_seed`: `path` `chunks`, `value`
  `['su-c01','su-c02','su-c03','su-c04','su-c05','su-c06','su-c07','su-c08','su-c09','su-c10']`
  (no whitespace, which is what `core.assign` requires). A real host's upload
  pipeline yields these; the example authors them so the document is
  runnable from the Run button.
- `core.map` `blk_bi_chunks`: `items` `chunks`, `chart`
  `bdoc_su_invite_chunk`, `collect` `results`, `on` `all` in the first
  document and `first_error` in the second; `on_done` holding a
  `myapp.signup_step` confirm block, `on_error` holding a `myapp.notify`.

The strict document's seed list replaces `su-c04` with `su-cXX`, the
descriptor the handler refuses - so the document that demonstrates
`first_error` contains the thing that fails, rather than a test reaching in
to break a shared one.

#### 3. The bulk data-plane handler and promotion
**File**: `lib/statifier_examples/signup/handlers.ex` (new `myapp:process_rows`
clause), `lib/statifier_examples/signup/invites.ex` (row derivation)
**Changes**: `handle("myapp:process_rows", %{"chunk" => chunk_id}, %{run_id: run_id})`
derives the chunk's invitee rows deterministically from the descriptor
(fictional `@example.com` addresses), writes them through
`Invites.record_rows/3`, promotes the one row whose processing has to wait on
a person by starting an ordinary durable run of the signup wizard through the
host's existing entry door, and answers a **summary** donedata -
`%{"chunk" => chunk_id, "rows" => n, "promoted" => run_id_or_nil}` - never
the rows themselves. An unknown descriptor answers `{:error, ...}`, which is
what the strict document's `su-cXX` reaches.

#### 4. The fan-out module
**File**: `lib/statifier_examples/charts/fan_out.ex`
**Changes**: one module carrying the three host halves, written against
`AsyncCalls`' shape:

- `fan_out?/1` - whether an invoke type is `StatifierBlocks.Core.Map`'s
  constant, read on the executor's way in and the dispatch fun's way out, one
  predicate for both decisions for `AsyncCalls.async?/2`'s reason.
- `use StatifierOban.Invoke.Handler`; `config/0` returns a
  `StatifierOban.Config` adding `child_starter: __MODULE__` and leaving
  `max_fan_out` at the package default; `run/2` evaluates
  `invoke.params["items"]` against the parent run's persisted datamodel and
  returns `{:fan_out, descriptors}`.
- `@behaviour StatifierOban.Invoke.ChildStarter`; `start_child/5` resolves
  `invoke.params["chart"]` through `StatifierExamples.Charts.Subchart`,
  compiles it with `Subchart.child_compile/1`, builds the resolved effect as
  `%{invoke | content: scxml, params: %{"chunk" => Enum.at(descriptors, index)}}`
  and calls `StatifierPersistence.Driver.start_child_at/6`, mapping
  `{:refused, reason}` to `{:error, reason}` so an environment-shaped refusal
  retries the start job.
- `canceller/0` - the `child_canceller:` fun, three-arity, calling
  `StatifierOban.Invoke.FanOut.cancel_unstarted/3` and answering `:ok`.
- `consume/2` - claims `{:invoke, %Invoke{}}` for the map type through
  `Handler.perform_start/3` and passes `{:cancel_invoke, _}` to
  `Handler.perform_cancel/3`, exactly as `AsyncCalls.consume/2` does.

Evaluating the path reads the parent's own persisted position through the
new public `Durable.machine_state/1`, which is the four-step chain the Key
Discoveries name - record, recipe, `Statifier.compile/1`, position - and then
walks the dotted path over the string-keyed `datamodel` map. A path naming
nothing is `{:error, {:items_undefined, path}}`, which fails the invocation
on its ordinary error route rather than fanning out over a non-list.

Two facts this wiring rests on, stated so they read as decisions rather than
accidents. `canceller/0`'s wrapper **ignores** the `unstarted_indices`
argument the driver hands it: `FanOut.cancel_unstarted/3` cancels by
`{scope, invoke_id}` across every index and generation
(`fan_out.ex:265-273`), so the list is information the driver has and this
door does not need. And `FanOut.config/0` reuses `AsyncCalls.queue/0`
because `config/config.exs` defines exactly one invoke queue; giving a
fan-out its own queue is a deployment change and not this bead's.

#### 5. Wiring
**Files**: `lib/statifier_examples/charts/durable.ex`,
`lib/statifier_examples/charts.ex`,
`lib/statifier_examples/charts/sync_adapter.ex`,
`lib/statifier_examples/signup.ex`, `lib/statifier_examples/charts/fixture.ex`
(fixture list only)
**Changes**:
- `Durable.driver/1` gains `child_canceller: FanOut.canceller()`.
- `Durable.dispatch/1` gains a fan-out arm ahead of the async arm, answering
  `:pending` through the existing `pending/3` note.
- `Durable.executor/1` hands every effect to `FanOut.consume/2` beside
  `Timers` and `AsyncCalls`.
- `Charts.invoke_types/0` and `invoke_handlers/0` gain
  `StatifierBlocks.Core.Map.invoke_type/0`; `Charts.dispatch/3` refuses it
  the way it refuses the subchart type, with its own `reason/1` clause.
- `Signup`'s fixture list gains the three new documents.

#### 6. Tests
**Files**: `test/statifier_examples/charts/fan_out_test.exs`,
`test/statifier_examples/signup/handlers_test.exs`,
`test/statifier_examples/charts/fixture_datamodel_test.exs` (as needed)
**Changes**: the three documents decode and compile; the map's invoke type is
registered and refuses a synchronous dispatch; the bulk handler writes rows
idempotently and promotes exactly one; and the end-to-end `all` test:

1. `Durable.start/4` the `signup_bulk_invites` document.
2. Assert the parent rests with the invocation live and exactly one fan-out
   job stored.
3. `Oban.drain_queue(queue: AsyncCalls.queue())` - the fan-out job runs and
   enqueues ten start jobs.
4. Drain again - the ten children are created, each runs its bulk call and
   terminates, and the tenth settlement answers the parent.
5. Assert `results` is a dense ten-entry list, index-ordered, every entry
   `"status" => "completed"`; assert `invite_outcomes` holds the full row
   set; assert exactly one row carries a `promoted_run_id` and that
   `Durable.resume/1` opens it.

Each new test asserting `lib/` behaviour carries its `# Sabotage:` line.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes
- [ ] The `all` end-to-end test asserts a dense, index-ordered ten-entry
      `results` list with every entry `"completed"`
- [ ] `invite_outcomes` holds one row per invitee across all ten chunks, and
      exactly one carries a `promoted_run_id`
- [ ] The promoted run resumes through `Durable.resume/1`

#### Manual Verification:
- [ ] The document reads as an author would write it - one map block over a
      short list of descriptors, and no row data anywhere in it
- [ ] The Runs feed narrates the fan-out legibly

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead
of blocking here.

---

## Phase 4: `first_error`, and the cancel of the unstarted

### Overview

The second policy, and the half of it that only a host can prove: an index
whose start job has not run has no run record to cancel, so the driver's
`child_canceller:` is what reaches it.

### Changes Required:

#### 1. Test
**File**: `test/statifier_examples/charts/fan_out_test.exs`
**Changes**: the `first_error` end-to-end test, which controls execution
order rather than draining blind:

1. `Durable.start/4` the `signup_bulk_invites_strict` document.
2. Drain once - the fan-out job enqueues ten start jobs, all `available`.
3. Execute **only** the start job whose `args["index"]` is the refused
   descriptor's index, by loading its stored `%Oban.Job{}` row and calling
   `StatifierOban.Invoke.ChildStartWorker.perform/1` on it. That does not
   transition the executed row through Oban's own state machine - a real
   queue run would leave it `completed` and therefore outside
   `cancel_unstarted/3`'s match - so the assertions below name the **nine
   sibling indices** explicitly rather than counting cancelled rows, and
   the test says in a comment that the executed row's own state is an
   artifact of driving the worker directly.
4. That child fails; settlement reads `policy: :first_error`, cascades over
   the started children (none) and calls the host's canceller for the nine
   unstarted indices.
5. Assert the start job of each of the nine sibling indices is `cancelled`
   in the jobs table, matched by `args["index"]`; assert a second
   `Oban.drain_queue/1` runs nothing; assert `results` is a dense ten-entry
   list whose refused index reads `"failed"` and whose other nine read
   `"cancelled"`; assert `invite_outcomes` holds no rows for the nine.

Carries its `# Sabotage:` line - removing `child_canceller:` from the driver
leaves the nine start jobs `available` and the assertion red.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes
- [ ] The `first_error` test asserts the nine sibling indices' start jobs
      are each in state `cancelled`, matched by `args["index"]`
- [ ] The assembled list is dense and index-ordered with one `"failed"` and
      nine `"cancelled"`
- [ ] No `invite_outcomes` rows exist for the cancelled indices

#### Manual Verification:
- [ ] The two policies differ in the document and nowhere else - no host
      code branches on which one is running

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead
of blocking here.

---

## Phase 5: The README, and the captures

### Overview

State the boundary rule where a reader of this app meets it, and take the
screen captures that show both policies running.

### Changes Required:

#### 1. README
**File**: `README.md`
**Changes**: a new `###` section under `## Durable runs, and picking one up
after a kill -9`, placed after "A chart that embeds another chart, durably"
(`:269-325`) and before the abandonment-reminder section (`:326`). It states
the boundary rule in this repo's own words - the chart orchestrates batches,
the data plane processes rows, and a row gets its own run only when its
processing has to wait or branch on its own state - names the three
documents and the two policies, says that `items` are descriptors and why
(the parent's datamodel is serialized on every persisted step), and names the
three host seams the example wires: the `child_starter`, the
`child_canceller`, and the two adapter callbacks that make a fan-out
startable at all. The module table at `:389-396` gains its row.

#### 2. Captures
**Files**: `.claude/fleet/journal/031-artifacts/captures/se-j87-*.png`
**Changes**: with the dev server on a private port (`PORT=<private>`, never
8642-8645) and `locks/chrome/owner` claimed: the `signup_bulk_invites`
document in the editor, its run's Runs feed after the fan-out settles, one
chunk child open as a run of its own, the promoted signup-wizard run open as
a run of its own, and the strict document's run showing the cancelled
siblings. Any state the emulated mouse cannot reach is driven from page JS
and the script is cited in the evidence.

### Success Criteria:

#### Automated Verification:
- [ ] Full quality gate passes (the README is not gated, but the phase's
      commit is)
- [ ] The capture files exist at the named paths
- [ ] `mix phx.server` on the private port answers `/` and
      `/editor?doc=signup_bulk_invites` with 200

#### Manual Verification:
- [ ] The boundary paragraph is this repo's own words, not a quotation of a
      private document
- [ ] The captures show what the prose claims

**Implementation Note**: Use the project's loop gate between edits while
iterating; run the full gate as the phase gate. In interactive execution,
pause here for the human to confirm the manual testing before moving to the
next phase. In looped (`--loop`) execution, this phase's Automated
Verification gates advancement automatically (via `/wurk:commit --auto`), and
Manual Verification items are deferred and surfaced once at the end instead
of blocking here.

---

## Testing Strategy

### Unit Tests:
- `test/statifier_examples/persistence_test.exs` - the two new adapter
  callbacks, their projection shape, and their refusal on a bad match.
- `test/statifier_examples/signup/invites_test.exs` - the row table's
  at-least-once property.
- `test/statifier_examples/signup/handlers_test.exs` - the bulk handler's
  summary donedata, its promotion, and its refusal of an unknown descriptor.
- `test/statifier_examples/charts/fan_out_test.exs` - the fixtures compile,
  the invoke type is registered and is not a synchronous call, the path
  evaluator answers a list and refuses an undeclared path, and the two
  end-to-end policy tests.
- Every new test asserting `lib/` behaviour is sabotaged before it is
  trusted, with the mutation recorded in a `# Sabotage:` line above it, as
  this repo's conventions require.

### Manual Testing Steps:
1. `PORT=<private> mix phx.server`, open
   `/editor?doc=signup_bulk_invites`, press Run, and watch the Runs feed
   reach a settled ten-entry result.
2. Open one chunk child by its run id and confirm it is an ordinary run.
3. Open the promoted signup-wizard run by its run id and drive a step.
4. Open `/editor?doc=signup_bulk_invites_strict`, press Run, and confirm the
   siblings read cancelled.

## References

- Bead: `se-j87` (depends on `se-eoj`, `se-i4v`, both landed)
- Campaign rulings: `D31-9` (cap runtime-only, child set derived, no slices,
  `first_error` cancels), `RQ-031-2` (empty fan-out refused), `RQ-031-4`
  (the sob seam is `ChildStarter.start_child/5`), `RQ-031-6` (this app's
  adapter answers `supports_metadata?/1` true because its metadata queries
  are Elixir)
- The boundary rule: the umbrella's `docs/decisions.md` D14 (private - read,
  never quoted into this repo)
- `deps/statifier_blocks/lib/statifier_blocks/core/map.ex` - the block type
- `deps/statifier_oban/lib/statifier_oban/invoke/{fan_out,child_starter,child_start_worker}.ex`
- `deps/statifier_persistence/lib/statifier_persistence/driver.ex:635-651`,
  `:687-701`, `:875-1011` - start, refusals, settlement and assembly
- Similar implementation: `lib/statifier_examples/charts/async_calls.ex:120-290`
  (the asynchronous-invocation shape this follows) and
  `lib/statifier_examples/charts/subchart.ex:100-215` (the child recipe)
