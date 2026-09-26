# The first workflow, routed

The first-workflow guide opens its execution by hand. This one lets
`statifier_router` open it: every event arrives from a source, a binding
routes it to the one execution its key names, creating that execution when
the key is new, and a route hands the finished execution's answer to a sink.
It publishes the document through the publish-time checks with the router's
contracts in the gate, places the router's tables with a column of this
app's own, routes three scans of one parcel, and runs the router's two
reapers on this app's scheduler. Every step is code in this app, and one
command runs them all:

    mix ecto.migrate
    mix statifier_examples.first_workflow_routed

The command prints one line per step and stops with a non-zero exit, naming
the step, if any of them does not hold.

## The pins

The recipe is written and checked against these releases, which are what
`mix.exs` requires and `mix.lock` resolves:

| Package | Version | What the recipe uses it for |
|---|---|---|
| `statifier_router` | 0.6.0 | the binding, the delivery, the address and dedupe tables, the route, the reapers, the migration's `:leading_columns`, `:on_create` and `:on_step` |
| `statifier_persistence` | 0.19.0 | the chart registry, the execution, the input log, `ended_at` |
| `statifier_blocks` | 0.35.0 | the document and the compile |
| `statifier` | 2.9.0 | compiling the chart and running it |

`statifier_router` 0.6.0 requires `statifier ~> 2.9` and
`statifier_persistence ~> 0.18`, which is what moved those two with it. The
jobs run on this app's own Oban. The first line the command prints names
the versions it actually loaded.

## The workflow

The document is `priv/first_workflow/parcel_route.json`. A parcel travels
from a depot to a doorstep, and is scanned on the way:

1. **The depot scans it out.** A `core.await` holds until the first
   `parcel.scanned` arrives.
2. **The courier scans it at the door.** A second `core.await` holds for
   the next one.

When both scans are in, the execution completes. The document declares
what it accepts: `"accepts": ["parcel.scanned"]`.

Every scan comes from a source called `parcel_scans`, as a plain map:

```elixir
%{
  scope: "depot_eastside",
  source: "parcel_scans",
  message_id: "parcel-4f4ddcfc-depot",
  data: %{"kind" => "scan", "parcel_id" => "parcel-4f4ddcfc", "at" => "depot"}
}
```

The scope is opaque to the router; here it is the depot. The message id is
the scan's own, so the same scan handed over twice is the same message.

The code is `StatifierExamples.RoutedWorkflow`. The sections below follow
its `run/1`, one step at a time.

## 1. Place the router's tables, with a column of your own

The router keeps four tables: the address table, the dedupe table and the
routing ledger from its migration V01, and the subscription table from V02.
The host runs them in a migration of its own, which delegates to
`StatifierRouter.Migrations`. This app's is
`priv/repo/migrations/20260925120001_add_statifier_router.exs`:

```elixir
@opts [leading_columns: [depot_id: {:text, null: true}]]

def up, do: StatifierRouter.Migrations.up(@opts)
def down, do: StatifierRouter.Migrations.down(@opts)
```

`:leading_columns` puts `depot_id` immediately after `id`, at ordinal
position 2, in every table either version creates. It is for a host that
wants a column of its own at a fixed position on every table: an `ALTER
TABLE` afterwards would put it last. Three things follow from it:

- **It applies to a fresh create.** A table that already exists is not
  re-laid out.
- **The column is nullable here.** The package's schemas do not declare it,
  so every row the router writes leaves it to its default, `NULL` until a
  later migration of your own gives it one.
- **`down/1` takes the same list and ignores it**, so one list serves both
  directions.

Every statement in V01 and V02 runs on SQLite. The recipe reads each
table's columns back and checks that `depot_id` is second.

## 2. The router configuration

`StatifierExamples.RoutedWorkflow.config/0` builds the one
`StatifierRouter.Config` every step uses:

```elixir
StatifierRouter.Config.new(
  repo: StatifierExamples.Repo,
  store: StatifierExamples.FirstWorkflow.store(),
  executor: &StatifierExamples.RoutedWorkflow.execute/2,
  resolver: StatifierExamples.RoutedWorkflow.PublishedCharts,
  chart_resolver: &StatifierExamples.RoutedWorkflow.PublishedCharts.chart/1,
  on_create: StatifierExamples.RoutedWorkflow.Stepper,
  on_step: StatifierExamples.RoutedWorkflow.Stepper,
  bindings: [binding],
  send_type: "myapp:route",
  route_adapters: %{
    "doorstep_notices" => {StatifierExamples.RoutedWorkflow.DoorstepRoute, %{queue: :parcel_notices}}
  },
  on_complete: "doorstep_notices"
)
```

**The binding.** One binding routes every scan:

