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
   The eight keys, in the order the switcher offers them - which is
   `StatifierExamples.Charts.fixtures/0`'s order, card processing first:

   | `doc=` | What the document shows |
   |---|---|
   | `card_processing` | intake and a validation branch, then a three-lane authorization group - fraud review, balance check, 3-D Secure - with a `core.send` arming a deadline and two guarded interrupt rules listening on the group's rail; then an outcome branch with capture-retry, a resumable manual-review arm and a receipt tail. Every block type it names is registered, so it compiles clean and a finding on it is one an author produced |
   | `card_processing_sketch` | the same payment flow caught halfway through being authored sink-backwards: the tail the author already knows parked in a `core.drafts` tray, and the middle nobody has decided yet standing as a `core.placeholder`. Both are author warnings, so this is the one shipped document that does not read `Findings 0` |
   | `card_processing_composite` | the same three-lane authorization arrangement as one block. `myapp.authorize_with_deadline` is a **composite** - params plus a pure subtree - and it stands for exactly what `card_processing` spells out by hand: the group, the `core.send` arming the deadline, the `core.parallel` of three lanes, and the `core.on_event` on the rail. The two documents compile to the same bytes, which is the whole reading: what an author fills in is eight fields, and what the engine runs is the arrangement |
   | `signup_wizard` | account collection, a verification group with resume and abandon interrupts, then the A/B branch on the chosen plan - business, personal, or a nudge - and provisioning |
   | `signup_invitations` | a `core.foreach` over the invitees, each running the wizard above as a `core.subchart` child chart with an `on_error` subtree |
   | `signup_onboarding` | the smallest document here, and the one reading it exists for: a single `core.subchart` running the wizard, with `on_done`, `on_abandon` and `on_error` each routing to a `myapp.notify`. The child really runs, because a root session started with `inherit_invoke_handlers: true` hands its handler map down |
   | `signup_bulk_invites` | the fan-out shape: a `core.assign` seeding ten chunk descriptors, then a `core.map` running `signup_invite_chunk` once per descriptor with `collect: "results"` and `on: "all"`, then a confirmation step. Ids are what fan out, never invitee rows - the list is serialized on every persisted step |
   | `signup_bulk_invites_strict` | the same document with two characters changed: one descriptor is a deliberate bad id, and the `core.map` runs `on: "first_error"`. It is the pair that makes the two failure policies readable side by side |
   | `signup_guarded_step` | one `myapp.guarded_step` block: a call, and a `myapp.notify` on its error path. The second composite, and the pairing an author forgets - which is the argument for having composites at all |
   | `signup_invite_chunk` | the child the two bulk documents fan out over: one `core.invoke` of `myapp:process_rows` for the chunk a descriptor stands for, answering a summary. It is offered in the switcher because a child chart is a document like any other |

2. Switch documents with the header's DOCUMENT select. Edits live in
   `StatifierExamples.Documents`, one process holding one map, so an edit
   survives a document switch and a reload and does not survive a restart -
   nothing writes a document to disk. The app does have a database:
   `StatifierExamples.Repo`, on SQLite, carries `statifier_persistence`'s
   run storage rather than documents.

An unknown `doc=` is not a 404: the page falls back to the first fixture,
`card_processing`, because a query-string name is a thing somebody typed.

The same document has a second page: `/plan?doc=<key>`, which reads it as a
list of steps instead of a canvas (`StatifierExamplesWeb.PlanLive`). It takes
the same `doc=` and `theme=` parameters plus `readonly=1`, and its
`Open in editor` link and the editor's own page are two views of one
document, which is what the store above is for.

## What the Plan view copied, measured

Re-measured 2026-09-08 (`se-7p1`), on the `statifier_blocks` commit
`6d54afe13ca96196431c674231e24e50e3803b2f` (`6d54afe`), which `mix.exs` was
pinned at when the measurement was taken; `se-t73` advanced the same pin to
`6fa6a2a6d437521cfe3f8dda2b8eb31e268ead3e` (`6fa6a2a`) for `sb-hwlr` and
`sb-59rt`, both card-face changes across which `plan_live.ex` is
byte-identical. `se-9nn` has since retired the pin for the Hex requirement
`~> 0.27`: both commits are ancestors of `v0.27.0` (`4c63b1a`), so the
release carries the tree every count below was read on, and the whole suite
reads the same at the pin and at the release.

What the `se-7p1` pin bought is the last row this table still named as a
copy: `sb-ykkl` promoted
`StatifierBlocks.Editor.ConfigForm.config_form/1` to a call a host
composes, with an `event` attr and an omittable `target`, and the Plan
view's read-only/editable pair around `Editor.Field.field/1` - the twenty
seven lines of markup **every** embedder wrote identically - is one
component call now. The unrouted-findings paragraph above the form went
with it, because `config_form/1` draws that bucket at the form's head
itself, and `unrouted_findings/1` went with the paragraph.

The honest half of the entry: this file did not get shorter. It is 860
lines against 877 before the uptake, and against the 842 the measurement
below read - `se-ezz` added the insert picker's recipe rows in between.
The markup column is what moved, from 284 lines to 266; the twenty seven
that went were replaced by seven, and the rest of the difference is the
moduledoc growing by the paragraphs recording what this page now composes
rather than draws. A promotion buys a page fewer decisions, not fewer
lines, and the count that matters is that there is no field-surface
fragment left here for a second embedder to copy.

