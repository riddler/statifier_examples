# The refusal suite

Six charts this app's publish step, `StatifierExamples.Publish.check/2`,
refuses, and what the engine does when each one runs anyway. Each case is
one JSON file here. `test/statifier_examples/publish_refusals_test.exs`
reads every file twice: once through `Publish.check/2`, asserting the stage
and the finding the case names, and once on the engine, starting the same
chart with the same registries and asserting what the case records.

The suite proves one thing per case: the publish step refuses, before any
execution starts, a defect that the engine at run time either refuses too
(the backstop agrees with the gate) or does not refuse at all (the gate is
the only line). Where the engine refuses nothing, the case records what it
does today and the test asserts it, so a later release that adds a run-time
refusal turns that case red and the case is updated on purpose.

The shape is this app's own. It shares no schema with the engine's
conformance corpus or the router's, and a host that vendors these files
reads them with its own code.

## The cases

The runtime twin column names the row that describes the same refusal in
statifier-ex's `docs/publish-time-checks.md`, by package and row.

| Case | Refused at | Finding | World | What the engine does with the same chart | Twin row |
|---|---|---|---|---|---|
| `unregistered_send_type` | `:send_types` | `unsupported_send_type`, on the `<send>` | parcel delivery | Raises `error.execution` with data `{:unsupported_type, "myapp:courier"}`, carrying the send's `sendid`. The chart carries on. | statifier, S1 |
| `unregistered_route` | `:routes` | `unregistered_route`, on the `<send>` | library loan | `StatifierRouter.SendHandler` answers `{:error, {:unregistered_route, "overdue_notices"}}`. The host reports that with `Statifier.Session.failed_send/3`, and the chart hears `error.communication` carrying the send's `sendid` and no data. | statifier_router, RT1; statifier, S5 |
| `undeclared_receiver_event` | `:contracts` | `undeclared`, on the binding `depot_lost` | parcel delivery | Refuses nothing. `parcel.lost` is dequeued, selects no transition and changes no state, and no error event is raised. | statifier_router, RT13; statifier, S15 |
| `unresolvable_child` | `:graph` | `graph`, on the subchart block's `chart` field | library loan | The child fails to start: `error.communication.invoke.blk_ho_pickup` with reason `unknown_document` and the child's id in its detail, and the block's error path runs. | statifier_blocks, B1 |
| `dropped_consumed_outcome` | `:graph` | `graph`, on the subchart block's `outcomes` field | parcel delivery | Refuses nothing. The child finishes `received`; the parent's arm for `refused` never matches, and its unconditioned arm takes the answer into the `on_refused` path. | statifier_blocks, B4 |
| `undeclared_payload_capture` | `:findings` | `config`, on the `core.on_event` block's `capture` field | patron registration | Refuses nothing. The capture compiles to an `<assign>` guarded by `_event.data.email !== undefined`, so an event without `email` skips it: `patron` is never written, and no error event is raised. | none: nothing at run time refuses it |

The last case's document does not compile, because the block compiler
refuses the same capture. The chart the engine runs is compiled with the
payload declaration dropped, which is one of the ways out the finding
offers, and the test pins that dropping the declaration and declaring the
missing key compile the same SCXML: the declaration changes no byte of the
chart.

## The shape of a case

Every file is one JSON object with these keys.

- `case` - the case's name, the same as the file's.
- `world` - `library_loan`, `patron_registration` or `parcel_delivery`;
  the document's own `metadata.domain` says the same.
- `summary` - one sentence saying what is wrong.
- `host` - the host state the document is judged against and run with:
  - `block_types` - the block types the host registers on top of this
    app's palette. `myapp.typed_send` is a leaf step writing one `<send>`
    with a literal `type`, `target` and `event`, the three keys of its
    config; this app's palette has no such step, so the test registers
    `StatifierExamples.TypedSendStep` for the two cases that need it.
  - `send_types` - the `<send>` types the host registers a processor for.
    `myapp:sink` is the router's.
  - `routes` - the route names the host registers with the router.
  - `bindings` - the router bindings, each with `id`, `source`, `match`,
    `key`, `document` and `event`.
  - `published` - the other documents the host has published, as block
    documents. A child a subchart names resolves only if it is here.
- `document` - the block document being published.
- `publish` - what `Publish.check/2` answers:
  - `stage` - the stage that refuses, without the colon.
  - `check` - the refusing finding's `check`.
  - `anchor` - where the finding points: `["scxml"]` for an element of the
    generated chart, `["binding", id]` for a router binding, or
    `["config", block_id, key]` for a block's config field.
- `runtime` - what the engine does with the same chart:
  - `twin` - a short name for it.
  - `deliver` - `null` when starting the chart is enough, or the one event
    to send after it starts: `to` is `execution` for the chart itself or
    `child` for the child its subchart started, with `event` and `data`.
  - `expect` - what is asserted, each key optional:
    - `raised` - events the execution dequeues, each with its `event`
      name; `data` when the data is asserted, written as JSON (a tuple is
      a list whose atoms are strings); `sendid: true` when the event must
      carry a send id;
    - `handler_answer` - the router send handler's `{:error, reason}`
      reason, as JSON;
    - `reached` - a state the execution is in afterwards;
    - `unchanged_configuration` - the delivered event changes no state;
    - `unwritten` - a datamodel root that is still empty afterwards;
    - `quiet` - no event whose name begins `error.` is dequeued.

## Vendoring the suite

A host that vendors these files needs, beside its own publish step: a
palette with a typed send step under `myapp.typed_send`; the router's send
type registered under `myapp:sink`, with its send handler's misses reported
to the sending chart; a route adapter for every name in `routes`; and a
subchart handler that resolves exactly the documents in `published`.
