# A durable execution with an HTTP location: the BasicHTTP front

A patron places a hold on a copy at the Riverside branch. The hold is a
durable execution, and it needs to hear back from the branch desk when the
copy is on the holds shelf. With `statifier_router`'s BasicHTTP front, the
execution gets an HTTP location of its own - a URL the desk POSTs an event
to - and the router delivers that POST into the execution through the same
path every routed event takes.

This guide walks the pieces as this app wires them:
`StatifierExamples.HoldDesk` (the router configuration, the chart's
resolver and the executor), `StatifierExamples.HoldDesk.DeskPost` (the job
that makes the outbound POST), `priv/library/hold_desk.scxml` (the chart),
`StatifierExamplesWeb.BasicHTTPController` (the front's action) and
`test/statifier_examples_web/controllers/basic_http_controller_test.exs`,
which drives the whole of it through the controller.

## A location is a bearer capability

Anyone who holds a location can post events to that execution, and the
router authenticates nothing beyond possession of it (ruled by the
operator, 2026-09-30). The hold hands its location to the one desk its
request names. No request line or dispatch log carries it: the endpoint's
`Plug.Telemetry` logs no request line under `/basichttp`
(`StatifierExamplesWeb.Endpoint.log_level/1`), the route is
`log: false`, and `:filter_parameters` names `token`.

The location is also stored, and whoever can read where it is stored
holds the capability as surely as the desk does. The router's location
table holds the token, which the front looks the location up by. The
location is part of the execution's persisted state: `_ioprocessors`
names it, and the execution's `position_blob` carries it in the clear,
because `StatifierExamples.Persistence` stores the blob as `:binary`.
And the `StatifierExamples.HoldDesk.DeskPost` job that carries the POST
holds it in its arguments, in a job row this app's Oban pruner deletes
seven days after the job finishes (see the end of "The outbound send
runs in the executor").

A host keeps `:debug` out of production; at `:info`, the production level
here, no query is logged. `statifier_router` 0.10.0 runs its own three
statements that bind the token with Ecto's `log: false`, so the router's
query log no longer prints it, but other statements still bind it.
`statifier_persistence` writes the position on the create and on every
step, and Ecto's `:debug` query log prints those writes with the blob cut
short by its inspect limit: the token is unreadable in the line, not
absent from its parameters. Ecto's query telemetry event carries every
statement's bound parameters whatever the `log` option says, so a handler
on it receives the position writes and the desk post job's insert, whose
own log line Oban suppresses. The router's
`docs/adr/0002-addressing.md`, the Note of 2026-10-02 on the location
token and the query log, records the router's half of this and the
persisted state.

A host serves the base URL over TLS and rotates a location that may have
leaked with `StatifierRouter.BasicHTTP.rotate_location/2`, after which
the old one answers 404.

## The pins

| Package | Version | What this guide uses it for |
|---|---|---|
| `statifier_router` | 0.12.0 | the `:basichttp` key, the location, `StatifierRouter.BasicHTTP.Front`, the location table, `deliver_event/4` for a failed send |
| `statifier` | 2.12.1 | the Basic HTTP Event I/O Processor and its decoder |
| `statifier_persistence` | 0.24.1 | the chart registry, the execution, the input log |

0.12.0 is the floor because it is the published release `mix.exs`
requires. 0.9.2 was the first `statifier_router` release whose
migrations and address reaper both run on this app's SQLite database,
and nothing this guide uses needs more.

## The chart

`priv/library/hold_desk.scxml` waits in `requested` for the hold request.
On `hold.requested` it sends `hold.placed` to the desk the request names,
with a `<send type="basichttp">` whose `targetexpr` is the desk's URL, and
passes three parameters: the hold, the copy, and `reply_to`, its own
location, read from `_ioprocessors['basichttp']['location']`. It then waits
in `waiting` for `copy.shelved` and finishes in `shelved`.

## The configuration

`StatifierExamples.HoldDesk.config/0` is a router configuration of its own:
one binding, `hold_requests`, that routes each hold request naming a desk
to the execution keyed by its hold id, and the `:basichttp` key:

```elixir
basichttp: [base_url: StatifierExamplesWeb.Endpoint.url() <> "/basichttp"]
```

Setting the key does two things. It registers the router's processor under
the processor's URI and its short form `basichttp`, which is what lets the
chart's `<send type="basichttp">` pass the engine's type check. And it
gives every execution created under a new address row a location: the base
URL, `/`, and a 43-character token the router mints, never the execution
id. The parcel recipe's configuration,
`StatifierExamples.RoutedWorkflow.config/0`, does not set the key, so its
executions get no location.

A hold request that names no desk does not match the binding:
`StatifierExamples.HoldDesk.request/2` answers
`{:ok, [{:no_match, "hold_requests"}]}`, no execution starts and no send
is planned, where the chart's `targetexpr` would otherwise read an
undefined desk and plan a POST to `:undefined`.

The location token lives in the router's location table, which only a
configuration with `:basichttp` needs. This app creates it in
`priv/repo/migrations/20260930120001_add_statifier_router_locations.exs`:

```elixir
def up, do: StatifierRouter.Migrations.up_locations(@opts)
def down, do: StatifierRouter.Migrations.down_locations(@opts)
```

with the same `depot_id` leading column the app's first router migration
gives every router table.

## The outbound send runs in the executor

A durable execution has no session to perform its sends: the step hands
each effect to the configuration's executor. `StatifierExamples.HoldDesk.execute/2`
plans a BasicHTTP send with `StatifierRouter.BasicHTTP.deliver/3`, which
answers the POST to make - a form body for the desk, with the send's
`scxml-send-key` header - and makes none.

The executor runs inside the delivery's transaction, so it does not make
the POST there. It inserts a `StatifierExamples.HoldDesk.DeskPost` job on
this app's own Oban, in the `desk_posts` queue. The job writes through the
same repo, so it commits with the step that sent the POST and a delivery
that rolls back takes the job with it: the jobs table is the outbox. The
job is unique on the send's dedup key written out, so a step that is
driven again, and re-emits the same send, inserts no second job. The
guard holds while the job's row is in the jobs table and the job is
neither cancelled nor discarded, the two states Oban's default unique
states leave out: a send re-emitted after its job was cancelled,
discarded or pruned inserts a new job, which makes the POST again.

The job performs the POST after the delivery has committed, with the
processor's `perform/2`, through the configuration's `:transport`:
statifier's default, on OTP's `:httpc`, in the dev app, and a transport
under test that hands the POST back to the test instead of sending it.
This is why the example performs after the commit, as `statifier_router`
recommends in `docs/adr/0002-addressing.md`, the Amendment of 2026-10-02
on a durable execution's outbound BasicHTTP send.
Made inside the delivery, the POST would keep the transaction, the
execution's lock and SQLite's single write lock held for as long as the
desk took to answer, and would leave even for a step that then rolled
back. Made from the job, a slow desk holds none of them, and no POST
leaves for a step that never committed.

A desk that does not answer 2xx, or does not answer at all, is retried:
the job makes the POST up to three times. A POST that reached the desk
but whose answer was lost is made again, and so is the POST of a new job
inserted once the uniqueness guard above has lapsed, each with the same
`scxml-send-key` header, so the desk deduplicates on that header: it
takes a send key once, as this app's front does within the router's
dedupe horizon, where a repeat answers 204 and delivers nothing. A send that still fails comes
back into the execution through `StatifierRouter.Delivery.deliver_event/4`,
the one way back in the router's record names, with `create: :never` over
the hold's address row from `StatifierRouter.Addresses.by_execution/2`: an
external `error.communication` event carrying the send's id, delivered
in a step of its own under the plan id `desk_post_failure`. The chart
takes it from `waiting` to its other final state, `desk_unreached`. A
failure that reaches no execution - the hold has finished, or its address
row is gone - is cancelled, which keeps the job and its reason in the jobs
table as the dead letter until the pruner deletes it (below).

A send with no target, which statifier plans as an `error.communication`
raise and no request, plans no job: the executor fails it at once, and
`statifier_persistence` enters `error.communication` into the execution
in the same step. A delayed BasicHTTP send is refused the same way,
because its timer would live in the delivering process rather than in the
database.

The job's arguments carry the planned POST as it was planned, body
included, so the `reply_to` location the body hands the desk is written to
the jobs table with it. Anyone who can read the jobs table holds the
capability (see "A location is a bearer capability" above), so how long
the row stays is a retention decision, and this app makes it in its Oban
configuration in `config/config.exs`:

```elixir
pruner: [max_age: {7, :days}]
```

Oban's pruner deletes a job once seven days have passed since it
completed, was cancelled or was discarded. A location therefore stays at
rest in the jobs table from the step that inserts its job until seven days
after the job finishes; a job still waiting to retry is not pruned. The
age is one for the whole table, every queue alike, because Oban's pruner
keeps no age per queue, and it is written out because Oban's own default
is sixty seconds. Seven days is longer than the 72 hours a BasicHTTP
front keeps a send key, and leaves a week to read a dead letter.

The age is a trade, because a job row does more than hold a location. A
cancelled desk post, the dead letter, is deleted at the same age, so its
reason can be read for seven days. And the uniqueness guard on the send's
dedup key holds only while the job's row is there: once a completed job
is pruned, a step driven again that re-emits the same send inserts a new
job, which makes the POST again. From then on, what keeps that POST from
being taken twice is the desk's dedupe on the `scxml-send-key` header,
for as long as the desk keeps a send key. A host sets its own age: a
shorter one leaves a location at rest for less time, a longer one keeps
the guard and the dead letters for longer.

## The front

The router answers `/basichttp/:token` for every method with
`StatifierExamplesWeb.BasicHTTPController.event/2`, outside the browser
pipeline. The action builds the request map the front reads - the token,
the method, the content type, the body as it arrived, the query string and
the `scxml-send-key` header - hands it to
`StatifierRouter.BasicHTTP.Front.handle/3` and answers the status
`StatifierRouter.BasicHTTP.Front.response/1` maps the answer to:

| The request | The answer |
|---|---|
| a POST the execution takes, or a repeat of a send key it already took | 204 |
| a POST at a location that reaches no execution: unknown, rotated away, or finished | 404 |
| any other method | 405, with `allow: POST` |
| a body or a send key the decoder refuses | 400 |
| any other answer: a delivery that did not settle, which the desk may retry | 500 |

A form body is read by `Plug.Parsers` before any action runs, so the
endpoint's parsers use `StatifierExamplesWeb.RawBody`, which keeps the raw
body of a request under `/basichttp` for the action to hand on.

## Driving it

The controller test routes a hold request, drains the `desk_posts` queue
with `Oban.drain_queue/2` (the suite runs Oban with `testing: :manual`),
reads the `hold.placed` POST the desk was sent, takes `reply_to` from it
and POSTs
`_scxmleventname=copy.shelved` at that location through the endpoint:

```elixir
post(conn, "/basichttp/" <> token, "_scxmleventname=copy.shelved")
```

The answer is 204 and the execution is completed; the same POST again is
404, because the hold has finished. In the dev app, a desk that holds the
location does the same with any HTTP client.