Every span in the table below was re-run in this pass by the method the
paragraph under it names.

Re-measured 2026-09-07 (`se-6jn`), on the `statifier_blocks` commit
`eb64d4cbe8b038021b2a62a10b4b5bc15028c2fd` (`eb64d4c`), which is where
`mix.exs` was pinned when the measurement was taken. The pin advanced once
more after it - to `e61890a`, for `se-1q8`'s pass-through slots - and
`se-c9l` has since retired it for the Hex requirement `~> 0.26`; `eb64d4c`
is an ancestor of `v0.26.0` (`f9b62c5`), so the release carries the tree
the measurement was taken on. The measurement before it was taken on
`3a210a9`, an ancestor of `v0.25.0` (`7186b24`) and so of this commit;
every cite below is by module, function and clause rather than by line in
the package, and every one of them resolves on both. What moved between the two is the
subject of this pass: `sb-8fa8` keeps a refused
`Edit.Session.change_config/3`'s per-field findings in the session's
`draft_findings` and routes them with `ViewModel.overlay_findings/2`,
which took two near-verbatim fragments out of this file, and `sb-6xkf`
promoted the three transparent-container readers, which took none - this
page draws no container through. Both numbers are below. The first
measurement was taken on `ea2fdee` and is what `se-avi` acted on: it read
`StatifierExamplesWeb.PlanLive` fragment by fragment, said of each whether
it was a copy of something inside the package's editor, and recommended
promoting the ones that answer a question about a document rather than
decide how a page is laid out. Fourteen of those recommendations landed in
`statifier_blocks` as public functions (`sb-0buo`, `sb-mcs8`), and this
page deleted its copies of them.

That is what this table now measures: not what a second embedder *would*
have to copy, but what one still does.

`StatifierExamplesWeb.PlanLive` is 860 lines
(`wc -l lib/statifier_examples_web/live/plan_live.ex`); each row's count
below is `sed -n '<first>,<last>p' lib/statifier_examples_web/live/plan_live.ex | wc -l`
over the span named in the row. Of those 860, **0 lines are verbatim
copies** of the package editor's private helpers, **9 are near-verbatim**,
and **851 are the host's own** - 129 of them the moduledoc and 266 of them
this page's markup. The spans named in the table cover 836 of the 860; the
other 24 are `defmodule`, the closing `end`, and the blank line between one
span and the next, and they are the host's own by default.
`lib/statifier_examples/documents.ex`, the store both pages share, is a
further 81 lines with no package counterpart at all.

The three numbers to read against `ea2fdee`'s 35 / 183 / 649 are 0 / 9 /
851, where the pass before this one read 0 / 9 / 833 and the one before
that 0 / 57. What is left of the near-verbatim column is
`to_index/1` and nothing else, and it is left on purpose: the two functions
disagree about what an unparseable index means, and this page means the
other thing. There is no fragment of this file a second embedder has to
copy any more.

The last 48 of those lines went in one piece, and the reason is worth
reading as the pattern rather than as an entry. `se-f4a` added
`route_findings/3` and `draft_findings/3` here because a refused
`Edit.Session.change_config/3` discarded the findings its own refusal
carried, so the page had to re-derive them by running
`BlockType.validate_config/1` over the draft a second time. That was
recorded in the row below as **residue** - an `sb` bead rather than a shim -
and `sb-8fa8` is that bead landing: the findings are kept in the session's
`draft_findings` and `ViewModel.overlay_findings/2` routes them onto the
form. The host code went with the second derivation, which is what a
promotion is supposed to look like from this side.

The other half of the same pass deleted nothing, and that is the honest
entry. `sb-6xkf` promoted `ViewModel.transparent?/2`, `effective_parent/3`
and `end_of_list_target/3` for a host that FLATTENS containers out of its
own outline. This page flattens nothing - every block the walk hands over
is drawn - so it adopts none of the three and its `gap_target/2` stays
host-original. What it took instead is a test
(`StatifierExamplesWeb.PlanLiveTest`, "the transparent-container readers"):
with the caller's type list empty, which is this page's list, the package's
reader gives the same answer this page's own `ViewModel.positions/1` map
does, for every block of every fixture. A promoted reader a host does not
call is still worth pinning against, because the day the two disagree one
of the two views of this document is wrong about where a row sits.

A promotion pass that shrinks a host page is a pass that promoted the
page's own decisions by mistake; what these have bought is that the
fragments left are the ones nobody else has to write.

