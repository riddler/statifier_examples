# A durable execution with an HTTP location: the BasicHTTP front

A patron places a hold on a copy at the Riverside branch. The hold is a
durable execution, and it needs to hear back from the branch desk when the
copy is on the holds shelf. With `statifier_router`'s BasicHTTP front, the
execution gets an HTTP location of its own - a URL the desk POSTs an event
to - and the router delivers that POST into the execution through the same
path every routed event takes.

This guide walks the pieces as this app wires them:
`StatifierExamples.HoldDesk` (the router configuration, the chart's
resolver and the executor), `priv/library/hold_desk.scxml` (the chart),
`StatifierExamplesWeb.BasicHTTPController` (the front's action) and
`test/statifier_examples_web/controllers/basic_http_controller_test.exs`,
which drives the whole of it through the controller.

## A location is a bearer capability

Anyone who holds a location can post events to that execution, and the
router authenticates nothing beyond possession of it (ruled by the
operator, 2026-09-30). The hold hands its location to the one desk its
request names and to nobody else. No request line or dispatch log carries
it: the endpoint's `Plug.Telemetry` logs no request line under
`/basichttp` (`StatifierExamplesWeb.Endpoint.log_level/1`), the route is
`log: false`, and `:filter_parameters` names `token`. Ecto's query log at
`:debug` prints bound parameters, and the router binds the token to look
a location up and to store it, so a host keeps `:debug` out of
production; at `:info`, the production level here, no query is logged.
A host serves
the base URL over TLS and rotates a location that may have leaked with
`StatifierRouter.BasicHTTP.rotate_location/2`, after which the old one
answers 404.

## The pins

| Package | Version | What this guide uses it for |
|---|---|---|
| `statifier_router` | 0.9.2 | the `:basichttp` key, the location, `StatifierRouter.BasicHTTP.Front`, the location table |
| `statifier` | 2.10.0 | the Basic HTTP Event I/O Processor and its decoder |
| `statifier_persistence` | 0.24.0 | the chart registry, the execution, the input log |

0.9.2 is the floor because it is the first `statifier_router` release
whose migrations and address reaper both run on this app's SQLite
database.

## The chart

`priv/library/hold_desk.scxml` waits in `requested` for the hold request.
On `hold.requested` it sends `hold.placed` to the desk the request names,
with a `<send type="basichttp">` whose `targetexpr` is the desk's URL, and
passes three parameters: the hold, the copy, and `reply_to`, its own
location, read from `_ioprocessors['basichttp']['location']`. It then waits
in `waiting` for `copy.shelved` and finishes in `shelved`.

## The configuration

`StatifierExamples.HoldDesk.config/0` is a router configuration of its own:
one binding, `hold_requests`, that routes each hold request to the
execution keyed by its hold id, and the `:basichttp` key:

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
plans a BasicHTTP send with `StatifierRouter.BasicHTTP.deliver/3` and
performs what it planned with the processor's `perform/2`, which POSTs a
form body to the desk with the send's `scxml-send-key` header. The POST
goes through the configuration's `:transport`: statifier's default,
on OTP's `:httpc`, in the dev app, and a transport under test that hands
the POST back to the test instead of sending it.

The POST is made inside the delivery's transaction, before the step
commits. A desk that does not answer 2xx, or does not answer at all, is a
failed send: `statifier_persistence` enters `error.communication`,
carrying the send id, into the execution in the same step, and the chart
takes it from `waiting` to its other final state, `desk_unreached`. A
delayed BasicHTTP send is refused the same way, because its timer would
live in the delivering process rather than in the database.

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

A form body is read by `Plug.Parsers` before any action runs, so the
endpoint's parsers use `StatifierExamplesWeb.RawBody`, which keeps the raw
body of a request under `/basichttp` for the action to hand on.

## Driving it

The controller test routes a hold request, reads the `hold.placed` POST the
desk was sent, takes `reply_to` from it and POSTs
`_scxmleventname=copy.shelved` at that location through the endpoint:

```elixir
post(conn, "/basichttp/" <> token, "_scxmleventname=copy.shelved")
```

The answer is 204 and the execution is completed; the same POST again is
404, because the hold has finished. In the dev app, a desk that holds the
location does the same with any HTTP client.