```elixir
%{
  id: "parcel_scans",
  source: "parcel_scans",
  match: ~s(event.kind == "scan"),
  key: "event.parcel_id",
  document: "bdoc_parcel_route",
  event: "parcel.scanned",
  data: ["parcel_id", "at"],
  dedupe: %{by: :message_id, horizon_ms: 1_000}
}
```

`match` and `key` are predicator programs over the event's data. Every scan
of one parcel has the same key, so every scan of one parcel reaches the
same execution. `data` is what travels into the chart event. The horizon is
how long a message id is remembered; the recipe says one second so the
command finishes quickly, and a real host would keep days.

**The store** is the one the first-workflow recipe uses, over this app's
repo. It has to be built over the configuration's own `:repo`, so the
router's writes and the execution's writes commit in one transaction.

**The executor** is the router's own handler,
`StatifierRouter.SendHandler.handle_effect/3`, which answers a `<send>` of
the router's type and passes every other effect. This chart sends nothing,
so it passes everything.

**The resolver and the chart resolver** say which chart an execution runs;
step 4 covers them.

**`:on_create` and `:on_step`** are the router's calls into
`StatifierPersistence.Executions.create/4` and `step/5`, made by the host
instead. The router passes no `serialization:`, so each call takes the
default, the storage adapter's per-execution lock. This app's SQLite
adapter offers none, and the default refuses with
`{:error, {:serialization, :not_supported}}`.
`StatifierExamples.RoutedWorkflow.Stepper` makes the same two calls with
this app's own strategy added (`StatifierExamples.Charts.ExecutionLock`),
and answers what they answer. A host on Postgres takes the default and sets
neither.

**The route.** `doorstep_notices` is the one registered route, and
`:on_complete` names it: a delivery that finishes an execution hands the
finished execution's donedata to it. Step 7 covers it.

## 3. Publish it through the publish-time checks

The document goes through `StatifierExamples.Publish.check/2`, the same
seven checks the first-workflow guide describes, with this configuration as
the host's router configuration. The router's send type is the one send type
this host registers, and the contracts lookup answers the document's own
`accepts` list.

This is where `StatifierRouter.Contracts.check/3` earns its place: it
judges every binding's event against what the receiving document accepts.
`parcel.scanned` is in `accepts`, so the check passes. The recipe then
checks the same document against a binding that names `parcel.lost` and
confirms the publish is refused at the `:contracts` stage, with the finding
anchored on the binding. A binding that would hand a chart an event it
never takes is caught before any event is routed.

## 4. Register the chart and let the resolver find it

The chart an execution runs is compiled once more for running, with
`terminate: true`, and `StatifierPersistence.Storage.save_chart/3` stores it
under its content hash, as the first-workflow guide's step 3 does.

The router keeps no publish store, so which chart a new execution starts on
is the host's answer. `StatifierExamples.RoutedWorkflow.PublishedCharts` is
this app's:

- `resolve/2` takes the scope and the document and answers
  `{content_hash, machine}`. This app has no table of published revisions,
  so it compiles the one document it knows and answers it only when the
  registry already holds that chart. Any other document is
  `{:error, :not_published}`, and the router creates nothing.
- `chart/1` takes a content hash and rebuilds the chart from the registry.
  An execution that already exists keeps the chart it started on, and the
  router finds it this way, never through `resolve/2`.

The recipe checks that the resolver answers the registered hash for
`bdoc_parcel_route` and refuses a document that was never registered.

## 5. The depot scan opens the execution

`StatifierRouter.route/3` routes the depot scan. The binding matches, the
key is the parcel id, and the address `(scope, document, key)` has no row
yet, so in one transaction the delivery claims the message id, writes the
address row with a new execution id, asks the resolver for the chart,
creates the execution through the stepper, and steps the scan into it. The
answer is one outcome per binding:

    {:ok, [{:created_and_delivered, "parcel_scans", execution_id}]}

The execution is `:active`, resting in the second await.

## 6. The same scan again

The source hands the depot scan over a second time, with the same message
id. The claim finds the pair `(binding, message_id)` already handled inside
its horizon:

    {:ok, [{:duplicate, "parcel_scans"}]}

The ledger records the duplicate, and nothing else happens: no address row
is read and the execution is not stepped. The recipe checks that the
execution's input log still holds one scan.

## 7. The doorstep scan finishes the parcel

The doorstep scan has the same key, so the delivery finds the address row
and steps the execution it names:

    {:ok, [{:delivered, "parcel_scans", execution_id}]}

The second await takes the scan and the execution completes. Because this
delivery is the one that finished it, the router hands a `done.execution`
event to the `:on_complete` route, inside the same transaction.