| Fragment (span in `plan_live.ex`) | Lines | What it mirrors at `3a210a9` | Kind | Note |
|---|---|---|---|---|
| Moduledoc, including the public-API table (L2-130) | 129 | - | host-original | The table is fifteen rows of public API, and the paragraph under it says which copies went |
| `use`, the aliases, `@default_theme` (L132-147) | 16 | - | host-original | Page wiring |
| `mount/3`, `handle_params/3`, `select-document`, `select-row` (L149-184) | 36 | - | host-original | Page wiring. `sb-gbxt` made `selected_id` a host-written input assign on `StatifierBlocks.Editor`; this page mounts no editor, so there is nothing here for it to drive - the assign it writes is its own |
| Read-only write guard, the `handle_event/3` catch-all (L186-210) | 25 | nothing; `read_only?` is a `StatifierBlocks.Editor` profile key and this page mounts no editor | host-original | `se-4v1` asked for this to go. It stays: `docs/profiles.md` says `read_only?` "is not an authorization boundary". 20 of the 25 lines are that argument written down |
| `config-change`, `discard-draft`, `field-list-add`, `field-list-remove` (L212-240) | 29 | `lib/statifier_blocks/editor.ex:handle_event/3`, the four same-named clauses | host-original shape, package calls | A `phx-` binding belongs to the page that draws the control; what each one calls is now `Edit.Session`'s |
| `insert-open`, `insert-close`, `insert` (L242-288) | 47 | `editor.ex:handle_event/3`, `palette-open` / `palette-close` / `palette-pick` | host-original shape, package calls | `Palette.new_block/2` and `Session.commit/2` |
| `move`, `remove` (L290-311) | 22 | `editor.ex:handle_event/3`, `"remove"`; there is still no move clause - the canvas moves by drop | host-original | Two buttons are a list's answer to a gesture the canvas needs a pointer for |
| `undo`, `redo` (L313-319) | 7 | `editor.ex:handle_event/3`, `"undo"` and `"redo"` | host-original shape, package call | Both are `Session.step/2` now; the host's own `step/2` is gone |
| `render/1`, the page chrome (L321-434) | 114 | - | host-original | A page layout, which is exactly what does not promote |
| `row/1`, one outline entry (L436-587) | 152 | composes `lib/statifier_blocks/editor/config_form.ex:config_form/1` unchanged; the surrounding markup is new | host-original | **The pair is gone.** L489-506 was the read-only/editable pair around `Field.field/1` that every embedder wrote identically; `sb-ykkl` promoted `config_form/1` with an `event` attr, an omittable `target` and the hidden `block-id` input, and `se-7p1` replaced the twenty seven lines with the seven-line call at L516-522. The unrouted-findings paragraph above it went too: the component draws that bucket itself |
| `refused_fields/1` (L589-601) | 13 | - | host-original | New on `se-f4a`. What a refused draft is *about*, as words on the page: the field labels in the pending sentence. `unrouted_findings/1` was the other half until `se-7p1`, and it went with the paragraph that drew it - `config_form/1` renders `form.unrouted` at the head of the form. Both read fields `ViewModel.overlay_findings/2` wrote |
| Param and path helpers, `load_document/2` (L603-658) | 56 | - | host-original | `load_document/2` builds the `Edit.Session` the page holds |
| `apply_session/2` (L660-672) | 13 | - | host-original | What replaced the host's `commit/2`, `change_config/3` and `step/2` - 55 lines of near-verbatim down to 13 of "assign it, store it if the document moved". The gate, the undo stack, the draft treatment and the refusal vocabulary are all `Edit.Session`'s |
| `update_list/3` (L674-690) | 17 | `lib/statifier_blocks/edit/session.ex:update_list/4` | host-original | Only the key-to-field lookup is left - the crafted-payload guard. The rows, the `value_path/1` write and the commit are the package's |
| `to_index/1` (L692-700) | 9 | `editor.ex:to_index/1` | near-verbatim - returns `-1` where the package returns `0` | Keep host-side: the two disagree about what an unparseable index means, and that disagreement is deliberate here. The whole of the near-verbatim column, as of `se-6jn` |
| `store/1` (L702-706) | 5 | - | host-original | This app's document store |
| `rebuild/1` (L708-734) | 27 | `editor.ex:rebuild/1` | host-original - same name, different projection: three outline buckets, no run, marks or fit | The `positions` line is `ViewModel.positions/1`; the 53-line host walk is gone. It destructures `draft_findings` off the session now, which is the whole of what `sb-8fa8` cost this function |
| `overlay_draft/3` (L736-766) | 31 | wraps `ViewModel.overlay_draft/2` and `ViewModel.overlay_findings/2` | host-original | An outline entry is a `{node, depth, kind}` triple and both package functions take a node, so this is the unwrap and nothing else - 17 of the 31 lines are the comment recording which copies went and why. `route_findings/3` (29) and `draft_findings/3` (19) were here until `se-6jn`; the 21-line value-overlay copy and the 10-line `drafted_field/2` went before them |
| `assign_insertable/1`, `insertable/2` (L768-809) | 42 | `editor.ex:accepted_types/3` | host-original shape, package call | The 38-line copy with its own `fits?/5` probe is gone: `Edit.Targets.accepted_types/4` answers with a `MapSet` of type names and this filters the entry list by membership, so the two views can no longer answer the fit question differently. `Assignability.context/1` replaced the verbatim host clause pair |
| `position/2` (L811-813) | 3 | - | host-original | A lookup in the `ViewModel.positions/1` map |
| `gap_target/2`, `first_body_target/2` (L815-842) | 28 | `ViewModel.effective_parent/3` and `end_of_list_target/3` answer the same question for a host that flattens containers | host-original | Where the "+" under a row inserts is this page's question about its own control. `sb-6xkf` promoted the readers for a flattened outline; this page draws every container, so it keeps `position + 1` and takes a test instead - with an empty type list the package's reader and this page's `positions` map agree, for every block of every fixture |
| `fields_for/2` (L844-848) | 5 | `ViewModel.fields_for/2` | host-original | One line: the socket-to-view-model unwrap. The 7-line copy and the 8-line `find_node/2` under it are gone |
| `error_sentence/1` (L850-859) | 10 | - | host-original | The refusal reasons are the package's, the wording is the host's |

