# The first workflow, from a form post

The routed guide routes events a source hands over. This one starts where a
visitor does: a form post. A host that must answer the browser before any
engine work, keep the posted values out of the engine's state, and dedupe on
a key of its own stores the post in its own table, answers `202`, and hands
only the stored row's id to `statifier_router`'s webhook front from a job.
The chart then holds ids and its own words, and a step that needs what the
visitor typed reads it back by id.

The world is the Riverbend Public Library's card application form, which is
fictional. Every step is code in this app, and one command runs them all:

    mix ecto.migrate
    mix statifier_examples.first_workflow_form_post

The command prints one line per step and stops with a non-zero exit, naming
the step, if any of them does not hold.

## The pins

The recipe is written and checked against these releases, which are what
`mix.exs` requires and `mix.lock` resolves:

| Package | Version | What the recipe uses it for |
|---|---|---|
| `statifier_router` | 0.12.0 | the webhook front, the binding, the delivery, the address, dedupe and ledger tables, the typed-send routes, `:around_delivery`, `:on_create` and `:on_step` |
| `statifier_oban` | 0.17.2 | the steps' jobs and the deadline timers, on this app's Oban |
| `statifier_persistence` | 0.24.1 | the chart registry, the execution, the input log, `Retention.prune/3` |
| `statifier_blocks` | 0.42.1 | the document and the compile |
| `statifier` | 2.12.1 | compiling the chart and running it |

`statifier_router` 0.12.0 is the release this recipe needs: it takes a
webhook request with no raw body when its provider id is a non-empty
string. Before it, the raw body was required even when the provider id was
the message id, so a host with no body to hand over passed the row's id
twice. The jobs run on this app's own Oban. The first line the command
prints names the versions it actually loaded.

## The workflow

The document is `priv/form_post/card_application.json`. One application,
from the post to the library's two systems:

1. **The application arrives.** The chart waits for `application.received`,
   whose data is the stored row's id, and keeps the id.
2. **The library screens it.** The `myapp:screen_application` step answers
   `ok` or `screened_out`. The screen is bounded: if it has not answered
   within five seconds, the flow goes on with the word `unscreened`.
3. **A screened-out application ends here.** The rest of the flow is
   abandoned and nothing is sent.
4. **The library sorts it.** The `myapp:sort_application` step answers
   `card`, `newsletter`, `both` or `neither`: one word in place of the two
   checkboxes the visitor ticked, which stay in the host's table.
5. **Two lanes run side by side.** The card lane, on `card` or `both`,
   checks the address against the service area with the
   `myapp:check_service_area` step, bounded the same way (`check_at_desk`
   when it does not answer in time), and hands the application to the
   patron system. The newsletter lane, on `newsletter` or `both`, hands it
   to the newsletter list. Each hand-off is a typed send of `myapp:route`
   to a registered route.

