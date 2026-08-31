# statifier_examples

A Phoenix application that hosts the statifier family's two canonical example
domains - credit-card processing and a signup wizard with A/B testing - as the
reference embedder for the
[statifier_blocks](https://github.com/riddler/statifier_blocks) editor.

It is an app, not a library: nothing here is published to Hex. What it exists
to show is a host registering its own block types against the editor's
palette, rendering the editor, and running the resulting state charts - and
whether that is pleasant to do.

## Running it

1. `mise install` - provisions the Erlang and Elixir versions `mise.toml`
   pins; CI reads the same two.
2. `mix setup` - `deps.get`, then the tailwind and esbuild installs and one
   asset build.
3. `mix phx.server` - starts the dev server.
4. Open <http://127.0.0.1:8645/>. The home page lists the example documents,
   each linking into the editor.

Two environment variables change what step 3 does, and neither one's effect is
ever committed:

- `PORT` - the dev port is 8645 and is set in `config/dev.exs`.
  `config/runtime.exs` overrides it only when `PORT` is set or the environment
  is `:prod`, so dev stays on 8645 and `PORT=8650 mix phx.server` runs a second
  copy beside it; 8642, 8643 and 8644 belong to other processes and are never
  bound here.
- `STATIFIER_BLOCKS_PATH` - point it at a local `statifier_blocks` checkout and
  `deps/0` swaps the Hex requirement for a path dep on that directory, which is
  how a host-side change is tried against an unreleased editor. Unset, the Hex
  requirement in `mix.exs` is what resolves.

The path arm rewrites `mix.lock` when deps resolve under it, and a hand-edited
dep would rewrite `mix.exs`: **neither change is ever committed.** CI sets
neither variable, so a CI run always resolves `statifier_blocks` from Hex.

## Opening a document in the editor

1. Click a document on the home page, or go to `/editor?doc=<key>` directly.
   The three keys, in the order the switcher offers them:

   | `doc=` | What the document shows |
   |---|---|
   | `card_processing` | intake and a validation branch, then a three-lane authorization group - fraud review, balance check, 3-D Secure - with a `core.send` arming a deadline and two guarded interrupt rules listening on the group's rail; then an outcome branch with capture-retry, a resumable manual-review arm and a receipt tail. It also carries the one deliberately unregistered block type |
   | `signup_wizard` | account collection, a verification group with resume and abandon interrupts, then the A/B branch on the chosen plan - business, personal, or a nudge - and provisioning |
   | `signup_invitations` | a `core.foreach` over the invitees, each running the wizard above as a `core.subchart` child chart with an `on_error` subtree |

2. Switch documents with the header's DOCUMENT select. Edits live in the
   LiveView process, so an edit survives a document switch and does not
   survive a reload - there is no database in this app yet.

An unknown `doc=` is not a 404: the page falls back to the first fixture,
`card_processing`, because a query-string name is a thing somebody typed.

## Themes, and naming a screen by URL

1. Pick a theme with the header's THEME select, or ask for one:
   `/editor?doc=signup_wizard&theme=dark`. The three are `light`, `dark` and
   `brand`; an unknown theme falls back to `light`.
2. Both parameters are read in `handle_params/3` and nowhere else, so any
   screen this app can show has a URL that names it - which is what a
   headless capture, a browser loop and a bug report each need.

The themes are CSS, not an assign: three
`.myapp-page[data-theme="..."]` blocks in `assets/css/app.css`, each
declaring the host's own `--sb-accent-myapp` alongside the package's tokens.

## What Compile shows

The compile runs on every load and again on every edit, so the findings pane
is never answering for a document that is no longer on the canvas. The
header's Compile button re-runs a pass that is already current - it is there
because a host whose compile is expensive wants one, and this page is what
such a host copies. The verdict beside it reads `Findings N` - the drawer's
own title and the drawer's own number, read out of the package through
`StatifierBlocks.Editor.findings_count/3` rather than counted here. There is
one findings number on this page and it is the package's: the compiler
reports what it found, the editor's view model derives findings of its own on
top of whatever the host hands in, and a header counting the first beside a
drawer listing the second is a page disagreeing with itself about one fact.
The wording is the package's too, so there is no singular form and no word
for zero: a document with nothing wrong reads `Findings 0`.

The page also opens at Fit width, because the host passes the package's `fit`
attr - see step 1 of "Copying the reference header".

What the three documents report today:

- `signup_wizard` - `Findings 0`.
- `card_processing` - `Findings 2`, and both are intended.
  `myapp.legacy_check` at depth 7 is deliberately left out of the palette, so
  the editor's unavailable-block chrome and the compiler's
  `unknown_block_type` finding are both exercised on a document you can open.
  The compiler reports one finding for it; the view model derives a second on
  the same block from the same unresolved type, and the drawer lists both. It
  is the document that made the two numbers' gap visible, which is why the
  header now reads the package's.
- `signup_invitations` - `Findings 1`, also expected: its `core.subchart`
  emits the invoke type `statifier_blocks:subchart`, which is the **host's**
  to register, and this app registers only its own `myapp:*` handlers. The
  warning is the ordinary unregistered-handler lint, not a broken fixture.

## Copying the reference header

ADR-0005's shell arrangement, ruling 8A, splits the editing surface from the
document chrome: the package ships the canvas toolbar, the tabbed inspector,
the drawer and the grouped palette, and the **host** ships the outer header -
document identity, the document switcher, the theme control, and compile.
The record is `docs/adr/0005-liveview-editor.md` in `statifier_blocks`,
section "Amendment (2026-08-29): the shell arrangement - three panes and a
drawer". To copy the host's half:

1. Read `lib/statifier_examples_web/live/editor_live.ex`. The header markup
   goes in `StatifierBlocks.Editor`'s `:header` slot: the document's name,
   `revision N` and its id, the DOCUMENT and THEME selects as `phx-change`
   forms, and the Compile button. Undo and redo are deliberately absent -
   they are the package's toolbar, and a second pair here would be two
   controls over one history. The same call passes `fit={:width}`, which is
   how the page opens at Fit width: the fit is the package's to compute and
   the host's to ask for, so a host that wants the whole document in view on
   the first paint says so here rather than reaching for the toolbar's Fit
   button on the reader's behalf.
2. Register **both** hooks in `assets/js/app.js`. `StatifierBlocksDrag` is
   the drag hook and `StatifierBlocksMeasure` is the read-only measurement
   hook; without the second one the editor works but draws no connectors at
   all. Both arrive in the package's default export, so one import spreads
   the pair into `hooks:`. The specifier resolves through esbuild's
   `NODE_PATH`, which `config/config.exs` points at `deps/` - the same way
   this app already resolves `phoenix` - rather than through an
   `assets/package.json` and an npm install.
3. Style the page root, not the editor's internals: `assets/css/app.css`
   redeclares the package's tokens under `.myapp-page[data-theme="..."]`.
4. Bound the editor's height if the page is an application shell rather than
   a page whose only content is the editor. `.myapp-page .sb-editor` sets
   `--sb-editor-height` to the viewport less the page's gutter, which makes
   the editor a pane: the canvas scrolls inside it and the drawer strip stays
   pinned at the bottom of the window instead of falling below the fold on a
   long document. The selector reaches the editor element rather than the
   page root on purpose - the package declares the token's `auto` default on
   `.sb-editor` itself, and a declaration there beats an inherited one.

## Durable runs, and picking one up after a `kill -9`

Pressing **Run** on the editor page starts a *durable* run. There is no
process holding the chart between steps: every step goes
`load -> step -> execute effects -> persist` through
`StatifierPersistence.Runs`, and the chart's position lands in the
`statifier_runs` table before the press returns. The run id goes into the
page URL, which is what makes a run something you can come back to.

Two host pieces make that work and both are worth reading before copying:

- `StatifierExamples.Charts.Durable` is the driver - the loop that steps,
  answers the calls the chart made, and steps again.
- `StatifierExamples.Charts.RunLock` is this app's per-run serialization
  strategy. It is **not optional**: `StatifierPersistence.Runs` defaults to
  the storage adapter's `lock_run/3`, `StatifierExamples.Persistence`
  declines that callback because SQLite has no row lock to take, and the
  default therefore refuses with `{:error, {:serialization,
  :not_supported}}` before a run can start. A host on Postgres takes the
  default; a host on SQLite writes the twenty lines this one writes.

### The walkthrough

1. Start the app and open the signup wizard:

   ```sh
   mix setup
   mix phx.server
   ```

   Then <http://127.0.0.1:8645/editor?doc=signup_wizard>.

2. Press **Run** in the header. The chart runs through two `myapp:signup`
   calls and parks in its verification group, waiting on the 24-hour
   `core.wait` with both interrupts armed. Open the drawer's **Runs** tab
   to watch it: `Run started`, two `Invoke dispatched` / `Performed`
   pairs, and a `Delayed send` for the wait.

3. Look at the address bar. It now carries a `run=` parameter - that is
   the run id, and it is the only thing you need to find this run again.

4. Confirm the run is durable rather than merely running:

   ```sh
   sqlite3 priv/repo/statifier_examples_dev.db \
     "select run_id, status, length(position_blob) from statifier_runs;"
   ```

   One row, `active`, with a position blob of about a kilobyte.

5. Kill the server the hard way, from another shell - no shutdown hook, no
   flush:

   ```sh
   kill -9 $(lsof -nP -tiTCP:8645 -sTCP:LISTEN)
   ```

6. Start it again with `mix phx.server`, and reload the **same URL**,
   `run=` parameter included.

7. The page comes back on the configuration the run was left in: the wait
   block and both interrupt rules are marked active on the canvas, the
   header says `running`, and the Runs tab opens with one row -
   `Run resumed from storage`, naming the run id and its stored status.

8. Press **signup.abandoned** in the Runs panel. The resumed run steps on
   from exactly where it was: the abandon interrupt fires, the
   verification group finishes, onboarding runs its branch, and the chart
   reaches its root outcome. Nothing about the step knows a server died.

### What survives and what does not

Durable: the chart's position after every step, the run's status, and the
account `myapp:provision` writes.

Not durable: the **feed**. Its rows are derived from the effects each step
returns, and effects are not stored, so a resumed run opens with one row
rather than a replay of the run so far. The marks are not affected - those
come from the stored position.

### The one call that writes

`myapp:provision` creates the account row the wizard exists to produce, in
`StatifierExamples.Signup.Accounts`. Two things about it are the point:

- **The run is the key.** The chart carries no datamodel and no personal
  data, so the address is derived from the run id -
  `signup-<run id>@example.com`, fiction like every value in this repo.
- **It is idempotent on that key, honestly.** `StatifierPersistence`'s
  executor contract is at-least-once: a host that crashed between
  executing an effect and persisting the step re-drives the same event and
  gets the same call again, and the stepper never dedupes. The `users`
  table has a unique index on `email` and the write is an upsert against
  it, so a second delivery finds the row and the feed's `Performed` row
  says `provisioned=existing` instead of `created`. No dedup table, no
  guessing.

One caveat the shipped fixture makes visible: the signup wizard's plan
branch reads `signup.plan` and `signup.seats` from a datamodel the
document does not declare, so every run of *that* document takes the
`otherwise` arm and abandons before it reaches its provision block. The
write is exercised by `StatifierExamples.Charts.DurableTest`, on a
document built in the test for the purpose.

## The gate

```sh
mix quality --profile loop   # inner loop: format, compile, credo, changed tests
mix quality                  # full gate: + dialyzer, deps audit, coverage floor
```

Full `mix quality` must be green before any commit. `.quality.exs` records what
the gate does and the one recorded deviation from the family's defaults.

## Layout

| Module | What it holds |
|---|---|
| `StatifierExamples.CardAuth` | the card-processing block types and their invoke handlers |
| `StatifierExamples.Signup` | the signup-wizard block types and their invoke handlers |
| `StatifierExamples.Charts` | shared host plumbing: the palette, the icon seam, the theme tokens, the fixture list |
| `StatifierExamples.Charts.Durable` | the durable run driver: step, answer the chart's calls, step again |
| `StatifierExamples.Charts.RunLock` | the per-run serialization strategy durable steps run inside |
| `StatifierExamples.Persistence` | the storage adapter and the `statifier_persistence` host declaration |

Both domains are filled. `StatifierExamples.Charts` also carries the shared
messaging block type `myapp.notify`, which belongs to neither domain, and
`invoke_types/0` - the union of every handler the app registers, which the
compiler reads as `:known_invoke_types`.

### One step helper, one handler shape

A reference embedder that showed two ways to write the same thing would be
teaching the reader to pick, so there is one of each and both domains use it:

- **`StatifierExamples.Charts.Step`** is the only step helper. Every host
  block type in both domains declares its schema with `config_schema/2`,
  checks it with `check_invoke_type/2` and `verdict/1`, and compiles with
  `emit/4` - which takes the type's own invoke type as the default and
  whatever `<param>` children it wants. It lives under `Charts` because that
  is the seam the domains meet in, next to the palette and the fixture list.
- **A handler module** is `invoke_types/0` plus `handle/3`: every name the
  module registers, and one call - `type`, the `<param>` values, and the
  driver's own call context - answered or refused with
  `{:error, {:unknown_invoke_type, type}}`. The context is empty from the
  in-memory driver and carries `run_id` from the durable one; only
  `myapp:provision` reads it, because only it writes. That shape is the one the
  runtime asks for - st-ADR-0051 registers handlers per session as a
  `%{invoke type => module}` map - and it is what makes
  `Charts.invoke_types/0` a concatenation of three identical calls.
- **Two outcomes, `done` and `error`**, in that order, labelled "Done" and
  "Error". The label is the outcome's own name, which is also the compiled
  event's (`error.communication.invoke`), so a card and a chart say one word
  for one thing.

A step whose config stores no `invoke_type` is naming the default its schema
declares - the one place "the usual handler" is written down - so an absent
key compiles and validates, while a stored value outside the `myapp:*`
grammar is a finding.

## Fixtures

`priv/fixtures/` holds the example block documents, decoded strictly at
compile time and listed by `StatifierExamples.Charts.fixtures/0`. A fixture
that does not decode fails the build.

`card_processing.json` is ported from the `statifier_blocks` spike. It is
byte-faithful to the spike document - every block id, revision, label and
invoke type - except for four deliberate differences, all of which exist
because the shipped vocabulary is not the spike's proposed one:

- the spike's `_comment` keys are stripped, once, in the file: the strict
  decoder rejects them, and stripping at load time would mean shipping a
  fixture no other reader of the format can use;
- `core.invoke`'s `params` is the shipped `name=path`-per-line string rather
  than the spike's map;
- the spike's proposed `core.timeout` block is ported onto the pair of
  **shipped** types that models a clock interrupt: a `core.send` arming
  `card.authz_timed_out` at the head of the authorization group's
  body, and a `core.on_event` on that group's interrupt rail listening for
  it. Nothing in this app registers a `core.*` name - the vocabulary is
  `statifier_blocks`' to grow;
- the two guarded interrupt rules keep their `cond` config key, which the
  shipped `core.on_event` **does not read**. The spike proposes that key on
  that type; until `statifier_blocks` ships it, the guard is authored and
  inert, and dropping it would quietly lose what the document says.

`myapp.legacy_check` is deliberately left unregistered, at depth 7, so the
editor's unavailable-block chrome and the compiler's unknown-type finding are
both exercised.

Every fixture, seed and example value in this repository is fictional.

## The rules that are not in this file

`CLAUDE.md` carries the ones a change here has to honour, including the rule
that the example domains are the two canonical ones and nothing else.