### What went, and what it cost the package

Fourteen fragments the first measurement recommended promoting are gone
from this file, two more went on `se-6jn`, and the field-surface pair went
on `se-7p1`. The package answers each of them now:

| What this page held | What it calls at 0.27.0 |
|---|---|
| `sentence/1` (9) | `ViewModel.sentence/1` |
| `shown_fields/1` (9) | `ViewModel.shown_fields/1` |
| `find_node/2` (8) | `ViewModel.find_node/2` |
| `fields_for/2` (7) | `ViewModel.fields_for/2` |
| `positions/1` and `/2` (53, with `position/2`) | `ViewModel.positions/1` |
| `overlay_draft/2` (21) | `ViewModel.overlay_draft/2` |
| `drafted_field/2` (10) | `ViewModel.drafted_field/2`, through the above |
| `effective_config/2` (7) | `Document.effective_config/3` |
| `committed_config/2` (7) | `Document.committed_config/2` |
| `commit/2` (17) | `Edit.Session.commit/2` |
| `change_config/3` (23) | `Edit.Session.change_config/3` |
| `step/2` (15) | `Edit.Session.step/2` |
| `update_list/3` (23) and `apply_gesture/2` (3) | `Edit.Session.update_list/4` |
| `insertable/2` + `fits?/5` (38) and `assignability_context/1` (6) | `Edit.Targets.accepted_types/4` + `Assignability.context/1` |
| `route_findings/3` (29) and `draft_findings/3` (19), added on `se-f4a` and deleted on `se-6jn` | `ViewModel.overlay_findings/2`, over `Edit.Session`'s `draft_findings` (`sb-8fa8`) |
| the read-only/editable field pair (27) and `unrouted_findings/1` (7), deleted on `se-7p1` | `Editor.ConfigForm.config_form/1`, with `event`, `target` and `read_only` (`sb-ykkl`) |

Three of the promoted shapes are not the shapes this page had, and the
difference is the package's decision rather than a mismatch to work
around. `update_list/4` carries the member path this page's arity-3 copy
had deleted; `apply_gesture/2` takes a `ViewModel.Field` rather than raw
rows, so a `{:type_expr, opts}` field gets a blank member and a `{:list, t}`
gets a blank string; `step/2` takes `:undo | :redo` where this page passed
a function. `accepted_types/4` answers with type **names** rather than
palette entries, which is why the host still owns the one line that filters
its own entry list. Each of those is a widening, and this page took the
wider one.

### The number that decides the next pass

0 verbatim, 9 near-verbatim. The 9 is one fragment, `to_index/1`, and it is
a deliberate disagreement: the package answers `0` for an unparseable index
and this page answers `-1`, because a crafted payload should not silently
mean "the first row". Promoting it would mean promoting the disagreement,
so it stays.

The pass before this one ended here with 57 and named the reason for the
other 48: `Edit.Session.change_config/3` was handed the per-field findings
by `History.commit/4` and threw them away, so every host wanting the
sentence "which field was refused" re-ran `validate_config/1` against a
config the package had validated microseconds earlier. `sb-8fa8` is a
`Session` that keeps them, and the 48 went to zero exactly as predicted.
That is the whole argument for measuring this file: the number named the
bead, and the bead moved the number.

That pass ended by pointing at the one shape still written by hand here
that another embedder would also write by hand: `row/1`'s L489-506, the
read-only/editable pair around `Field.field/1`. It said the shape was a
component, not a layout, so D16 admits it - and that it belonged in the
package as a `config_form/1` rather than as a promotion out of this file.
That is what `sb-ykkl` did and what `se-7p1` took up, which is the same
argument closing a second time: the measurement named the shape, and the
package grew the component rather than this file shrinking around a copy.

So this pass has no fragment to point at either, and none in reserve.

Everything else in the file is this page: its layout, its parameters, its
store, its write gate, and the words it uses for a refusal. That is the
D16 line - components promote, layouts do not - and it is now where the
measurement says it is rather than where the direction said it should be.

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

What the eight documents report today - seven `Findings 0`, and one that is
supposed to have something to say:

- `signup_wizard` - `Findings 0`.
- `card_processing` - `Findings 0`. It read `Findings 2` until 2026-09-06
  (se-bv9), because `myapp.legacy_check` at depth 7 was deliberately left out
  of the palette: the compiler reported one `unknown_block_type` finding for
  it, the view model derived a second on the same block from the same
  unresolved type, and the gap between those two numbers is what made the
  header read the package's rather than count for itself. What that cost was
  the rest of the document. The compiler reports findings from the FIRST
  FAILING STAGE only, so an unresolvable type at depth 7 hid every later
  stage of this document from the editor - including the type refusal the
  card-processing domain is authored to demonstrate, which could be asserted
  in the suite but never seen on the page. The type is registered now, the
  document compiles clean, and a finding on it is one an author produced.
  The unavailable-block chrome belongs to `statifier_blocks` and is covered
  there.
