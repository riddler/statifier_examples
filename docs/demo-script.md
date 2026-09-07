# The executing signup: a demo script

A numbered walk through the signup wizard as a *running* chart: the authoring
view, a durable run, live block marking, the Run pane over the stored run, a `kill -9` the run
survives, the abandonment nudge, and the account the wizard exists to create. The last
two beats step outside the wizard: one runs a chart that embeds another, and
one puts the editor back in the author's hands and writes a flow backwards
from its sink.

Each beat is one thing you do and what you should see when you do it. Every
line quoted below was read off a real run of this repository at `main` on a
fresh `mix setup`, so a beat that does not match is a bug rather than drift in
the prose. The whole thing takes about five minutes.

The README's "Durable runs, and picking one up after a `kill -9`" section is
the same machinery explained; this file is the version you read out loud with
the app in front of you.

## Before you start

```sh
mix setup
mix phx.server
```

Two shells are easier than one: the second is where the `sqlite3` queries and
the `kill -9` go. Nothing here needs a service, a container or a credential -
the database is one SQLite file under `priv/`.

Start from a database with no runs in it. `mix ecto.reset` is the blunt way,
and it is fine: nothing in this repo is precious.

---

## 1. Open the authoring view

**Do**: go to <http://127.0.0.1:8645/editor?doc=signup_wizard>. The dev
port is 8645 unless you set `PORT`.

**See**: the host's header names the document - `Signup wizard`, at
`revision 11`, id `bdoc_signup_demo` - beside the DOCUMENT and THEME
selects, a Compile button and `Findings 0`. The canvas opens at Fit width -
`20 blocks`, `depth 4` - and the
palette on the left counts `31 block types, 1 recipe`. Nothing is running
yet, so the header shows a **Run** button and no status beside it.

This is the whole point of the beat: what you are looking at is an editor, not
a viewer. The run you are about to start runs *this* document.

## 2. Read the header's run controls

**Do**: look along the top of the page, to the right of `Compile`.

**See**: `Run`, and then three event buttons - `signup.abandoned`,
`signup.email_verified`, `signup.reminder_due` - present but disabled. There
is no run yet, and the canvas is sitting on the page rather than inside a run
pane.

The buttons are the document's own: they are the `event` of every
`core.on_event` block in it, sorted. A document with different interrupts
offers different buttons, and no code here knows their names.

They are in the header rather than in the Run pane deliberately. The pane
`statifier_blocks` gives a host has a send control of its own, and it writes
into a live `Statifier.Session` process; a durable run does not have one, so
the pane reads a run of this app's as not sendable and says so. Sending to a
stored run is the host's own door, and this is it.

## 3. Press Run

**Do**: press **Run** in the header.

**See**: three things move at once.

- The address bar grows a `run=` parameter -
  `?doc=signup_wizard&theme=light&run=868edf9bf6eb15ac3e3e58427b57a105`. That
  hex string is the run id, and it is the only thing you need to come back to
  this run later.
- The header status beside Run reads `running`, and Run becomes **Stop**.
- The canvas marks seven blocks active - the 24-hour wait
  (`blk_su_verify_wait`), the three interrupt rules watching it
  (`blk_su_reminder_due`, `blk_su_verified`, `blk_su_abandoned`), and the
  three groups they are nested in (`blk_su_root`, `blk_su_verify`,
  `blk_su_reminder_window`).

  Seven and not four, since se-dh0. The marks are read off the run's own
  configuration now rather than derived by this app, and a configuration
  holds the compound states above an atomic one as well as the atomic one
  itself - so a group whose child is active is marked too, which is what an
  author reading the canvas would say is happening anyway.

The chart has walked from the top to the place where it can only wait for the
outside world, and it did that in the time it took the button to come back up.

## 4. Read the run

**Do**: look at the pane the canvas is now sitting inside.

**See**: the canvas has been seated in a **Run pane**. Above it, a status
reading `(no session) persisted` and a scrubber - `First Prev Next Live`,
`Showing the live tip.` Below it, an event log grouped by macrostep:

```
Event log: sess_06g7f1khtjx5fpv268jmc2dk8w
  Macrostep 1 - initialize
  Macrostep 2 - done.invoke.s_blk_su_account__running.inv_1
  Macrostep 3 - done.invoke.s_blk_su_send_verification__running.inv_2
```

Open any macrostep and it expands into its rounds: which transition was
selected, which states were exited and entered, what each round executed,
and the configuration the macrostep came to rest on.

Three things this pane is, that the hand-rolled feed it replaced was not.

**It is the stored run, not this page's memory.** The rows are produced by
replaying the run's persisted input log - `statifier_persistence`'s
ADR-0010, read by `StatifierExamples.Charts.Replay` - through statifier-ui,
which turns it into exactly the message stream a live session emits. Reload
the page and the whole run comes back, which section 7 is about.

**It scrubs.** Press `Prev` and the marks on the canvas move to where the
chart was at the previous macrostep; the note above says which point is
being shown and whether the configuration drawn is that macrostep's own.
Press `Live` to come back to the tip.

**It says what it cannot do.** Beside the send control:
`A persisted run has nothing to send to.` The pane's own send control writes
into a live `Statifier.Session` process, and a durable run has none - so the
event buttons for this run are the host's, in the page header beside Run and
Stop.

What the log shows for the run so far is two calls out to the host, then two
delays: the abandonment nudge at 90 seconds and the verification wait at 24
hours. The nudge is 90 seconds because
`config :statifier_examples, :signup_reminder_delay` says so in dev - the
fixture itself ships the production framing, `2d`, and the host applies the
configured duration as the document loads.

## 5. Confirm the run is durable rather than merely running

**Do**: in the second shell,

```sh
sqlite3 priv/repo/statifier_examples_dev.db \
  "select run_id, status, length(position_blob) from statifier_runs;"
sqlite3 priv/repo/statifier_examples_dev.db \
  "select id, state, args ->> 'event', scheduled_at from oban_jobs;"
```

**See**: one run row - `active`, with a position blob of about 1.2 kB - and
two job rows, both `scheduled`:

```
1|scheduled|signup.reminder_due|<90 seconds from now>
2|scheduled|statifier_blocks.wait.blk_su_verify_wait|<24 hours from now>
```

Both delays are rows in the same file the run is in. There is no process
holding this chart, and no timer in anybody's mailbox.

**Do**, while you are in there, ask what the run was driven by:

```sh
sqlite3 priv/repo/statifier_examples_dev.db \
  "select seq, door from statifier_inputs order by seq;"
```

**See**: one row per event that reached the interpreter, dense from zero, each
naming the door it came in at - the invocation answers the create's own drive
fed back, then a `step` for every event sent since. That table is
`statifier_persistence`'s per-run input log (its ADR-0010), it is what section
4's pane was replaying, and it is the reason section 7's resumed page comes
back with the whole run rather than a line saying it was resumed.

## 6. Kill the server the hard way

**Do**: no shutdown hook, no flush:

```sh
kill -9 $(lsof -nP -tiTCP:8645 -sTCP:LISTEN)
```

**See**: the page goes dead in the browser. Re-run the `oban_jobs` query from
beat 5 with the server down: **both rows are still there, still
`scheduled`**. That is the beat - a deploy in the middle of somebody's signup
window does not lose their reminder, because the reminder was never in memory
to lose.

## 7. Start it again and reload the same URL

**Do**: `mix phx.server` in the first shell, then reload the page with the
`run=` parameter still on it.

**See**: the run comes back on the configuration it was left in.

- The same seven blocks are marked active on the canvas.
- The header says `running`.
- The Run pane's log is the whole run again - `Macrostep 1 - initialize`
  down to the macrostep the chart came to rest on - not a single line saying
  it was picked up.

That last point is the one worth stopping on, because it is the beat this
script used to have to apologise for. The **marks** always came from the
stored position and were always exact. The **narration** did not: it was
derived from the effects each step returned, effects were not stored, and a
resumed run opened with the fact that it had been resumed and nothing else.
Now the run's inputs are stored too, so what comes back after the `kill -9`
is the run, not a note about it.