The bounded step is the first pattern in `statifier_blocks`' flow-patterns
guide, and the two lanes on one word are its second:
[How to build common flow patterns](https://github.com/riddler/statifier_blocks/blob/v0.42.1/docs/guides/flow-patterns.md).

The code is `StatifierExamples.FormPost`. The sections below follow its
`run/1`, one step at a time.

## What the host keeps, and what the engine keeps

**The host keeps the posted values.** The name, the email address, the phone
number and the street address live in the host's `card_applications` table
and nowhere else. So does what follows from holding them:

- **their retention**: how long they stay, and what clears them, is the
  host's decision. No chart holds a timer per application for it; the
  retention section below shows the host's jobs;
- **their encryption**: this app stores them in plain columns. A host that
  must encrypt them at rest does so in its own table, with its own keys;
  nothing in the engine is involved, because nothing in the engine holds
  them;
- **per-scope terms**: which library system an application belongs to,
  and how long each one keeps its applications, is the host's. This app
  serves one library system, `riverbend`, fixed by the form's controller.

**The engine keeps ids and declared words.** No field value of the posted
form enters a router message, a binding's `data`, a datamodel, an input
log, an Oban job's arguments or meta, a route's outbox, or telemetry
metadata. The engine's rows hold the application's id, the execution's id,
and the words the chart declares (`ok`, `both`, `inside`, and the rest). A
step that needs a value re-reads it by id through
`StatifierExamples.FormPost.CardApplications.Reader`, the one module that
reads the personal fields, so a reviewer checks "ids only" by reading that
module's callers. `test/statifier_examples/form_post/ids_only_test.exs`
reads every row the engine and the router own and proves it; step 7 below
is the same check in small.

## 1. Register the chart

The document is compiled for running, with `terminate: true`, and stored
under its content hash with `StatifierPersistence.Storage.save_chart/3`.
`StatifierExamples.FormPost.PublishedCharts` is the router's resolver: it
answers that hash for `bdoc_card_application`, and `{:error,
:not_published}` for any document the registry does not hold, so the router
creates nothing for it. The recipe checks the resolver's answer.

## 2. Store the post, and answer

The form posts to `POST /form-post/card-applications`.
`StatifierExamplesWeb.CardApplicationController` hands the form to
`StatifierExamples.FormPost.CardApplications.receive_application/2` and
answers `202` with the stored application's id, before any workflow runs.

`receive_application/2` inserts the row and its
`StatifierExamples.FormPost.IntakeJob` in one transaction, so a stored
application always has its job and a row that did not commit leaves none.
The job's arguments are the row's id and nothing else:

```elixir
%{"application_id" => id}
```

A job's arguments sit in the jobs table, in plain sight of every dashboard
and dead letter. The recipe stores an application and checks that its one
intake job carries the id alone.

## 3. The same post again

The client's key is the form's own `idempotency_key` field, which the page
fills once, so a visitor who presses submit twice posts the same key. The
table is unique on `(scope, idempotency_key)`, and a repeat answers the
first application and stores nothing, row or job. The unique index decides
it, not a read before the write, so two posts racing each other still store
one row. The recipe posts the same form again and checks that it answers
the first application, with one row and one intake job.

## 4. The job routes the id

`StatifierExamples.FormPost.IntakeJob` reads the row's `scope` column and
nothing else, and calls `StatifierRouter.Webhook.handle/3` under
`StatifierExamples.FormPost.Router.config/0`:

```elixir
%{
  scope: scope,
  source: "card_application_form",
  provider_id: Integer.to_string(id),
  data: %{"application_id" => id}
}
```

The provider id is the message id the router dedupes on. There is no
`:raw_body`: this host has no body to hand over, since it never gives the
router the posted values, and `statifier_router` 0.12.0 takes the request
without one. This is the shape `statifier_router`'s guide calls
[a form post you store first](https://hexdocs.pm/statifier_router/0.12.0/how-to-take-webhooks-and-form-posts.html#step-5-a-form-post-you-store-first).

**The configuration.** One binding, `card_applications`, keys every event
from the `card_application_form` source by the application id and hands
the execution `application.received`, with the id as the event's only data.
Every door the router drives runs inside `:around_delivery`,
`StatifierExamples.FormPost.Scope`, this app's stand-in for a host's tenancy
context: it holds the library system while the work runs. Every create and
step goes through `:on_create` and `:on_step`,
`StatifierExamples.FormPost.Stepper`, which refuses outside a library system
and adds the serialization SQLite needs. The two routes,
`StatifierExamples.FormPost.PatronSystemRoute` and
`StatifierExamples.FormPost.NewsletterRoute`, are registered under the send
type `myapp:route`.

**The steps run on the app's Oban.** The three steps' `<invoke>`s become
jobs on the `statifier_invocations` queue and the two deadlines become
`statifier_oban` timer jobs on `statifier_timers`.
`StatifierExamples.FormPost.Delivery` steps each answer back in, inside the
application's library system. `StatifierExamples.FormPost.Drain` runs the
queues in order until none has work left; the recipe drains them until the
execution completes, and checks the three words in its datamodel:

    screen ok, sort both, area inside

## 5. The routes hand it on

Both lanes ran, so both routes were reached. A route runs inside the
delivery's transaction, so it may only hand off durably. Here each one
reads the application through the reader, writes one row of the
`card_application_sends` outbox, and writes a fictional reference back to
the application through `StatifierExamples.FormPost.CardApplications.Writer`,
which marks it `sent`. The outbox row is unique on `(route, key)` with the
router's key, so a redriven delivery writes nothing new. The recipe checks
both outbox rows, both references and the status.

## 6. The same job again

An Oban job runs at least once. The recipe routes the same application a
second time, as a second run of the intake job would, and the router
answers it from its dedupe table without reaching the execution:

    {:ok, [{:duplicate, "card_applications"}]}

The routing ledger holds one row per attempt:

    created_and_delivered, duplicate

## 7. Ids only

The recipe reads back the execution's datamodel, its input log and every
job stored for the application, and checks that none of the four personal
values the visitor typed is in any of them. `statifier_oban` stores a
job's host-opaque fields (an invoke's params, content and caller context,
a timer's data and caller context) as Base64 term payloads, so the recipe
decodes each one with `StatifierOban.OpaqueTerm.decode_field/2` before it
searches; a payload it cannot decode stops the step.

## 8. A screened-out application

A second application gives a post office box as its street address. The
screen answers `screened_out`, the flow is abandoned before the sort, and
nothing is sent: the execution completes with the words

    screen screened_out, sort unsorted, area check_at_desk

The chart's word reaches the host's row too. `StatifierExamples.FormPost.Delivery`,
after the step that ends an execution screened out, marks the stored
application `screened_out` through
`StatifierExamples.FormPost.CardApplications.Writer.record_screened_out/2`,
by the id the datamodel holds, so the host's retention can age it. The
recipe checks the words, that nothing was sent, and the status.

## 9. Read the trace

The first execution's input log, from
`StatifierPersistence.Executions.inputs/2`, holds the event that opened it
and the three steps' answers. The event's data is the id; each answer is a
word:

    0 step application.received %{"application_id" => 1}
    1 step done.invoke.s_blk_ca_screen_call__running.inv_1 "ok"
    2 step done.invoke.s_blk_ca_sort_call__running.inv_2 "both"
    3 step done.invoke.s_blk_ca_area_call__running.inv_3 "inside"

The duplicate is not there: it never reached the execution. The routing
ledger is where it is recorded.

## Retention, on the host's scheduler

Two jobs on the `retention` queue, scheduled daily in `config/config.exs`,
clear what the recipe leaves behind. The recipe does not run them, since
they sweep the whole table; their own tests do.

- `StatifierExamples.FormPost.PurgeJob` clears the personal fields of an
  application once its outcome is old enough: `:screened_out_after_days`
  after it was screened out, `:sent_after_days` after it was sent. It clears
  the fields and keeps the row: the id and the idempotency key stay, so a
  repeat post of the same form is still matched and answers the first
  application instead of storing the values again.
- `StatifierExamples.FormPost.PruneJob` calls
  `StatifierPersistence.Retention.prune/3`, which clears the position blob
  and the input log of every execution that ended before the cutoff and
  keeps the execution row. It passes no `scope:`, because this app's
  persistence tables have no leading column: the library system lives on
  the host's `card_applications` table, not on the engine's rows. A host
  whose engine tables carry a tenant column passes it, one call per tenant.

The ages are this example's numbers, not a recommendation. The routed
recipe's two reapers already sweep the router's dedupe and address rows,
these included.

## What this recipe leaves out

- **The front's guards.** The form's route has no session and no CSRF
  token, because a public form has no signed-in visitor to protect. A host
  guards it otherwise (an `Origin` check against its own pages, a rate limit
  per client address, a field a person never fills); none of that is here.
- **Routing from the controller.** The controller stores and a job routes.
  A host that may make the browser wait can call
  `StatifierRouter.Webhook.handle/3` from the controller instead, the
  router guide's step 4.
- **Library systems from the request.** The controller fixes `riverbend`.
  A multi-tenant host resolves the library system from the request (the
  host name, or the path a library system's page posts to), never from a
  field the visitor could change.
- **Outside systems.** The patron system and the newsletter list are
  stand-ins in this app, written through the same repo. A host whose system
  is truly outside inserts a job in the route and calls the system from that
  job, never from the route.
- **Encryption at rest.** The personal fields are plain columns here.

## Moving a host to these pins

The move that shaped this recipe is `statifier_router` 0.11 to 0.12.0. On
0.11 a webhook request needs `:raw_body` even beside a `:provider_id`, so a
host that stores first passes the row's id as both. On 0.12.0 it drops
`:raw_body` and passes the id once, as the provider id; every request that
still carries a raw body is answered exactly as before. A host on 0.11
keeps the id-twice shape until it moves.