- `signup_invitations` - `Findings 0`. It read `Findings 1` until 2026-08-31
  (se-4dt.4), because its `core.subchart` emits the invoke type
  `statifier_blocks:subchart`, which is the **host's** to register, and this
  app registered no handler for it: the standing number was the ordinary
  unregistered-handler lint, not a broken fixture.
  `StatifierExamples.Charts.Subchart` gives the canonical handler
  `statifier_blocks` ships the two callbacks a host owes it - a document-id
  lookup over the fixture list, and the palette a child compiles against - so
  the type is registered now and the lint is retired.
- `card_processing_sketch` - `Findings 2`, and that is the document working.
  Both are `:warning`/`fault: :author` findings from the `:emit` stage: a
  `placeholder_block` on `blk_cps_gap`, and a `draft_blocks_present` on
  `blk_cps_drafts`. A sketch is a document somebody is still writing, and
  neither an unwritten step nor a parked fragment survives publication, so a
  sketch reading `Findings 0` would be the bug.
- `card_processing_composite` - `Findings 0`.
- `signup_guarded_step` - `Findings 0`.
- `signup_onboarding` - `Findings 0`.
- `signup_bulk_invites` - `Findings 0`.
- `signup_bulk_invites_strict` - `Findings 0`. Its deliberate bad chunk id is
  a **runtime** fact, not a compile-time one: `first_error` is what a run does
  with the failure, and the compiler has nothing to say about a string.
- `signup_invite_chunk` - `Findings 0`.

## The typed environment, and the two answers it gives

The card-processing domain declares what its paths hold, so the editor and
the compiler can refuse a document that contradicts itself. The declarations
live in `priv/fixtures/card-processing.datamodel.json` - a
`statifier_datamodel` document, keyed on the **domain** rather than on one
chart, so all three card-processing charts - `card_processing`,
`card_processing_sketch` and `card_processing_composite` - share one
vocabulary. The composite document joined them on 2026-09-07 (`se-0u1`);
until then it carried no `metadata.domain` and was the one card chart the
advisories were off for. Joining meant declaring what it writes:
`myapp.authorize_with_deadline` records each lane's answer at
`<lane name>.result`, so the three lane roots its defaults name -
`fraud_review`, `balance_check` and `three_ds` - each carry a `result` in
the datamodel document. It carries three scopes of declared paths and a fourth key,
`types`, naming two records and a shape: `cards.credit_txn`, what the flow is
about; `cards.settlement`, what a settled amount would be; and `Settleable`,
the amount-and-currency pair a capture needs and no more.

Nothing flows between adjacent blocks. Every value is written to a path by
name and read from one by name, so the question at any position is what the
document has written on the way there. `myapp.intake` is the entry block, and
its palette entry names the subject - `cards.current_txn` - so its `produces`
leaves a `cards.credit_txn` at that path for everything after it.

From there the two answers this example exists to show:

- **Satisfied.** `myapp.capture` reads `Settleable` at the subject. A credit
  card transaction is not a `Settleable` and nothing declares the two
  related - the read passes on **coverage**, because the record carries every
  field the shape requires. That is why a step asks for a shape rather than
  for a record: it says what it needs and stays out of the business of what
  it will be handed.
- **Refused.** `myapp.receipt` reads a `cards.settlement` at the path its
  `Settlement read from` field names. Pointed where the document points it,
  the document declares that path as the `cards.settlement` record, so the
  read meets exactly what it expects - no finding. Point the same field at
  `cards.current_txn` and it
  is refused, naming the path: *this block reads "Settlement" at
  cards.current_txn, where "blk_cp_intake" left "Credit card transaction"*.
  Two declared records do not widen into one another, and the message reads
  the labels the datamodel document declares rather than the nominal names.

One field value is the whole distance between them, so both verdicts are
reachable from the editor without touching any code. The drawer's Datamodel
tab is the third surface: select a block and it lists the paths the
environment holds *at that position*, and beneath them the declared records
and shapes with their required marks - which is where an author reads what a
shape wanted when a read of theirs is refused.

The declarations reach the condition editor too. A path declared `integer`
projects to the expression language's number kind, so a clause on it offers
the numeric operators rather than whichever set its current source happens to
imply. The risk branch's high-risk arm is a lone `risk_rating >= 70` on
purpose: a compound condition has nothing for the structured picklist to open
on, and a single comparison on a declared path opens straight into it.

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

`docs/demo-script.md` is the same ground as a numbered beat list to read out
loud with the app in front of you - what to press, and what you should see
when you press it, through to the account the wizard creates.

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
   reaches its root outcome and finishes - the header says `done` and the
   `statifier_runs` row is `completed`. Nothing about the step knows a
   server died.

   Finishing at all is an opt-in: the page compiles with
   `terminate: true`, which is what gives the emission a top-level
   `<final>` per root outcome. Without it the root block's outcome finals
   are children of the root compound state, so completing the root block
   raises `done.outcome` internally and the session stays active forever.
   The option changes the generated bytes and therefore the content hash
   chart identity is keyed on, so it is a property of the chart rather
   than of a run: a run stored in the dev database **before** this option
   was passed belongs to the old hash and will not resume. Delete the
   database (or just start a fresh run) rather than looking for a way to
   carry one across.