## 8. Nudge the visitor who never verified

**Do**: press **signup.reminder_due** in the page header.

The script presses the button rather than waiting the 90-second window out,
so the beat is repeatable and the demo stays under five minutes. The event it
sends is the same one the stored job carries.

**See**: the log gains a macrostep named for the event - `signup.reminder_due`
- and then the ones its cascade raised, and the run **stops in the middle of a
call**. Open the last macrostep and read its rounds: the reminder is
delivered, the abandon interrupt takes the group, the notify call goes out and
comes back, the onboarding group is entered, and the company-details call is
dispatched with no answer after it.

That last one is the beat worth stopping on. Every other call in this app is
answered inside the step that made it; the company-details step is not.
Collecting a company's details is a human step that takes hours, so the host
starts it as an Oban job and tells the chart nothing yet. The drive reaches
quiescence and the run **persists with the invocation still live** - no
process is holding it, and the header reads `running` rather than `done`. Kill
the server here and the call is still outstanding when it comes back.

**See**, a moment later, without touching anything: the log grows by the
macrosteps the answer drove, ending in the workspace being created, and the
header goes to `done`.

That is the job answering, on a process that has never seen this run: it
rebuilt the chart, the position and the run out of SQLite, fed the answer back
through the durable driver's completion door, and the page redrew because the
answer was broadcast. One reading and not two, which is the other half of what
the input log bought: the narration is the run's, so a second drive by a
different process extends it rather than replacing it.

Narrate the whole thing honestly, because it is what the chart says: the nudge
fires, the reminder window ends, the visitor is notified, the signup pauses on
a call that takes real time - **and then it completes anyway**. Nudged, then
signed up. The wizard has no trailing park after the nudge; adding one is a
change to the chart, not to this script.

The header now reads `done`, the three event buttons are disabled again, and
the only active mark left is the root.

If the run sits on `running` and never advances, the invocations queue is not
draining - `select id, state, queue from oban_jobs` will show the invoke job
`available`. It is a stored row either way, which is the point.

## 9. Look at what the run wrote

**Do**:

```sh
sqlite3 priv/repo/statifier_examples_dev.db "select run_id, status from statifier_runs;"
sqlite3 priv/repo/statifier_examples_dev.db "select id, email from users;"
sqlite3 priv/repo/statifier_examples_dev.db "select id, state from oban_jobs;"
```

**See**:

```
868edf9bf6eb15ac3e3e58427b57a105|completed
1|signup-868edf9bf6eb15ac3e3e58427b57a105@example.com
1|cancelled
2|cancelled
3|cancelled
```

The run record is `completed`, not `active`: the page compiles the document
with `terminate: true`, which is what gives the emission a top-level `<final>`
and lets a chart actually finish.

One user row, keyed on the run id - the chart carries no personal data, so the
address is derived rather than collected, and it is fiction like every value
in this repository.

And three cancelled jobs, none of them cancelled by anything anybody authored.
The compiler emits the cancel in the `<onexit>` of the scope each send was
armed in, so leaving the verification window took down both the reminder and
the 24-hour wait, and finishing onboarding took down its two-hour deadline.

## 10. Read the log

**Do**: look at the server's output.

**See**: one line per call, which is all a reference embedder's handlers do:

```
[info] myapp:notify completed with 0 params
[info] myapp:signup collected step "company_details"
[info] myapp:provision created the account signup-868edf...@example.com
```

`myapp:provision` is the only one of the three that writes, and it is
idempotent on the run id: deliver it twice and the second says
`provisioned=existing`.

## 11. Run a chart that embeds another chart

**Do**: switch the DOCUMENT select to `Signup onboarding`, or go straight to
<http://127.0.0.1:8645/editor?doc=signup_onboarding>.

