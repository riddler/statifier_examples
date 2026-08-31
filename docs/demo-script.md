# The executing signup: a demo script

A numbered walk through the signup wizard as a *running* chart: the authoring
view, a durable run, live block marking, the run feed, a `kill -9` the run
survives, the abandonment nudge, and the account the wizard exists to create.

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
`revision 10`, id `bdoc_signup_demo` - beside the DOCUMENT and THEME
selects, a Compile button and `Findings 0`. The canvas opens at Fit width -
`21 blocks`, `depth 4` - and the
palette on the left offers 26 block types. Nothing is running yet, so the
header shows a **Run** button and no status beside it.

This is the whole point of the beat: what you are looking at is an editor, not
a viewer. The run you are about to start runs *this* document.

## 2. Open the drawer and pick the Runs tab

**Do**: click the drawer strip along the bottom, then the **Runs** tab.

**See**: three tabs - `Truth tables (0)`, `Findings (0)`, `Runs (0)`. The Runs
panel says `no run` and, in place of a table, one sentence: *Nothing is
running. Run, in the header, starts a session on this document in memory.*
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

**Do**: look at the Runs tab, which now says `Runs (18)`.

**See**: eighteen rows, numbered, three columns - `#`, `WHAT`, `DETAIL`. The
ones worth reading out:

```
0  | Run started       | 868edf9bf6eb15ac3e3e58427b57a105
2  | Invoke dispatched | myapp:signup on Collect email and password
3  | Performed         | myapp:signup
9  | Invoke dispatched | myapp:signup on Send the verification email
14 | Delayed send      | signup.reminder_due in 90000 ms
16 | Entered           | blk_su_verify_wait
17 | Delayed send      | statifier_blocks.wait.blk_su_verify_wait in 86400000 ms
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

One row and not eighteen, and the difference is worth saying out loud: the
**marks** come from the stored position, so they are exact. The **feed** is
derived from the effects each step returned, and effects are not stored, so a
resumed run opens with the fact that it was resumed rather than a replay of
its own history.

## 8. Nudge the visitor who never verified

**Do**: press **signup.reminder_due** in the Runs panel.

The script presses the button rather than waiting the 90-second window out,
so the beat is repeatable and the demo stays under five minutes. The event it
sends is the same one the stored job carries.

**See**: the feed jumps to `Runs (38)` and the run finishes. The shape, in
order:

```
1  | Event             | signup.reminder_due
2  | Entered           | blk_su_reminder_due
3  | Event             | statifier_blocks.interrupt.abandon
8  | Invoke dispatched | myapp:notify on Remind them to finish signing up
9  | Performed         | myapp:notify
15 | Entered           | blk_su_onboarding, blk_su_onboarding_deadline,
   |                   | blk_su_onboarding_abandoned
20 | Invoke dispatched | myapp:signup on Collect the company details
27 | Invoke dispatched | myapp:provision on Create the workspace
28 | Performed         | myapp:provision -> account=signup-868edf...@example.com, provisioned=created
37 | Run finished      | done
```

Narrate that honestly, because it is what the chart says: the nudge fires, the
reminder window ends, the visitor is notified - **and then the signup
completes anyway**. Nudged, then signed up. The wizard has no trailing park
after the nudge; adding one is a change to the chart, not to this script.

The header now reads `done`, the three event buttons are disabled again, and
the only active mark left is the root.

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

---

## Two things a viewer will ask

**"Why not press signup.email_verified? That is what a real visitor does."**

Press it and watch: the verification group's resume interrupt fires, the group
re-enters, and the 90-second reminder and the 24-hour wait are both armed
again -

```
18 | Event        | signup.email_verified
20 | Event        | statifier_blocks.interrupt.resume
22 | Delayed send | signup.reminder_due in 90000 ms
26 | Delayed send | statifier_blocks.wait.blk_su_verify_wait in 86400000 ms
```

The run is back where it started, one round later. The only event that
advances *past* the wait is the wait's own event,
`statifier_blocks.wait.blk_su_verify_wait`, and no button offers it - the
buttons are the document's `core.on_event` names, and a `core.wait` is not one
of those. That is a fact about how this fixture is wired, worth showing rather
than hiding: an interrupt that resumes a scope resumes the whole scope, timers
included.

**"Where do the plan and the seat count come from? Nobody typed them."**

They are a `core.assign` block near the top of the document
(`blk_su_collected`), which sets `signup.plan` and `signup.seats` so the A/B
branch downstream has something to guard on. It is a stand-in for the step
that would collect them, not a claim that the form collects them. The `signup`
root the block writes into is declared by the document itself, in a top-level
`datamodel` key beside the tree: which roots a chart's guards read is a
property of that chart, so it travels in the bytes an author edits rather than
in every host that runs it. A host can still declare roots of its own at
compile time, over and above what the document asks for. This one declares
none.