### What survives and what does not

Durable: the chart's position after every step, the run's status, the
account `myapp:provision` writes, and - since se-dh0 - the run's **inputs**.

The inputs are the newest of those and the one that changed what this page
shows. `statifier_persistence`'s ADR-0010 adds an optional per-run input
log to the storage adapter: every event that reaches the interpreter is
appended, verbatim, inside the same exclusion the step runs in, stamped
with the door it entered by and a dense ordinal.
`StatifierExamples.Persistence` exports the three callbacks that opt in,
V05 in `priv/repo/migrations` creates the table, and
`StatifierExamples.Charts.Replay` maps the log back into the recording
statifier-ui replays.

So a resumed run no longer opens with one row saying it was picked up. The
whole run comes back: the editor page replays the stored inputs into the
same wire-format message stream a live session produces and seats it in
`statifier_blocks`' Run pane, which is where the marks, the scrubber and
the event log now come from. Scrubbing back moves the marks, because the
marks are read off the run rather than off whatever this process watched.

Two things that costs, said out loud. The log stores document payload - an
event's `data` is the host's own values - so turning it on is a
data-retention decision and not a debugging switch; the cap
`StatifierExamples.Persistence.init/1` declares is this app's answer for a
demo database. And the pane's own send control stays disabled for a run of
this app's: it writes into a live `Statifier.Session` server, and a durable
run has no process at all. The event buttons are in the page header
instead, beside Run and Stop.

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
  it, so a second delivery finds the row rather than raising. No dedup
  table, no guessing.

The shipped fixture reaches that block. Its plan branch guards on
`signup.plan` and `signup.seats`, and both halves of making that work are
the host's: the fixture declares the `signup` root the guards read - a
block document cannot declare its own datamodel roots - and a `core.assign`
near the top of the document sets the two values, standing in for the step
that would collect them. `StatifierExamples.Charts.DurableTest` exercises
the write on that fixture rather than on a document built in the test, so
the run the demo does is the run the suite covers.

### A chart that embeds another chart, durably

`Signup onboarding` runs the whole wizard as a child chart, through one
`core.subchart` block naming the wizard's document id. On the durable path
the child is not something the parent holds: it is **its own persisted
run**, with its own row in `statifier_runs`, its own position, its own
status, and a run id that goes in the page URL like any other.

Press **Run** on
<http://127.0.0.1:8645/editor?doc=signup_onboarding> and the parent's Run
pane narrates the hand-over: the subchart block's invocation goes out, and
when the child finishes, the answer comes back as an ordinary
`done.invoke.blk_so_wizard` macrostep in the parent's log.

That the parent narrates its child at all is a property of the input log
rather than of anything this app writes. ADR-0010 decision 7 keeps one log
per run - a child is an ordinary run with a log of its own, and nothing
merges the two - but the child's **answer** reaches the parent through
`Driver.answer_parent/3`, which re-enters the parent through its own
invocation door. So the answer is one of the parent's own inputs, and the
parent's pane shows it without joining anything. What the parent's log does
not hold is the child's own steps, and it should not: those are the child's
run, and reading them means opening the child's run id in the page.

That id is not random. It is the parent's, plus the invocation, plus the
child index, so a child id strictly extends its parent's - which is what
makes the tree acyclic and the cascade below terminate. Open it and you
are looking at the wizard as a run of its own:

```
http://127.0.0.1:8645/editor?doc=signup_wizard&run=<parent>/blk_so_wizard/0
```

Drive it to the end there. The parent finishes too, without anybody
pressing anything on the parent's page: when the child reaches a terminal
status the driver answers the parent's invocation, and the parent takes
its `on_done` or `on_abandon` slot. Three host pieces make that work and
each is small:

- **`StatifierExamples.Persistence.list_runs_by_metadata/2`** is what opts
  this app into durable subcharts at all. The driver refuses to start a
  child over a store that cannot enumerate one - a child that could never
  be found is a child that could never be cancelled - and enumerating on
  SQLite is a containment test in Elixir rather than the `jsonb @>` query
  Postgres gets. That module's moduledoc says what the scan costs. From
  `statifier_persistence` 0.7.1 the opt-in is that callback **and**
  `supports_metadata?/1` answering `true`: the shipped Ecto adapter says
  `false` off Postgres, because the metadata queries it ships are
  `jsonb` SQL a SQLite backend cannot parse, and this app answers for
  itself rather than inheriting that.
- **`chart_resolver:`** on the driver is how the *child's* driver reaches
  the *parent's* chart, which it does not hold. `statifier_persistence`
  cannot supply it - a stored chart is opaque to the package - so this app
  walks the documents it publishes and matches on the content hash.
