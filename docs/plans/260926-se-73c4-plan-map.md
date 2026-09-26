# The Plan view's map Implementation Plan

## Overview

Give the Plan view (`/plan`) a laid-out map of the block document as its
default reading, with the indented list kept beside it as the keyboard and
screen-reader path. Ruled by the operator, 2026-09-25: a document-mode map,
laid out by ELK over the blocks view model's outline, click-through to the
editor panel; no geometry stored, no connectors authored, no hand-placed
positions; empty outcome slots marked, not hidden; editing through the four
`StatifierBlocks.Edit` commands - insert at a gap, move, remove, and
`update_config` through `Editor.ConfigForm` in the panel; arm and slot order
kept and pinned by a test; a layout failure draws an error, never a blank
pane; fixtures from the library world; elkjs vendored with its licence and
its size stated. Bead: se-73c4.

It lands as four pull requests, each green on the full gate on its own.

## Current State Analysis

- `StatifierExamplesWeb.PlanLive` (`lib/statifier_examples_web/live/plan_live.ex`)
  draws the indented list from `ViewModel.outline/1`, selects a row with
  `select-row`, draws the selected block's `ConfigForm` inline, and writes
  through `Edit.Session.commit/2` for `insert`, `move` and `remove` and
  `Edit.Session.change_config/3` for a config change. Its moduledoc's table
  is the list of public package APIs the page may use.
- `priv/fixtures/` held card processing and signup documents only; the
  library-world documents under `test/fixtures/` are refusal fixtures.
- `statifier_blocks` is pinned `~> 0.35.0` and locked at 0.35.0.
- No JavaScript in this app lays anything out; the package's editor hooks
  are the only hooks it registers.

## Desired End State

`/plan?doc=library_loan` opens on the map: every block a box, every branch
arm side by side in evaluation order, every empty slot a dashed "Nothing
here yet" marker, a sequence's steps top to bottom. Clicking a box selects
that block and opens its form in a panel; the four edit commands work from
the map and leave the document exactly as the same gesture on the list
does. The list is still on the page, complete, and is what a keyboard or a
screen reader reaches; the map is hidden from assistive technology. A graph
elkjs refuses draws an error pane. The README says what the map is, what it
costs, and why the tests need Node.

### Key Discoveries

- `ViewModel.outline/1` visits a node's body slots, then its rails, then its
  trays, flow children before shelf children; the graph builder walks slots
  in exactly that order so its pre-order block list equals the outline's.
- elkjs 0.9.3 answers a child's position relative to its parent and an
  edge's points relative to the node the edge is declared in; the
  `elk.json.shapeCoords` option did not change that, so the hook adds the
  offsets itself.
- Without `forceNodeModelOrder`, elkjs lays branch arms out of evaluation
  order - in both library documents, in card processing and in two signup
  documents; with it on every container every arm comes back in order. A
  per-container `considerModelOrder` did not throw on these graphs, but it
  stays on the root only, as ruled.
- `ViewModel.Slot` carries empty declared slots (`children: []`), so an
  empty outcome is visible to a consumer without a second lookup.

## What We're NOT Doing

- Storing any position, size or connector anywhere, or hand placement.
- Removing, hiding or reordering the indented list.
- Moving the map into `statifier_blocks`, or any record for that move.
- A chart (compiled state) view, a compact density mode, or edges derived
  from the compiler.
- Changing any card or signup fixture.

## Implementation Approach

The server owns every fact about the document (which boxes, their words,
their estimated sizes, their order, the ELK options); the hook owns only
where the boxes go and how they are drawn. That keeps the order pinnable
in Elixir and the hook small enough to test through Node.

## PR 1: Layout

### Changes

- `mix.lock`: `statifier_blocks` 0.35.0 -> 0.35.1, no other package moved.
- `StatifierExamples.Library` and `priv/fixtures/library_loan.json`,
  `priv/fixtures/patron_registration.json`: two `core.*`-only documents,
  each with a branch that has one empty outcome slot; appended to
  `Charts.fixtures/0`, and the tests that pin the fixture list extended.
- `StatifierExamplesWeb.PlanMap`: the graph builder.
- `assets/vendor/elk.bundled.js` (elkjs 0.9.3, byte-identical to the npm
  tarball) and `assets/vendor/elkjs-LICENSE.md`.