`StatifierExamples.RoutedWorkflow.DoorstepRoute` is that route. A route runs
under the execution's serialization, so it may only hand off durably: it
inserts a `StatifierExamples.RoutedWorkflow.DoorstepNotice` job on this
app's Oban. The job is written through the same repo, so it commits or
rolls back with the delivery. The router hands the route an idempotency
key, and the job is unique on it, so a redriven delivery queues no second
notice. The recipe checks that one notice was queued for the execution and
that it ran.

`:on_complete` fires on the delivery that finishes the execution and on no
other: donedata exists only in the answer of the call that produced it.

## 8. A late scan

A third scan arrives after the parcel is delivered. The address row names
an execution that has ended, so nothing is stepped:

    {:ok, [{:dropped, "parcel_scans", :finished}]}

The delivery stamps the address row's `terminal_seen_at`, which is what the
address reaper counts from. The routing ledger now holds one row per
attempt, in order:

    created_and_delivered, duplicate, delivered, dropped: finished

The recipe checks those four rows, and checks that none of them carries a
`depot_id`: the router never writes the host's column.

## 9. The reapers, on the host's scheduler

The router runs no process. The rows that outlive their use are removed by
two plain functions the host calls on its own schedule:

- `StatifierRouter.Dedupe.reap/2` deletes every dedupe row whose horizon has
  passed. An expired row already counts as absent when a message is
  claimed, so this only reclaims space.
- `StatifierRouter.Addresses.reap/3` deletes the address rows whose
  execution finished longer ago than the longest horizon of any enabled
  binding naming the row's document. It takes the host's bindings, examines
  a bounded number of rows per call and answers a cursor to continue from.

This app runs each as an Oban job,
`StatifierExamples.RoutedWorkflow.DedupeReaper` and
`StatifierExamples.RoutedWorkflow.AddressReaper`, on a `router_maintenance`
queue, and schedules both hourly in `config/config.exs`:

```elixir
plugins: [
  {Oban.Plugins.Cron,
   crontab: [
     {"@hourly", StatifierExamples.RoutedWorkflow.DedupeReaper},
     {"@hourly", StatifierExamples.RoutedWorkflow.AddressReaper}
   ]}
]
```

The address reaper calls again from the cursor until it reaches the end of
the table. The recipe checks that both workers are on the crontab, waits
out the one-second horizon, runs both jobs, and checks that the parcel's
three dedupe rows and its address row are gone.

## 10. Read the trace

The stored execution is `:completed` with its `ended_at` stamp, and its
input log, from `StatifierPersistence.Executions.inputs/2`, holds the two
scans that stepped it, each by the door it came in through:

    0 step parcel.scanned at depot
    1 step parcel.scanned at doorstep

The duplicate and the late scan are not there: neither reached the
execution. The routing ledger is where they are recorded.

## What this recipe leaves out

Each of these is in `statifier_router`'s README and not needed here:

- **A front.** The recipe calls `StatifierRouter.route/3` itself. A host
  starts `StatifierRouter.Broadway` with the producer it already runs, or
  calls `StatifierRouter.Webhook` from a controller.
- **Bindings per scope.** One `:bindings` list serves every scope here; a
  host whose scopes route differently gives a `:bindings_resolver` instead.
  The publish-time checks read `:bindings` alone, so such a host checks each
  scope's bindings itself.
- **Its own execution ids.** The router mints each new execution id; a host
  that names its executions gives an `:execution_id` callback.
- **Route sends from the chart.** This chart sends nothing: its one route is
  reached through `:on_complete`, because a block document at
  statifier_blocks 0.35.0 cannot author a routed `<send>` - `core.send`
  declares no `type` or `target`. A `<send>` of the router's type to a
  registered route reaches the same adapter, and a delayed one needs a
  `:timer_queue`.

## Moving the first-workflow host to these pins

This app moved from statifier 2.8.1, statifier_persistence 0.17.0 and
statifier_router 0.4.1 to the pins above, and nothing in it changed but the
requirements:

- **statifier 2.9.0** adds `Statifier.Publish.findings/2` and
  `MachineState.last_selection`; this app reads neither.
- **statifier_persistence 0.18.0 and 0.19.0 add no migration.** 0.18.0's
  refusal of `migrate/4` on a linked execution and 0.19.0's move to
  `prune_executions/4` reach nothing here: this app migrates no execution,
  and its adapter exports no pruning callback.
- **statifier_router 0.5.0 grows two closed sets**: a delivery whose step
  selects no transition answers `{:dropped, binding_id, :unmatched_event}`,
  and every `:unregistered_routes` entry of `Contracts.check/3` carries a
  `reason`. `StatifierExamples.Publish` matches those entries on
  `%{route: _, location: _}`, which still holds. 0.6.0 adds options and
  changes nothing a host that sets none of them sees.