- **`StatifierExamples.Charts.Durable.abandon/1` cascades.** Press **Stop**
  on a parent with a live child and the child is cancelled with it.
  Cancellation *retains*: the child's stored position is byte-identical
  afterwards, so a cancelled child is still a run you can open and read.

None of this is in the document. Whether a `core.subchart` runs in memory
or as its own persisted run is host wiring - `statifier_blocks` ships two
handlers for the one invoke type and this app gives both the same
resolver - which is the thing to say out loud, because it means an author
never writes a chart for one deployment shape.

### A batch that runs a chart per chunk, and the one row that gets its own

`Bulk invitations` imports a batch of workspace invitations. It is two
blocks: a `core.assign` that seeds ten **chunk descriptors**, and a
`core.map` - "For every item, run a chart" - that runs the `Invite chunk`
chart once per descriptor and collects the ten answers into `results`.

The rule the shape follows is worth saying in one sentence, because it is
the decision every host embedding this engine has to make:

> **The chart orchestrates batches; the data plane processes rows. A row
> gets its own run only when its processing has to wait or branch on its
> own state.**

So `chunks` holds ten short strings - `su-c01` through `su-c10` - and never
an invitee. That is not tidiness. A run's datamodel is serialized on every
persisted step for the rest of the run, so a fan-out over ten thousand
invitee ids costs what ids cost, and one over ten thousand invitee records
charges the parent for those records forever. What a descriptor stands for
is derived from it, in `StatifierExamples.Signup.Invites`, exactly the way
the wizard's account address is derived from its run id - and for the same
reason, since a start job is at-least-once and the derivation is what makes
the write idempotent.

Each chunk child is one bulk call, `myapp:process_rows`, which writes
twenty-five rows to `invite_outcomes` - a table this app owns and the
engine has never heard of - and answers a summary. Two hundred and fifty
rows are processed by ten runs, not by two hundred and fifty.

**The promoted row.** One invitee's signup waits for a person to verify an
address, which is chart semantics and not a row's. That invitee is
promoted: `StatifierExamples.Signup.Promotion` starts an ordinary durable
run of the signup wizard for it, through the same door the editor's Run
button uses. It is a run you open by URL, resume after a `kill -9`, and
drive to the end like any other, and its id is on that invitee's row. It is
deliberately **not** a durable subchart of the chunk chart: a subchart's
lifetime is its parent's, and a finished batch import should not take a
person's half-driven signup with it.

**Both policies.** `Bulk invitations` waits for every chunk. `Bulk
invitations (stop on first error)` carries the same blocks with `on` set to
"stop on first error", and one descriptor the data plane refuses - so it
shows what `first_error` does: the chunk that fails cancels its siblings,
and the answer is still a dense, index-ordered list, with `"cancelled"`
sitting at the index of every sibling that never ran.

Cancelling those siblings takes two doors, because they are two different
things. A sibling that already has a run is cancelled as a run, by
`statifier_persistence`'s own cascade. A sibling whose **start job** has
not run yet has no run record at all, so nothing in that package can see
it - `StatifierExamples.Charts.FanOut.canceller/0` is what reaches it,
through the driver's `child_canceller:` seam and into
`statifier_oban`'s job table.

**Four host seams, and that is the whole of it.** The adapter answers
`supports_run_outcome?/1` and `list_run_states_by_metadata/2`, without
which a fan-out is refused at open rather than half-started. The
`StatifierOban.Config` names a `:child_starter`, because the scheduling
package creates no runs. The driver is built with a `child_canceller:`,
because the persistence package cannot see an unstarted job. And the
dispatch fun answers a `core.map` `:pending`, because N creates cannot hold
the parent's exclusion. Nothing else in this app knows a fan-out is
happening.

**Two things the shipped vocabulary does not give yet**, said out loud
because a reader will look for them. A fan-out child answers its **outcome
name** and nothing else - `child_use: true` compiles a fixed
`<donedata>` - so the per-chunk summary the bulk handler builds reaches
this app's own table rather than the parent's `results`
list, whose entries carry `%{"outcome" => "done"}`. And a chart still has
no way to say "this run failed" *from the blocks this chunk is built out
of*. Half of that gap closed on 2026-09-06: `statifier_persistence` 0.8.0
fails a run whose chart settles in a top-level `<final>` tagged
`statifier_persistence:run_status` `= "failed"`, and `statifier_blocks`
0.21.0 stamps that tag on the final of any outcome a block type classes as
a failure through its new `failure_outcomes/1` callback. But only
`core.map` and `core.subchart` class one, and the chunk chart is a
`core.sequence` around a single `core.invoke`, whose `error` outcome is
classed as nothing - so its refusal reaches no failure-classed final and
the run would still sit `active` forever.

So this app still translates that - a chunk chart is one bulk call and has
nowhere to rest, so a chunk child that is not terminal when its
create-drive returns is a chunk whose call was refused - and says so
through `StatifierPersistence.Driver.answer_parent/3`, which the package
makes public for exactly a host in this position. That translation is what
`statifier_persistence` ADR-0008's amendment, decision 6, deletes, and the
deletion waits on a way for this chart to reach a failure-classed final.
Both are reported upstream rather than papered over here.

### The abandonment reminder, and why it is a row rather than a timer