- `assets/js/plan_map.mjs`: `layout`, `renderSvg`, `renderError`,
  `drawMap` and the `PlanMap` hook; registered in `assets/js/app.js`.
- Tests: `PlanMapTest` (graph = outline, empty markers, the options) and
  `PlanMapLayoutTest` through `test/support/js/plan_map_layout.mjs` (the
  order test, the error-pane test, escaping).

### Acceptance items met

The order test; the error-pane test; both fixtures laid out with every
branch visible and the empty slots marked (at the graph and layout level).

### Success Criteria

#### Automated Verification:
- [x] `mix quality` green.
- [x] `mix assets.bundle` builds the bundle with the hook in it.

#### Manual Verification:
- None: nothing on a page mounts the hook yet.

## PR 2: View

### Changes

- `PlanLive`: the map as the default reading - a region holding the hook,
  `data-graph` from `PlanMap.graph/1` over the view model the page already
  builds, a `data-map-canvas` child under `phx-update="ignore"`; the list
  stays in the page after it, complete and in the tab order; the map region
  `aria-hidden="true"`.
- Click-through: a box pushes `select-row` with its block id (the list's own
  event); the selected block's `ConfigForm` opens on its row in the list, and
  a panel beside the map names the block. (Amended 2026-09-26 while
  building: a second, read-only copy of the form in the panel put every
  field on the page twice, which the page's field-surface tests refuse. The
  form moves into the panel, as the one form surface, in PR 3, with the
  editing controls.)
- From the PR 1 review: leaves and containers sized from their widest line,
  title included (containers through a minimum size elkjs 0.9.3 reads
  transposed under `DOWN`); rail and tray blocks not joined by edges; a
  sentence that repeats its title not drawn twice; the layout driver reads
  the layout `drawMap` drew; an edge-offset check in the layout tests.
- Theme tokens for the map in `assets/css/app.css` for the three themes.
- LiveView tests: both library fixtures render the map region with a graph
  holding every block; the list is present and complete; selecting from the
  map selects the same row.

### Acceptance items met

The Map renders both fixtures (live page); the list remains reachable and
complete; a11y (the map aria-hidden from the list's path).

### Manual Verification:
- Captures of both library fixtures in the light and dark themes.

## PR 3: Editing

### Changes

- The four commands from the map, through the page's existing handlers:
  a "+" at each gap and on each empty marker arms `insert-open` with the
  same gap target the list computes; the panel carries move up, move down
  and remove for the selected block (`move`, `remove`); the panel's form is
  `ConfigForm` posting `config-change` (`update_config`).
- The one form surface: the selected block's `ConfigForm` moves from its
  row into the panel, which then leaves the map's `aria-hidden` region
  and is reached from the row by keyboard.
- Tests: each command performed from the map and from the list on copies of
  the same document ends at the same document.
- As built (2026-09-26): an empty marker arms `insert-open` with the slot
  named (`{:slot, block, slot}` in the page), the head of that slot - a gap
  the list has no row for, held to the package's own insert at that
  position rather than to a list gesture. The picker for the gap after a
  block opens under that block's row whichever view armed it; the empty-slot
  picker opens in the panel. The panel sits between the map and the list,
  and the selected row's "Its fields" link moves focus into it. What the
  map sends is read off the hook's own `mapGesture` through Node, and the
  LiveView tests send exactly that.

### Acceptance items met

The four Edit commands work from the Map with the same results as from the
list.

## PR 4: Tests and docs

### Changes

- README section: what the map is, that it stores nothing, elkjs's version,
  licence and size, and that the layout tests need Node.
- An acceptance sweep test over both library fixtures that walks every
  criterion the earlier PRs pinned piecemeal, and a firewall-style check
  that no product name appears in the map's strings.

### Acceptance items met

README section; no product name; the whole acceptance list re-read against
the live page.

## Testing Strategy

The layout runs in the browser, so the order and error-pane tests run the
same `plan_map.mjs` through Node with the real elkjs and read the boxes it
placed. Everything decided on the server is tested in Elixir without a
layout. Every new test carries a sabotage note.

## References

- `lib/statifier_examples_web/live/plan_live.ex` (the list view)
- `deps/statifier_blocks/lib/statifier_blocks/view_model.ex`, `outline/1`
- elkjs 0.9.3 on npm (EPL-2.0)