**See**: a five-block document at `revision 1`, id `bdoc_su_onboarding_demo`,
and `Findings 0`. The one thing worth pointing at is that zero: the chart's
first block is a `core.subchart` naming the wizard's document id
(`bdoc_signup_demo`), and this app registers a handler for
`statifier_blocks:subchart` - the canonical one `statifier_blocks` ships,
given a resolver over this app's own fixture list.

**Do**: press **Run**.

**See**: the child starts. Of the rows that land, these four are the beat:

```
0 | Run started         | 83aae24cd3331f9d66bef6e983292dba
1 | Entered             | blk_so_root, blk_so_wizard
2 | Invoke dispatched   | statifier_blocks:subchart on blk_so_wizard
3 | Child chart started | bdoc_signup_demo as run 83aae24cd3331f9d66bef6e983292dba/blk_so_wizard/0
```

Row 3 is the whole point. On the durable path a `core.subchart` is not
something the parent holds in memory: `StatifierExamples.Charts.Durable`
routes the invoke type to `StatifierBlocks.Runtime.DurableSubchart`, which
turns the block's `{:start_child, _, _}` instruction into **its own
persisted run** - its own row, its own position, its own status, its own
run id.

That id is not random. It is the parent's, plus the invocation, plus the
child index, so a child id strictly extends its parent's, which is what
makes the tree acyclic and the cascade below terminate. And the parent does
not answer the call itself: it rests on the live child until the child
reaches a terminal status, and the driver answers the invocation then.

**Do**: open the child as a run of its own. Its id is the one row 3 printed:

```
http://127.0.0.1:8645/editor?doc=signup_wizard&run=83aae24cd3331f9d66bef6e983292dba/blk_so_wizard/0
```

**See**: the wizard, at `revision 11`, id `bdoc_signup_demo`, `running`, and a
Run pane of its own with the child's own run in it - its own log, replayed
from its own input log. One log per run is `statifier_persistence`'s ADR-0010
decision 7, and this page is what it looks like: the child's steps are here,
and on the parent's page there is only the answer the child sent back.

Nothing on that page knows it is anybody's child. It is the wizard, resumed
from storage exactly as section 7 resumed the parent after the `kill -9` -
and resumed **by run id alone**, because the page's own compile is the root
recipe while a child's stored identity is keyed on the child recipe, so the
usual resume-onto-this-canvas path would refuse it. Drive the wizard to the
end here and the parent finishes too, with nobody pressing anything on the
parent's page.

**Do**: go back to the parent's page and press **Stop** while the child is
still live.

**See**: reload the child's URL. The header says `cancelled`.

Stopping a parent has to take its children with it: nothing is holding an
orphaned child, and its stored timers would go on firing into a run no page
will ever show. `StatifierExamples.Charts.Durable.abandon/1` walks the run's
child subtree and cancels it. Cancellation *retains* - the child keeps its
record and its stored position byte for byte - which is why the page above
still renders after the stop, and it is what makes the button safe to press.

**What the host had to supply** is three small things, and naming them is
the point of a reference embedder:

- **`StatifierExamples.Persistence.list_runs_by_metadata/2`** is what opts
  this app into durable subcharts at all. The driver refuses to start a
  child over a store that cannot enumerate one, because a child that could
  never be found is a child that could never be cancelled. SQLite has no
  `jsonb @>` operator, so this app's version is a containment test in
  Elixir, with the table scan it costs written down in that module rather
  than hidden.
- **`chart_resolver:`** on the driver is how a *child's* driver reaches the
  *parent's* chart in order to answer it, which it does not hold. A stored
  chart is opaque to `statifier_persistence`, so the host walks the
  documents it publishes and matches on the content hash.
- **`abandon/1`'s cascade**, above.

