# The executing signup: a demo script

A numbered walk through the signup wizard as a *running* chart: the authoring
view, a durable run, live block marking, the run feed, a `kill -9` the run
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
palette on the left offers 28 block types. Nothing is running yet, so the
header shows a **Run** button and no status beside it.

This is the whole point of the beat: what you are looking at is an editor, not
a viewer. The run you are about to start runs *this* document.

## 2. Open the drawer and pick the Runs tab

**Do**: click the drawer strip along the bottom, then the **Runs** tab.

**See**: three tabs - `Truth tables (0)`, `Findings (0)`, `Runs (0)`. The Runs
panel says `no run` and, in place of a table, one sentence: *Nothing is
running. Run, in the header, starts a durable run on this document -
stored, so it outlives this page.*
The three event buttons - `signup.abandoned`, `signup.email_verified`,
`signup.reminder_due` - are present but disabled.

The buttons are the document's own: they are the `event` of every
`core.on_event` block in it, sorted. A document with different interrupts
offers different buttons, and no code here knows their names.

## 3. Press Run

**Do**: press **Run** in the header.

**See**: three things move at once.

- The address bar grows a `run=` parameter -
  `?doc=signup_wizard&theme=light&run=868edf9bf6eb15ac3e3e58427b57a105`. That
  hex string is the run id, and it is the only thing you need to come back to
  this run later.
- The header status beside Run reads `running`, and Run becomes **Stop**.
- The canvas marks four blocks active - the 24-hour wait
  (`blk_su_verify_wait`) and the three interrupt rules watching it
  (`blk_su_reminder_due`, `blk_su_verified`, `blk_su_abandoned`) - and the
  reminder's `core.send` carries a `done` outcome mark.

The chart has walked from the top to the place where it can only wait for the
outside world, and it did that in the time it took the button to come back up.

## 4. Read the feed

**Do**: look at the Runs tab, which now says `Runs (16)`.

**See**: sixteen rows, numbered, three columns - `#`, `WHAT`, `DETAIL`. The
ones worth reading out:

```
0  | Run started       | 868edf9bf6eb15ac3e3e58427b57a105
2  | Invoke dispatched | myapp:signup on Collect email and password
3  | Performed         | myapp:signup -> email_verified=false, plan=business, seats=5
7  | Invoke dispatched | myapp:signup on Send the verification email
12 | Delayed send      | signup.reminder_due in 90000 ms
14 | Entered           | blk_su_verify_wait
15 | Delayed send      | statifier_blocks.wait.blk_su_verify_wait in 86400000 ms
```

Two calls out to the host, then two delays: the abandonment nudge at 90
seconds, and the verification wait at 24 hours. The nudge is 90 seconds
because `config :statifier_examples, :signup_reminder_delay` says so in dev -
the fixture itself ships the production framing, `2d`, and the host applies
the configured duration as the document loads.

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

- The same four blocks are marked active on the canvas.
- The header says `running`.
- The Runs tab says `Runs (1)`, and the one row is
  `Run resumed from storage | 868edf9bf6eb15ac3e3e58427b57a105 (active)`.

One row and not sixteen, and the difference is worth saying out loud: the
**marks** come from the stored position, so they are exact. The **feed** is
derived from the effects each step returned, and effects are not stored, so a
resumed run opens with the fact that it was resumed rather than a replay of
its own history.

## 8. Nudge the visitor who never verified

**Do**: press **signup.reminder_due** in the Runs panel.

The script presses the button rather than waiting the 90-second window out,
so the beat is repeatable and the demo stays under five minutes. The event it
sends is the same one the stored job carries.

**See**: the feed jumps to `Runs (22)` and the run **stops in the middle of a
call**. The shape, in order:

```
1  | Event             | signup.reminder_due
2  | Entered           | blk_su_reminder_due
3  | Event             | statifier_blocks.interrupt.abandon
8  | Invoke dispatched | myapp:notify on Remind them to finish signing up
9  | Performed         | myapp:notify
15 | Entered           | blk_su_onboarding, blk_su_onboarding_deadline,
   |                   | blk_su_onboarding_abandoned
20 | Invoke dispatched | myapp:signup on Collect the company details
21 | Call started      | myapp:signup: running as a job, answer to follow
```

That last row is the beat worth stopping on. Every other call in this app is
answered inside the step that made it; the company-details step is not.
Collecting a company's details is a human step that takes hours, so the host
starts it as an Oban job and tells the chart nothing yet. The drive reaches
quiescence and the run **persists with the invocation still live** - no
process is holding it, and the header reads `running` rather than `done`. Kill
the server here and the call is still outstanding when it comes back.

**See**, a moment later, without touching anything: the feed is replaced by a
second, shorter reading of `Runs (17)`, and the run finishes.

```
0  | Run resumed from storage | 868edf9bf6eb15ac3e3e58427b57a105 (active)
1  | Entered           | Collect the company details
6  | Invoke dispatched | myapp:provision on Create the workspace
7  | Performed         | myapp:provision -> account=signup-868edf...@example.com, provisioned=created
16 | Run finished      | done
```

That is the job answering, on a process that has never seen this run: it
rebuilt the chart, the position and the run out of SQLite, fed the answer back
through the durable driver's completion door, and the page redrew because the
answer was broadcast. Two readings and not one, for the same reason a resumed
run opens with one row: the feed is derived from the effects a drive returned,
and this was two drives.

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

**See**: the wizard, at `revision 11`, id `bdoc_signup_demo`, `running`, and
one row in a Runs feed of its own:

```
0 | Run resumed from storage | 83aae24cd3331f9d66bef6e983292dba/blk_so_wizard/0 (active)
```

Nothing on that page knows it is anybody's child. It is the wizard, resumed
from storage exactly as section 7 resumed the parent after the `kill -9` -
and resumed **by run id alone**, because the page's own compile is the root
recipe while a child's stored identity is keyed on the child recipe, so the
usual resume-onto-this-canvas path would refuse it. Drive the wizard to the
end here and the parent finishes too, with nobody pressing anything on the
parent's page.

**Do**: go back to the parent's page and press **Stop** while the child is
still live.

**See**: reload the child's URL. It is `cancelled`, and its feed says so:

```
0 | Run resumed from storage | 83aae24cd3331f9d66bef6e983292dba/blk_so_wizard/0 (cancelled)
1 | Run finished             | cancelled
```

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