The signup wizard nudges a visitor who never verified their email. In the
chart that is two ordinary blocks - a `core.send` with a delay, and a
`core.on_event` in the enclosing group's interrupts - and no new
vocabulary at all. What makes it interesting is where the delay is kept.

`Statifier.Session` arms a delayed send with `Process.send_after/3`, so
the timer dies with the node: deploy during the window and the nudge is
silently gone. A durable run has no process to hold one in the first
place. So this app hands the effect to
[`statifier_oban`](https://github.com/riddler/statifier_oban) instead
(`StatifierExamples.Charts.Timers`), which stores it as an `oban_jobs`
row on the same SQLite file everything else lives in. `statifier_oban`
never owns an Oban instance - this app supplies one, on
`Oban.Engines.Lite`, in `config/config.exs`.

Three things follow, and each is worth seeing:

- **The reminder survives a restart.** `kill -9` the server mid-window and
  the job is still there. When it fires,
  `StatifierExamples.Charts.Timers.Delivery` answers the run-liveness
  question from the stored run's status and hands the event to
  `StatifierExamples.Charts.Durable.deliver/2`, which rebuilds the chart
  and the position out of storage. Nothing in that path has ever seen the
  process that armed the timer.
- **The compiler takes it back down.** Nothing in the document authors a
  cancel: `statifier_blocks` emits one in the `<onexit>` of the scope the
  send was armed in, so leaving the verification window cancels the stored
  job. The same machinery makes the wizard's 24-hour `core.wait` durable,
  because a wait compiles to a delayed send too.
- **A page that is open redraws.** The drive announces itself on the run's
  topic and the editor page adopts the reading, so the nudge appears in
  the Run pane's log while you are watching rather than on the next reload.

The delay itself is **host configuration**, not a fact about the chart:

```elixir
config :statifier_examples, :signup_reminder_delay, "90s"
```

A real product waits a day or two, and the fixture ships `2d` so it says
so. A demo cannot wait two days, and editing the chart down to ninety
seconds would make the example lie about the product. So
`StatifierExamples.Signup` applies the configured duration to the reminder
block as the document is loaded, the test environment configures something
else again, and neither has to pretend to be the other. It does change the
document's bytes, and therefore the content hash chart identity is keyed
on - so a run armed under one delay will not resume under another, which
is the identity guard doing its job rather than a wrinkle to work around.

## The gate

```sh
mix quality --profile loop   # inner loop: format, compile, credo, changed tests
mix quality                  # full gate: + dialyzer, deps audit, coverage floor
```

Full `mix quality` must be green before any commit. `.quality.exs` records what
the gate does and the one recorded deviation from the family's defaults.

One check runs beside the gate and is not part of it. `mix assets.bundle` runs
esbuild over `assets/js/app.js`, which resolves `statifier_blocks` and
`statifier_ui` out of `deps/` through esbuild's `NODE_PATH`, so a dependency
whose `assets/js` no longer bundles fails here. CI runs it as the **Assets
bundle** job on every pull request. It lives here rather than in those
packages because their own gates never bundle - statifier-ui's ADR-0009
decides that, and names an example host as where the bundle should actually be
built. Run it locally the same way; it needs no server and no npm install.

The job runs two legs. **`hex`** bundles the `statifier_ui` this app actually
depends on, the last published release, and it is a required check.
**`statifier-ui-main`** bundles the statifier-ui repository's `main` instead,
by setting `STATIFIER_UI_REF` so `mix.exs` takes the package from git; that
leg is `continue-on-error`, and each leg prints the version or commit it
resolved. The second leg exists because the first one only ever sees released
code, so a bundler break sat unnoticed until the release that shipped it -
ADR-0009's own Note records that weakening. Nothing is pinned for it:
`mix.lock` stays at the Hex resolution, and the override lives in the CI job
alone. To reproduce that leg locally, run `mix deps.get` and `mix assets.bundle` with
`STATIFIER_UI_REF=main` set for both; it rewrites `mix.lock` in the working
tree, so `git checkout mix.lock && mix deps.get` afterwards to come back to
Hex.

## Layout

| Module | What it holds |
|---|---|
| `StatifierExamples.CardAuth` | the card-processing block types and their invoke handlers |
| `StatifierExamples.Signup` | the signup-wizard block types and their invoke handlers |
| `StatifierExamples.Charts` | shared host plumbing: the palette, the icon seam, the theme tokens, the fixture list |
| `StatifierExamples.Charts.Durable` | the durable run driver: step, answer the chart's calls, step again |
| `StatifierExamples.Charts.FanOut` | the fan-out host half: the job that starts one, the seam that creates each child, the door that cancels the unstarted |
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

`myapp.legacy_check` at depth 7 was deliberately left unregistered until
2026-09-06, to exercise the editor's unavailable-block chrome and the
compiler's unknown-type finding. It is registered now (se-bv9): an
unresolvable type in the shipped document masked every stage after
resolution, and the reference embedder is worth more compiling clean than it
is demonstrating a package's chrome.

Every fixture, seed and example value in this repository is fictional.

## The rules that are not in this file

`CLAUDE.md` carries the ones a change here has to honour, including the rule
that the example domains are the two canonical ones and nothing else.