**The other deployment shape still exists**, on the same document. A live
`Statifier.Session` started with
`StatifierExamples.Charts.invoke_handlers/0` **and
`inherit_invoke_handlers: true`** runs `blk_so_wizard` as a child *session*
instead - byte for byte the chart the run record pinned at create, compiled
as a child, which `StatifierExamples.Charts.SubchartTest` asserts by
comparing the child's content hash against that pin. It runs to depth 2
there, driven rather than read: the child dispatches its own `myapp:signup`
call, assigns the answer, advances into the wizard's email-verification
group `s_blk_su_verify`, ends on the wizard's own abandonment event, and
reports an outcome the parent routes through its `on_done` slot before
finishing. The negative control is
asserted beside it - with `inherit_invoke_handlers` left at the engine's
default of `false` the child holds no handler map at all and parks at
`s_blk_su_account` forever. The option is opt-in upstream on purpose, since
inheritance would otherwise run a host's handlers inside charts nobody
registered them for, so a host that embeds charts states it and this app is
the reference embedder stating it.

Which of the two a `core.subchart` gets is **host wiring, not authoring**:
`statifier_blocks` ships two handlers for the one invoke type and this app
gives both the same resolver, so nothing in the document says which
deployment shape it is for. That is the thing to say out loud, because it
means an author never writes a chart for one deployment shape.

## 12. Read what the run pinned

**Do**: in the second shell, read the run's metadata.

```sh
sqlite3 priv/repo/statifier_examples_dev.db \
  "select metadata from statifier_runs order by inserted_at desc limit 1;"
```

**See**: two keys - the fixture the run is of, and the child chart it
resolved:

```json
{"fixture":"signup_onboarding",
 "subcharts":{"bdoc_signup_demo":"sha256:<64 hex characters>"}}
```

