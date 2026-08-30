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

The dev port is 8645 and is set in `config/dev.exs`. `config/runtime.exs`
overrides it only when `PORT` is set or the environment is `:prod`, so dev
stays on 8645; 8642, 8643 and 8644 belong to other processes and are never
bound here.

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
such a host copies. The verdict beside it reads `clean` or `N findings`, and
it counts the compiler's findings rather than the pane's, so a finding that
names no block is still counted even though there is nowhere to draw it.

What the three documents report today:

- `signup_wizard` - `clean`.
- `card_processing` - `1 finding`, and it is intended: `myapp.legacy_check`
  at depth 7 is deliberately left out of the palette, so the editor's
  unavailable-block chrome and the compiler's `unknown_block_type` finding
  are both exercised on a document you can open.
- `signup_invitations` - `1 finding`, also expected: its `core.subchart`
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
   controls over one history.
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
- **A handler module** is `invoke_types/0` plus `handle/2`: every name the
  module registers, and one call answered or refused with
  `{:error, {:unknown_invoke_type, type}}`. That shape is the one the
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