`core.subchart` names its child by **document id**, and a document id is
stable across every revision of that child - so the record would otherwise
say nothing about which revision this run actually ran. The hash is that
missing fact, written once at create and never rewritten (campaign-023 ruling
R-d). Edit the wizard, start a second onboarding run, and the two runs' pins
differ while both still say `bdoc_signup_demo`. The digits are not quoted
here for the same reason: they are a hash of the child's bytes, and this
deployment writes its configured reminder delay into them before compiling
(beat 8's 90 seconds), so the demo machine's hash is its own.

It is the host's fact, not the compiler's: `StatifierBlocks.Core.Subchart`
says so in as many words - pinning a particular child revision at publish
time is a host provenance concern, carried in run metadata.

## 13. Author a flow backwards, from its sink

This beat needs no run and no second shell. It is about the *authoring*
half, and about the two block types `statifier_blocks` added for it.

**Do**: switch the DOCUMENT select to `Card processing (sketch)`, or go to
<http://127.0.0.1:8645/editor?doc=card_processing_sketch>.

**See**: the same payment flow as beat 1's, caught halfway through being
written - `revision 1`, id `bdoc_cp_sketch`, `8 blocks`, `depth 4`, and
`Findings 2`. Four cards down the canvas: **Take the payment request**, an
**Assign** seeding `capture.attempts`, a **Placeholder** carrying

```
a placeholder marks a step left unwritten here: "Authorize, then capture"
```

and a **Drafts** card carrying

```
this document has parked work in it: the drafts shelf holds fragments that
are not in the flow, and nothing in it is compiled
```

Under all of it, at the **foot of the canvas**, a strip labelled `DRAFTS`
holding a `Sequence` with **Build the receipt** and **Send the receipt** in
it. The strip is a slot like any other - it takes drops, it has gaps - but
its cards have no connectors into the flow, because they are not in it.

That is the whole idea worth saying out loud: the author knew the *end* of
this flow before they knew the middle. Rather than writing the receipt steps
somewhere they would run, or keeping them in a separate file, or not writing
them at all, they parked them in the document, in the tray, where the next
person to open it can see them.

**Do**: drag **Authorize card** out of the palette onto the gap above the
Placeholder, then **Capture funds** onto the gap below it.

**See**: two cards appear in the flow. `Findings` does not move: the sketch
already declared `amount` and `authorization` in its `datamodel`, so the two
steps land on roots that exist. Declaring the roots the middle will use
before the middle exists is the same habit the tray is - it is what authoring
from the sink backwards looks like in the document.

Neither card offers a deadline, and that is deliberate. `myapp.authorize`
used to declare one as a `timeout` field the compiler then dropped on the
floor; it does not any more. A deadline here is the recorded **pair** of
blocks *around* a step rather than a property *on* one: a `core.send`
carrying the deadline event and a `delay`, placed first in the enclosing
group's `body`, and a `core.on_event` on that same group's `interrupts` rail
listening for that event with an `outcome`. The `card_processing` document
this beat's sketch is a half-written version of authors its fifteen-minute
authorization deadline exactly that way, and `statifier_blocks` ADR-0010 is
where the spelling is recorded.

**Do**: delete the Placeholder with the `x` on its card. Then drag the
parked `Sequence` out of the `DRAFTS` strip onto the gap under **Capture
funds**.

**See**: the strip empties to a single dashed gap, the tail joins the flow -
`9 blocks`, `depth 3` - and the header falls to **`Findings 0`**.

That zero is the beat. Neither warning is an error and the document compiled
throughout: a shelf with anything in it and a placeholder are things an
author *says*, on a compile that succeeds. What a host does about them is
the host's policy, read off `%StatifierBlocks.Compiled{}.warnings` - and the
obvious policy is the one this beat just walked to: a document with parked
work or an unwritten step is not ready to publish, and it says so itself.

`StatifierExamplesWeb.EditorLiveTest`'s "a fixture is built sink-backwards"
drives exactly this sequence through the editor's own events and asserts
each step of it, so the beat is machine-verified rather than remembered.

---

## 14. Edit a guard through picklists, and watch it stay source text

This beat needs no run either. It is about the *condition* half of authoring,
and about a chain that starts three packages away.

**Do**: open <http://127.0.0.1:8645/editor?doc=card_processing>, fold the
palette, and click the **Branch** that sits under **Rate the transaction** -
`blk_cp_risk_branch`, `2 arms + otherwise`. Read the inspector's CONFIGURATION
panel.

**See**: `When "high_risk"` is not a text box. It is a row of dropdowns -

```
risk_rating   >=      70
add clause
switch to text   switch to picklists
```

and `When "low_risk"`, directly below it, *is* a text box, offering only
`switch to text`.

That difference is the whole design and it is not a bug. `high_risk` holds
`risk_rating >= 70`: a comparison of a path against a literal. That is
exactly what `Predicator.Simple` names as the subset a row of dropdowns can
draw - a flat list of such comparisons joined by one connective, of which a
single clause is the shortest case. It is a single clause here, so there is
no connective select and no `remove` beside the row: both appear from the
second clause on, and `add clause` is what gets you there.
`low_risk` holds `risk_rating < 40 AND customer.verified`, and
`customer.verified` is a bare path rather than a comparison, so the whole
expression answers `:outside`. Outside the subset is an ordinary answer about
a perfectly valid expression, not an error: the arm compiles exactly as it
always did, and the editor simply declines to offer an author a mode that
cannot draw what they wrote.

**Do**: change clause 1's operator from `>=` to `>`.

**See**: three things move at once. The canvas chip under `WHEN "HIGH_RISK"`
becomes `risk_rating > 70`; **Undo** lights up, because the document changed;
and pressing **Compile** leaves the header on `Findings 0` - where the
document opened, and no new diagnostic from the edit.

### The point: nothing here invented a second representation

This is the beat worth being slow about, because a structured editor is
usually where a source language quietly acquires a rival format on disk.

Look at what the field actually is. The condition is **one** named input,

```
input name="config[arm_high_risk]"  value="risk_rating > 70"
```

and that is the only element in the control the form serializes. The
dropdowns beside it carry no `name` at all. Each one is a list whose option
*values* are entire candidate source strings - picking the `>` option on
clause 1 is picking the string `risk_rating > 70` whole. The hook's job is to
put the chosen string into that input, and there is nowhere else for a
condition to live.

Press **switch to text** on the same arm and the point closes: the field
becomes a plain input holding `risk_rating > 70` -
the same characters the canvas chip shows, and the same characters the
document held before anyone touched a dropdown. The picklists are a way of
*choosing* source text, not a way of *storing* something else, so a document
authored entirely through dropdowns and one authored entirely by typing are
the same document.

### What that proves about the chain

Four packages, each proving the same subset one level further out:

| Layer | Package | What it contributes |
|---|---|---|
| the subset | `predicator` | `Predicator.Simple` - which expressions a row of dropdowns can draw, and the round-trip laws that keep `to_source/1` honest |
| the control | `statifier_ui` | `StatifierUI.Expression` answers *inside* or `:outside`; `Live.ExpressionInput` draws the picklists and `StatifierUIExpressionPicklist` writes the composed string back |
| the field | `statifier_blocks` | an `:expression` config field renders that control whenever the package is on the host's load path, and falls back to a plain source input when it is not |
| the document | this app | a real `card_processing` guard, edited through the dropdowns, compiled, and still source text |

Only the last row is this repository's. The other three are what a reference
embedder exists to consume without special-casing.

### Reproducing this beat

Nothing special. This beat needed git pins and a hook registration the app did
not carry when it was first walked; both retired when the packages published,
and `mix setup` is now the whole recipe.

The packages come from Hex at the floors `mix.exs` states -
`{:statifier_blocks, "~> 0.23"}` and `{:statifier_ui, "~> 0.10"}`, with
`predicator` arriving under them - and no `override:` remains anywhere in the
dependency list. The hook registration is committed, in `assets/js/app.js`:
`StatifierUIHooks` is imported beside `StatifierBlocks` and spread into the
same `hooks` map, resolved through the esbuild `NODE_PATH` the
`statifier_blocks` import already uses. Picklist mode is drawn on the server
and written back on the client, so without that spread the dropdowns would
render and move and change nothing - worth knowing about if a fork ever drops
it.

The beat above was first walked on a running server against the real
`card_processing` document and captured for campaign 028 as
`se-hzt-card-processing-picklists-before.jpg`,
`se-hzt-card-processing-picklist-edit-applied.jpg` and
`se-hzt-card-processing-same-field-as-source-text.jpg`. Those captures predate
the arm's condition losing its second clause, so they show two dropdown rows
where the shipped document now has one.

---

## Two things a viewer will ask

**"Why not press signup.email_verified? That is what a real visitor does."**

Press it and watch: the verification group's resume interrupt fires, the group
re-enters, and the 90-second reminder and the 24-hour wait are both armed
again -

```
16 | Event        | signup.email_verified
18 | Event        | statifier_blocks.interrupt.resume
20 | Delayed send | signup.reminder_due in 90000 ms
24 | Delayed send | statifier_blocks.wait.blk_su_verify_wait in 86400000 ms
```

The run is back where it started, one round later. The only event that
advances *past* the wait is the wait's own event,
`statifier_blocks.wait.blk_su_verify_wait`, and no button offers it - the
buttons are the document's `core.on_event` names, and a `core.wait` is not one
of those. That is a fact about how this fixture is wired, worth showing rather
than hiding: an interrupt that resumes a scope resumes the whole scope, timers
included.

**"Where do the plan and the seat count come from? Nobody typed them."**

From the first step, the one that says "Collect email and password". Point at
the `Performed` row under it - `myapp:signup -> email_verified=false,
plan=business, seats=5`. That is the handler answering, and the account block
names `signup` in its `assign_to`, so the chart writes the answer there on the
call's success transition. The A/B branch downstream reads `signup.plan` and
`signup.seats` out of it.

The values are canned, because there is no form on this page to fill in - but
they are canned in the *handler*, which is where a real deployment's answers
come from too. A call that fails writes nothing, because the assign is on the
success transition rather than in a `<finalize>`.

The `signup` root the answer lands in is declared by the document itself, in a
top-level `datamodel` key beside the tree: which roots a chart's guards read is
a property of that chart, so it travels in the bytes an author edits rather
than in every host that runs it. A host can still declare roots of its own at
compile time, over and above what the document asks for. This one declares
none.
