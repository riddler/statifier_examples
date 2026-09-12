# SF040 - the signup walking skeleton

A spike, in four beads. A Path is a `statifier_blocks` document plus one
element document per screen (Riddler R10a); this app is where that claim gets
built small enough to argue with.

| Bead | What it added |
|---|---|
| `se-e68` (k1) | the element document, four element types, and the renderer |
| `se-19h` (k2) | the screen Composite and a three-screen Path |
| `se-7wt` (k3) | a durable run of that Path, and the page that drives it |
| `k4` | the findings this document collects |

This file is created by k1 and completed by k4. Each bead appends its own
section; nothing rewrites an earlier one.

## Vocabulary

Written into this file by k4, after the skeleton was built. The operator's
R10d amendment of 2026-09-12 (carried into campaign SF040 as consent
amendment A2) settles the words this spike was groping for:

- a **question** owns its `answer_options` - the things a select or a
  checkbox group chooses among;
- a visitor's **Journey** owns `responses`, and the datamodel root a screen
  writes is `responses.<element_key>`, not `answers.<element_key>`;
- the **host-supplied** root is `context`, not `request`, so a `responses`
  root never reads as the reply half of a request/response pair.

The k4 section at the foot of this file is written in that vocabulary. The
k1, k2 and k3 sections above it, and all of the code and fixtures the
skeleton shipped, still say `answers`: they were written before the ruling
and this file's rule is that nothing rewrites an earlier section. The rename
in this app is `se-ah4`, scheduled after the k1..k3 stack lands. Until it
does, read `answers.<element_key>` in the sections above, in
`priv/fixtures/signup_path.json`'s datamodel envelope, and in every module
under `lib/statifier_examples/signup/` as the thing now called
`responses.<element_key>`. Where k4 quotes code, a fixture or a test
verbatim, it is quoted as it stands.

## k1 findings - what the four types needed that a JSON document did not say

`priv/fixtures/signup_screens.json` holds three screens built from four
element types - `heading`, `text`, `text_question`, `button`. Writing the
resolver (`StatifierExamples.Signup.Screens`) and the renderer
(`StatifierExamplesWeb.SignupElements`) against it turned up eight questions
the document does not answer. They are written down rather than fixed,
because seven of the eight are the element document format's to answer and
this app only gets to discover them.

1. **A condition has three outcomes, not two.** A node carries `condition` as
   predicator source. Against this app's datamodel the same expression
   answers three different ways: `{:ok, true}`, `{:ok, false}`, and - for a
   path the datamodel does not hold - `{:ok, :undefined}` when the root is
   present but the leaf is not, or `{:error, %UndefinedVariableError{}}` when
   the root itself is absent. `Screens.shown?/2` hides on all three, so only
   `{:ok, true}` puts a node on a screen and an unanswered question hides
   what depends on it. Which shape a caller actually meets is the caller's
   choice, not the document's: `StatifierExamplesWeb.SignupScreensLive`
   always hands over an `answers` root, so every screen it draws - the first
   one included - sees `:undefined` and never the error; a caller passing a
   bare `%{}` gets the error instead. Nothing in the element document says
   either that the two shapes mean the same thing or that a renderer owes
   the resolver a root, and the opposite rule - unknown means show - is just
   as defensible for a screen that explains itself before it is filled in.

2. **Hiding a node says nothing about its answer.** A `text_question` whose
   condition stops holding disappears from the screen. Whether the answer it
   already wrote stays in `answers` is a question about the datamodel, not
   about the screen, and the element document has no vocabulary for it. The
   skeleton leaves the answer in place, which means a reader can be routed by
   a value no longer visible on any screen.

3. **A text slot that resolves to nothing has no declared spelling.** The
   document writes `{{ answers.first_name }}`. The subset is Riddler R9's to
   define and **no Liquid library is added here** - `Screens.fill_slots/2` is
   one regex and one lookup, deliberately too small to be mistaken for an
   implementation. What that stand-in had to invent is the missing case: an
   unresolved path renders as the empty string, so a half-written sentence is
   what a reader sees. An error, a literal passthrough, and a default written
   beside the slot are all reasonable and all unspecified. So is a path that
   resolves to a map or a list - `{{ answers }}` names something real and
   has no sensible string - which the stand-in renders as the empty string
   for the same reason, rather than raising inside a template.

4. **One `key` field carries two meanings.** Answers are keyed by element key
   (Riddler R10d), so a `text_question`'s key is also its datamodel path. For
   `heading`, `text` and `button` the key identifies the node and addresses
   nothing. A document cannot currently say "this question writes somewhere
   other than its own key", and a renaming - which for a heading is cosmetic
   - silently moves a question's answer.

5. **Outcome names have no declared vocabulary.** A button declares
   `outcome`, and the screen Composite (k2) turns those into outcome slots.
   Nothing in the element document constrains the set, and nothing in the
   block document declares which outcomes it expects, so the two halves of a
   Path agree by convention. `Screens.outcomes/1` exists so k2 can at least
   read the list off the screen rather than restate it.

6. **`required` is a label, not a rule.** The renderer marks a required
   question and sets the HTML attribute; nothing evaluates it. Whether a
   required question blocks the button that ends the screen is a Path
   question the element document raises and does not answer.

7. **Answers arrive as strings and conditions compare typed values.** This is
   the app's problem rather than the format's, but it bit immediately:
   `answers.seats > 1` is false for the string `"5"`, so
   `StatifierExamplesWeb.SignupScreensLive` coerces digits to integers at the
   form edge. A chart-backed Path (k2) hands typed values over and will not
   need it - which is worth saying out loud, because a datamodel whose types
   depend on which page wrote it is a bug waiting for k3.

8. **A condition that does not parse is a broken document, and the
   skeleton hides it anyway.** `Screens.shown?/2` keeps a node only on
   `{:ok, true}`, which folds a `%Predicator.Errors.ParseError{}` - source
   the author mistyped - in with the ordinary "not yet" cases. That is not
   the rule the renderer beside it uses: `SignupElements.element/1` raises on
   an element type it does not know, because a silently dropped element is a
   screen that lies about the document. The two are inconsistent on purpose
   only in the sense that nothing said which was right. A condition that does
   not parse is closer to the unknown type than to the unanswered question,
   and a later bead that makes it raise would be tightening this rather than
   changing its mind. Recorded here because the element document format, not
   this app, should say whether a malformed condition hides a node or breaks
   the screen.

### Asks this k1 does not act on

No ADR is amended in SF040 (consent clause 9), so these are recorded here:

- **An element document format needs a written rule for an undecidable
  condition.** Finding 1 is a fork the skeleton took by itself, and two
  screens taking it differently is a Path that behaves differently depending
  on which renderer drew it. Owner: the element document format, wherever it
  comes to rest.
- **`statifier_examples` should declare `predicator` directly when this
  leaves spike status.** `Screens.shown?/2` calls `Predicator.evaluate/2`,
  and before this bead there was no `Predicator` call under `lib/` and no
  `{:predicator, ...}` line in `mix.exs`: 9.4.0 is present only because
  `statifier` depends on it (`mix.lock`). The bead's hard line is that the
  skeleton adds no dependency, so the call stays transitive here and the
  app's requirement is implicit in the engine's. That is a spike's licence,
  not a shape to keep: an app calling a module it does not require is one
  upstream requirement change away from a compile error it did not ask for.
  Owner: this repo, on the bead that promotes the skeleton.

### What k1 shipped

| File | What it is |
|---|---|
| `priv/fixtures/signup_screens.json` | three screens, four element types, conditions and one text slot |
| `lib/statifier_examples/signup/screens.ex` | the loader and the resolver - conditions and slots |
| `lib/statifier_examples_web/components/signup_elements.ex` | one function component per type, plus `screen/1` |
| `lib/statifier_examples_web/live/signup_screens_live.ex` | `/signup-screens`, so the components are rendered by something |

The resolver holds no markup and the renderer holds no datamodel, which is
the split worth keeping: the renderer takes nodes that are already resolved
and so cannot disagree with the resolver about whether a node is on the
screen.

### What the capture shows

`se-e68-screen.png` (the campaign's pending captures) is `/signup-screens?screen=plan`
with `5` typed into the seat count. Two of the findings above are visible in
one frame rather than argued for:

- The business hint reads **"More than one seat puts you on the business
  plan, ."** - the sentence ends in a comma and a full stop because
  `{{ answers.first_name }}` is unresolved on a screen that never asked for a
  name. That is finding 3's empty-string rule, and it looks exactly as bad as
  it should.
- Before the seat count is typed, the plan screen shows **only** the Back
  button: `plan_personal` guards on `answers.seats <= 1`, which is
  `:undefined` rather than true while the question is unanswered, so the
  screen's default choice is missing until the reader answers something. That
  is finding 1 with a face on it - a document author would have written
  `<= 1` meaning "the default", and the skeleton's rule reads it as "not
  yet".

## k2 findings - what the screen Composite could not be asked to do

`se-19h` turned the element document into a chart. `myapp.screen`
(`StatifierExamples.Signup.Screen`) is a composite standing for one screen,
`priv/fixtures/signup_path.json` is three of them with a branch and a timer,
and `StatifierExamples.Signup.Path` is the check the two halves agree.

The bead asked for a specific shape - one outcome slot per declared button,
plus `timed_out` - and the interesting result is that the package cannot
express it. Everything below was measured against `statifier_blocks` 0.27.0,
the version this app pins, and each claim has a test that goes red if it
stops being true.

1. **A composite's outcomes are its expansion root's, and nothing deeper.**
   `StatifierBlocks.Composite.derived_outcomes/2` expands the subtree and
   asks the **head member** for its outcomes (`composite.ex:680-683` calling
   `outcomes_over/3` at `:729-733`, which binds `[root | _rest]` and reads
   that one). The arrangement a screen needs is a `core.group` - a `body`
   that presents and parks, `interrupts` holding one handler per button - and
   `core.group` declares no `outcomes/1`, so it takes the default single
   `done`. The plan screen has three buttons; none of them reaches the
   composite's outcome list. `StatifierExamples.Signup.ScreenTest` asserts
   `[{"done", "Done"}]` against `Screens.outcomes/1`'s three, so the two
   numbers sit beside each other in one case.

2. **`StatifierBlocks.Composite.Data` is not a way around it.** The bead
   asked for this to be tried rather than assumed. It was, and it is not:
   `Data.outcomes/2` delegates to the same `Composite.derived_outcomes/2`
   (`composite/data.ex:572`), so a declaration held as data answers the root's
   outcomes exactly as the `use` form does. A data declaration can change
   *what the root is*, and nothing else about this.

3. **`timed_out` is reachable, but only by giving up the arrangement.**
   `core.await` is the one core type that declares the name D13 wants
   (`core/await.ex:123`, `[{"received", ...}, {"timed_out", ...}]`, and the
   list does not follow `timeout` - an await with no deadline still declares
   both). So a composite **rooted** at `core.await` surfaces `timed_out`
   properly, which the test asserts against a data twin. What it cannot then
   have is a group, and without one there is nowhere to hang a button
   handler: `core.on_event` is `kinds: [:interrupt_handler]`
   (`core/on_event.ex:574`), and the only slots that admit that kind are the
   `interrupts` of `core.group` (`core/group.ex:59`) and of
   `core.resumable_group` (`core/resumable_group.ex:74`) - which declare the
   identical `slot_accepts`. Either can root the composite and both answer
   `done`, so the choice between them does not affect finding 1; what it
   does affect is finding 4, and `core.resumable_group` is the better root
   there. Its whole stated purpose is re-entering a group after an interrupt
   and returning to where it left off, which is exactly the re-present the
   park was invented for. This skeleton did not use it - `core.group` was
   reached for first and the difference only became visible once the park
   was written - and trying the resumable root is work for k3 rather than a
   defect here. The two halves of the bead's request are individually
   expressible and jointly are not.

4. **The await has to name an event it will never receive.** There is no
   "wait here until something interrupts you, with a deadline" in the `core.*`
   vocabulary. `core.await` is the only block that carries a `timeout`, and
   it requires an `event` (`config_schema/1` marks it `required?: true`). So
   the screen's body parks on `signup.screen.<key>.resumed`, an event the
   host sends only to re-present a screen it already showed, and the park's
   real job is to be somewhere a run can *sit* with a deadline on it. Every
   ordinary exit from a screen is a button, and a button is an interrupt. The
   arrangement works and reads slightly dishonestly, which is worth one line
   in a spike rather than a workaround.

5. **The environment walk sees `answers.*`, and types every one of them
   `:unknown`.** This is the question the bead left open, and it has a
   definite answer in both directions. The paths **are** there - all four,
   and only after the screens that write them; `Environment.at/3` at the
   confirm screen's position answers `answers.email`, `answers.first_name`,
   `answers.plan`, `answers.seats`, and at the first position answers `%{}`.
   Every value is `:unknown`. That is not an accident of this document:
   `StatifierBlocks.Environment`'s moduledoc says a `capture` map "writes
   `:unknown` at each of its keys, one per pair" (`environment.ex:78`) and
   `capture_writes/1` (`:1250-1255`) builds that `:unknown` unconditionally.
   Nothing declarable on this side improves it - in particular the handler's
   optional `payload` does not, because what `payload` buys is
   `payload_capture_findings/2`, a refusal on a capture **source** that reads
   a member the payload does not carry. The source is checked; the
   destination stays untyped.

6. **A `capture` map cannot express a constant, so nothing lets a button
   record its own identity.** This is the finding the skeleton went looking
   for a field to solve and found it could not. The Path branches on
   `answers.plan`, and no question asks for a plan - the choice *is* which
   button was pressed. The obvious move is to let a button say what its
   press records, so a button may now declare `writes`, a `capture` map of
   its own, and both plan buttons declare `{"answers.plan": "plan"}`.

   **That does not do what it looks like it does.** A `capture` value is a
   path inside `_event.data`, never a literal: `core/on_event.ex:806-820`
   builds each pair as `{"expr", "_event.data." <> source}`. Both plan
   buttons therefore compile to the byte-identical
   `<assign location="answers.plan" expr="_event.data.plan"/>`, and what
   reaches `answers.plan` is entirely whatever the **host** put in the
   payload. The press contributes nothing.

   Two things follow, and both are the point. First, the field still earns
   its place, for a smaller reason than the one it was added for: it decides
   which buttons write the path **at all**, and `Back` declaring no `writes`
   is why pressing it leaves `answers.plan` alone instead of overwriting it.
   Second, the Path's branch rests on a **host contract that neither
   document states** - an event raised for a button that declares `writes`
   must carry those source fields in its payload - and there is nowhere in
   either document to write that contract down. That is the gap, rather than
   the missing field.

   It is also k1's finding 4 one turn further along: `key` already carried
   two meanings, and `outcome` now carries a third thing that is neither. A
   format that let a node say "pressing me records **this literal**" once
   would collapse all three and remove the unstated contract with them.

7. **A composite that reads a second document widens what "pure" means.**
   `subtree/1` is required to be pure, and this one is - the same params
   answer the same blocks - but it reaches `Screens.screen/1` to get there,
   so it is a pure function of the params *and a file*. That is the right
   trade for a Path (the buttons are declared once, in the element document,
   and a composite that made an author restate them here would be a second
   place for them to drift), and it is a wider notion of purity than
   `StatifierExamples.Signup.GuardedStep`'s. The cost shows up as
   totality: a `screen` param naming nothing expands to the group and the
   park with no handlers rather than raising, because `subtree/1` runs behind
   `outcomes/1` and `io/1`, which the editor calls against config that is
   still being typed.

8. **Answer-key uniqueness is a Path-wide property no compiler can check.**
   R10d keys answers by element key, so the key is not a per-screen
   identifier. The check shipped here is deliberately narrower than R10d's
   whole surface: `Screens.answer_keys/1` reads `text_question` nodes only,
   so what `validate/1` holds unique is the keys that actually **carry an
   answer**, and the finding is tagged `:duplicate_answer_key` to say so.
   Two screens sharing a `heading` or `button` key are not reported. That is
   a real remaining gap rather than a decision - a duplicated button key is
   as much a collision as a duplicated question key, it just collides in a
   namespace nothing reads yet - and widening the read is the obvious next
   move. It is left narrow here so the tag does not promise more than the
   code does. The element document is not a block document and the compiler
   never reads it, so nothing upstream can see two screens claiming one key.
   `StatifierExamples.Signup.Path.validate/1` is that check, on the host side,
   which is the class `statifier_blocks`' own `docs/host-validators.md`
   describes. Building it turned up that the commonest instance is not two
   screens sharing a key but **one screen shown twice** - a Path that revisits
   a screen reaches its keys twice, and the second visit overwrites what the
   first collected. So the finding names the *blocks* that reach a repeated
   name rather than the screens, which is the only way the two cases report
   the same. The same check covers outcome names, because
   `Screen.outcome_event/1` deliberately leaves the screen out of an event
   name and distinctness is what makes that safe.

9. **Registering one document moved five pinned enumerations.** Adding
   `signup_path` to `Signup.@documents` and `myapp.screen` to
   `block_types/0` turned seven cases red across `ChartsTest`, `SignupTest`,
   `StepLabelTest` and `ViewModelPinTest` - the palette list, the fixture
   list, the label counts, the outline row counts and the fixture-list pin.
   Every one of them is a deliberate "tell me when this changes" pin and
   every one was updated rather than relaxed. Recorded because it is the
   honest cost of this app's pinning convention and a later bead adding a
   document should budget for it.

### A sentence of k1's that k2 falsified

This file's rule is that each bead appends its own section and nothing
rewrites an earlier one, so k1's finding 5 is left as written - but it is
wrong now and a reader meets both statements. It says a button declares
`outcome` "and the screen Composite (k2) turns those into outcome slots".
k2 could not: finding 1 above is that a composite's outcomes are its
expansion root's, so the buttons reach no outcome slot at all. Everything
else in k1's finding 5 stands, including the reason `Screens.outcomes/1`
exists - k2 does read the list off the screen rather than restate it, and
uses it to derive one handler and one event name per button instead.

### Asks this k2 does not act on

No ADR is amended in SF040 (consent clause 9), so these are recorded here:

- **A composite should be able to declare its outcomes.** Findings 1-3
  together: the root-only rule means the outcome surface of a composite is
  whatever its head member happens to declare, which for every structural
  root (`core.group`, `core.sequence`, `core.branch`) is the default `done`.
  A composite is the unit a host puts in front of an author, and it is
  currently the one block type that cannot say how it finished. A declared
  `outcomes` key on the composite declaration - checked against what the
  subtree can actually raise - would be the shape. Owner: `statifier_blocks`.
- **A `capture` destination could be typed where the handler declares a
  `payload`.** Finding 5. The payload declaration already carries the member
  types the capture sources are checked against, so the type of each
  destination is in hand at exactly the moment `capture_writes/1` discards
  it. Typing them would make a Path's `answers.*` readable by the environment
  walk, which is what a downstream branch guard wants. Owner:
  `statifier_blocks`.
- **A "park until interrupted, with a deadline" primitive.** Finding 4.
  Today the shape is `core.await` on an event nobody sends. Owner:
  `statifier_blocks`.
- **A node needs a way to declare what pressing it records, as a literal.**
  Finding 6, and k1's finding 4 under it. `capture` is path-to-path by
  construction (`core/on_event.ex:806-820`), so a constant is not expressible
  in it and a button cannot record its own identity - the one thing a
  multi-button screen most obviously needs. Either the element document
  format grows the notion, or `capture` grows a literal arm; the two owners
  should agree which. **Until then a Path carries an unstated host
  contract**: an event raised for a button declaring `writes` must carry
  those source fields in its payload, and nothing in either document says
  so or can check it. Owner: the element document format, with
  `statifier_blocks` on the `capture` half.

### What k2 shipped

| File | What it is |
|---|---|
| `lib/statifier_examples/signup/screen.ex` | `myapp.screen`: the composite, its params and its subtree |
| `lib/statifier_examples/signup/path.ex` | the Path, and `validate/1` - the R10d uniqueness check |
| `priv/fixtures/signup_path.json` | three screens, a branch on `answers.plan`, a reminder timer |
| `test/statifier_examples/signup/screen_test.exs` | the expansion, and the two limits above asserted as facts |
| `test/statifier_examples/signup/path_test.exs` | the compile, the distinct events, the environment walk, the validator |

`priv/fixtures/signup_screens.json` gained two lines - the `writes` map on
each plan button (finding 6). Nothing else of k1's was rewritten.

## k3 findings - what a Path costs to actually run

k2 built the Path and compiled it. k3 ran one: `StatifierExamples.Signup.Journey`
over `StatifierExamples.Charts.Durable`, with
`StatifierExamplesWeb.SignupJourneyLive` at `/signup-journey` drawing whatever
screen the run is parked on. Three submits take a run from the first screen to
a created account; a screen nobody answers times out and the Path goes on
without it. What follows is what that turned up.

### The presentation contract, as it came out (Riddler R10e)

The brief asked for the resolve/submit function pair recorded. It is two
functions and a third that a linear-Path assumption would have missed:

| Function | Takes | Answers |
|---|---|---|
| `Journey.current/1` | a run id | the screen the run is parked on, its resolved nodes, the answers so far, the status |
| `Journey.submit/3` | a run id, the outcome a button named, the form's answers | `{:ok, next view}`, `{:invalid, same view with findings}`, or `{:error, reason}` |
| `Journey.resolve/2` | a view and a **draft** | the same view re-resolved over answers the reader has typed and not sent |

Two properties are worth naming as part of the contract rather than as
implementation. **Neither of the first two takes a run** - both take an id and
load from storage, so there is no process, no session and nothing in a socket
that the next press depends on. And **neither returns a chart**: a page built
on this pair cannot reach into the run, so it cannot start depending on the
chart's shape.

`resolve/2` is the one a first draft leaves out. An element's condition may
read an answer given on the screen it is on - the plan screen's two plan
buttons are conditional on the seat count typed two lines above them - so a
page that resolved only against what the chart has stored would draw a screen
with no way off it. The draft is never persisted and never sent.

1. **The host contract k2 predicted is real, and this page is the host.**
   k2's finding 6 says a `capture` value is a path inside `_event.data` and
   never a literal, so what lands at `answers.plan` is whatever the host put
   in the payload. Running it makes that concrete: the payload
   `Journey.submit/3` sends is *the form's answers, keyed by element key,
   merged with the firing button's own `payload` map*, and the two plan
   buttons carry `"payload": {"plan": "business"}` and `{"plan": "personal"}`
   for the branch to read. `Journey.payload/2` is public for that reason - a
   contract nothing can read is a contract nobody can check. Without the
   button half, `answers.plan` is `:undefined`, the branch takes neither arm
   and the run reaches the confirm screen having chosen nothing. That is
   asserted, both ways, in `JourneyTest`.

2. **A capture writes its destination whether or not the payload carries the
   source.** Press Back on the plan screen without typing a seat count and
   `answers.seats` is written as `:undefined` rather than left absent. Every
   question on a screen is in every button's capture map, so a screen's
   answers are written by whichever button ends it, in full, with the
   unanswered ones filled in as `:undefined`. Nothing downstream can tell
   "not answered" from "answered with nothing", and a guard reading such a
   path gets a value rather than a missing one.

3. **`timed_out` is unreachable from the Path, exactly as k2 said.** The
   deadline works: each screen's `core.await` arms a stored Oban job through
   `StatifierExamples.Charts.Timers`, draining the queue fires it, and the
   feed shows `timed_out on blk_sp_account_park`. What the *Path* sees is
   nothing at all - the group completes and the next block runs, the same as
   for any button - because the composite's only outcome is `done`
   (k2's finding 1). So a timed-out screen and an answered one are
   distinguishable only by what was captured, which is finding 2's problem
   with the word "only" removed: a timeout captures nothing, and an
   unanswered submit captures `:undefined`, and those are two different
   things that look the same one level up.

4. **A parked run has no way to say which screen it is on except a block
   id.** `Journey` finds the current screen by looking for
   `Screen.park_block_id/1` - the composite block's id with `_park` appended
   - among the reading's active blocks. That works because
   `StatifierBlocks.Composite.expand/2` mints member ids from the composite's
   own, but it is a host reading a package's id-minting rule, and it is the
   single thing the whole loop rests on: breaking it reddened eighteen cases.
   A composite that could answer "what is this position waiting for" would
   put the knowledge where it belongs.

5. **A durable run has a third resting state, and a presentation contract has
   to admit it.** The Path's business arm is `myapp:signup` on the
   `company_details` step, which this app runs as an Oban job
   (`StatifierExamples.Charts.AsyncCalls`), so between the plan screen and
   the confirm screen the run rests with **no screen at all**: a live
   invocation, a persisted position, and nothing holding it. `current/1`
   answers `screen: nil` and the page says so. A contract with only "here is
   a screen" and "the journey is over" has nowhere to put that, and it is not
   an exotic case - any step a host runs asynchronously produces it.

6. **The element document needs a validation vocabulary, and had one field's
   worth of it invented here.** `required` is the document's; `format` is not.
   `StatifierExamples.Signup.Validation` stands in for Riddler R10c's
   elements package, and to have anything to check it added
   `"format": "email"` to the account screen's address question. The rule it
   implements is one regex, not RFC 5322, and a format name it does not
   implement raises rather than passing - a document asking for a check
   nobody runs is a document that silently accepts anything.

7. **Validation is over *resolved* nodes, and that is not a detail.** The
   confirm screen's referral question only appears for a business plan. A
   check over the raw document would refuse a personal signup for not
   answering a question it never saw, so the check has to run over what
   `Screens.resolve/2` left on the screen. Whichever package owns the rules
   owns that too: they are rules about a screen as drawn, not about a screen
   as written.

8. **Every button validates, and one of them should not.** A Back button must
   not refuse to leave a screen because the screen is incomplete. This app
   shipped a `"validate": false` field for it, then removed it: the plan
   screen - the one screen with a second button - asks for nothing required,
   so no press of Back can be refused, and the field could not be sabotaged
   into failing any test. A field no shipped screen can exercise is a field
   no test can defend. It is recorded as an ask instead.

9. **A hidden button is not a button anyone pressed.** `submit/3` looks for
   the outcome among the *resolved* nodes, so pressing the business plan
   without a seat count is `{:unknown_outcome, _}` rather than a press. That
   is a host's call today; nothing in either document says whether a
   condition on a button hides it from the reader alone or from the chart as
   well.

10. **No shipped screen can demonstrate an input drawn over a stored answer.**
    The renderer takes an `answers` map for exactly that, and on this Path it
    is unobservable: a linear Path never returns to a screen, so no input is
    ever redrawn over an answer the chart holds. Deleting the attribute's
    value reddened nothing in either suite. It stays correct because the next
    Path will not be linear; it is recorded because a spike that only reports
    what it proved is more useful than one that implies it proved everything.

11. **A chart with captures cannot be driven by an event with no payload.**
    `Charts.Durable.send_event/3` had no way to carry one - nothing in this
    app had needed `_event.data` before - so k3 widened it to `/4`. Worth
    saying only because it is the seam a host meets first and it was missing:
    every door into a run (`send_event`, `deliver/2`,
    `complete_invocation/3`) is about *which* event, and a screen's answers
    ride on the one thing none of them took.

### The acceptance line k3 could not meet literally

`se-7wt` asks for "an end-to-end test [that] drives three submits and one
timeout through the durable run". Three submits and one timeout cannot share a
run on this Path: it has three screens, a timed-out screen is by definition
one that was **not** submitted, and a run that took all three buttons has
finished before any deadline can elapse. The obligation is met by two runs in
`StatifierExamples.Signup.JourneyTest` - "three submits drive the run from the
first screen to the created account", and "a screen nobody answers times out,
takes the timed_out slot, and the Path goes on" - and the divergence is
recorded here rather than papered over by a test that drives both in one
function and calls itself one run.

### Asks this k3 does not act on

No ADR is amended in SF040 (consent clause 9), so these are recorded here.
They are additional to k2's four, which all stand.

- **A capture should be able to leave a destination alone when the payload
  does not carry its source.** Finding 2. Writing `:undefined` makes "not
  answered" indistinguishable from "answered with nothing" at every path a
  screen touches, and it is the capture map that decides, not the host.
  Owner: `statifier_blocks`.
- **A composite should be able to answer what a position inside it is waiting
  for.** Finding 4. A host presenting a screen has to know which screen, and
  the only handle today is the composite's own id-minting rule read from
  outside. Owner: `statifier_blocks`.
- **The element document format needs a validation vocabulary.** Findings 6,
  7 and 8: a named `format` check per question, the rule that checks run over
  resolved nodes rather than declared ones, and a way for a button to say it
  does not validate. Owner: the element document format (Riddler R10c).
- **A presentation contract needs a third answer.** Finding 5: "no screen,
  the run is working" is a state any asynchronous step produces, and a
  contract with only a screen and an ending has nowhere to put it. Owner:
  Riddler R10e.

### Residue in this app, for the campaign to file

- `Charts.Durable.resume/1` loads a run's position and discards the
  `Statifier.MachineState` it built, so `Journey.current/1` walks storage
  twice per view - once through `resume/1` for the reading and once through
  `machine_state/1` for the datamodel. Answering both from one load is a
  small change to this app's own module and it is not k3's to make.

### What k3 shipped

| File | What it is |
|---|---|
| `lib/statifier_examples/signup/journey.ex` | the loop: `start`, `current`, `resolve`, `submit`, `payload` |
| `lib/statifier_examples/signup/validation.ex` | the pure check standing in for R10c's elements package |
| `lib/statifier_examples_web/live/signup_journey_live.ex` | `/signup-journey`: the page, holding only the draft |
| `test/statifier_examples/signup/journey_test.exs` | three submits, the timeout, the park, the refusals |
| `test/statifier_examples/signup/validation_test.exs` | the two rules, and what a third would cost |
| `test/statifier_examples_web/live/signup_journey_live_test.exs` | drawn, pressed, and reloaded into a second process |

Five files of k1's and k2's moved, each forced by the bead:
`priv/fixtures/signup_path.json` gained the `core.invoke` the finished Path
ends on (`myapp:signup` with `params: "answers=answers"`, writing to a
`created` root it also declares); `priv/fixtures/signup_screens.json` gained
the `format` on the address question and the `payload` map on each plan
button; `lib/statifier_examples/signup/screen.ex` gained
`park_block_id/1`; `lib/statifier_examples/charts/durable.ex` gained the
payload argument on `send_event`; `lib/statifier_examples/signup/handlers.ex`
gained the `myapp:signup` clause that answers a create-account receipt for
the answers it is handed. `test/statifier_examples/view_model_pin_test.exs`
moved to the measured value, 9 rows for `signup_path` rather than 8, because
the Path gained a block.

### What the k3 captures show

Four, in `.claude/fleet/pending/SF040-spikes/`, taken against the dev server
on 8645 driving one real durable run end to end. The bead's acceptance line
is "the page works in `mix phx.server`"; these are that, and each one is
also the only evidence for something a test asserts differently.

| Capture | What it is evidence of |
|---|---|
| `se-7wt-validation-findings.png` | Continue pressed with a blank name and `ada-at-example` in the address: both findings drawn, the screen still the account screen, the run not moved. Finding 6's two rules, as a reader meets them. |
| `se-7wt-plan-screen-draft.png` | `5` typed into the seat count and nothing submitted: the business button has appeared, the personal one has not, and the hint reads "More than one seat puts you on the business plan, Ada." - a condition on a **draft** answer and a text slot filled from an answer the **chart** holds, on one screen. That is `resolve/2` and the k1 renderer doing two different jobs at once. |
| `se-7wt-confirm-screen.png` | After pressing the business plan. The page was showing the between-screens state while the company-details job ran, and redrew **on its own** when the job answered - nothing was clicked between the two. The referral question is on the screen because the seat count is five. |
| `se-7wt-run-finished.png` | Finish pressed: the run is `done` and the collected block holds all five answers the chart gathered. The server log for the same run carries `myapp:signup created the account for "ada@example.com"` - the create-account call, handed the answers. |

## k4 - what the skeleton settled, and what it only found out it did not know

k1, k2 and k3 each recorded what their own bead met. This section is the
whole of it read back against the rulings the spike was built to test, plus
the asks, each with the bead that now carries it. Nothing above is rewritten;
where k4 disagrees with an earlier section it says so here.

Every cite below was read on branch `se-ocz-signup-findings` at `f81e92a`,
the head of the k1 -> k2 -> k3 stack, and the file paths are as of that
commit.

### R10a, the nouns, as built

R10a says a Path is a `statifier_blocks` document plus the element documents
its screens reference; a Journey is a durable run plus its datamodel; a Guide
is the durable stepper composed with an element resolver and an answer
validator **as effect executors**. Two of the three came out as ruled. The
third did not, and the reason is the most useful thing this spike has to say
about the mapping.

| Noun | Built as | Verdict |
|---|---|---|
| **Path** | `priv/fixtures/signup_path.json` (the block half) plus `priv/fixtures/signup_screens.json` (the element half), joined by each `myapp.screen` block's `screen` param | holds, unchanged |
| **Journey** | one `StatifierExamples.Charts.Durable` run over `statifier_persistence`, its datamodel read back from storage by run id | holds, unchanged |
| **Guide** | `StatifierExamples.Signup.Journey` - a plain module the page calls, which resolves and validates **before** it tells the chart anything | diverges, and has to |

**The validator cannot be an effect executor on this shape.** A failed
validation must leave the run exactly where it was: the reader sees the same
screen with findings on it, and nothing is written. An effect executor runs
inside a step the chart has *already taken*, so by the time one could refuse,
the event has been raised, the capture has fired, and the position has moved.
`Journey.submit/3` (`lib/statifier_examples/signup/journey.ex:201`) therefore
runs `Validation.validate/2` first and answers `{:invalid, view}` without
touching storage at all. The same argument applies, more weakly, to the
resolver: `Screens.resolve/2` has to run on the way *out* to a reader, which
is not a step the chart takes either.

This does not contradict R10c so much as complete it. R10c gives the chart
"capture and consequence", and capture is genuinely the chart's - the
`core.on_event` capture map is what writes a screen's responses. Consequence
is not, or not all of it: the failure consequence (re-present with findings)
happens entirely on the host side of the seam, before any event exists, and
the success consequence (raise the outcome) is the host deciding to speak.
What the chart owns is what happens *after* it is spoken to.

So the mapping worth carrying forward is: a Guide is the durable stepper plus
a **host-side** pair of pure functions that stand between a reader and the
run. That is a smaller claim than R10a's and it is the one the code can
defend.

#### The file map

| File | What it is | Bead |
|---|---|---|
| `priv/fixtures/signup_screens.json` | the element half: three screens, four element types, conditions, one text slot, per-button `payload` and `writes` | k1, +k2, +k3 |
| `priv/fixtures/signup_path.json` | the block half: three `myapp.screen` blocks, a `core.branch`, a reminder timer, a closing `core.invoke` | k2, +k3 |
| `lib/statifier_examples/signup/screens.ex` | the element resolver - conditions, text slots, the key and outcome lists | k1 |
| `lib/statifier_examples_web/components/signup_elements.ex` | one function component per element type, plus `screen/1` | k1 |
| `lib/statifier_examples/signup/screen.ex` | `myapp.screen`: the Composite, its params, its subtree, `park_block_id/1` | k2, +k3 |
| `lib/statifier_examples/signup/path.ex` | the Path, and `validate/1` - the host-side uniqueness check | k2 |
| `lib/statifier_examples/signup/validation.ex` | the pure check standing in for R10c's elements package | k3 |
| `lib/statifier_examples/signup/journey.ex` | the loop: `start`, `current`, `resolve`, `submit`, `payload` | k3 |
| `lib/statifier_examples_web/live/signup_screens_live.ex` | `/signup-screens` - the renderer with no chart behind it | k1 |
| `lib/statifier_examples_web/live/signup_journey_live.ex` | `/signup-journey` - the page over a durable run | k3 |
| `lib/statifier_examples/charts/durable.ex` | gained the payload argument on `send_event` | k3 |
| `lib/statifier_examples/signup/handlers.ex` | gained the `myapp:signup` clause that answers a create-account receipt | k3 |
| `lib/statifier_examples/signup.ex`, `lib/statifier_examples_web/router.ex` | the document registration, the block type, two routes | k1, k2 |

Six test modules and four pinned enumerations moved with them; k2's finding 9
records what the pinning convention costs a bead that adds a document.

The split worth keeping is the one k1 named and k3 did not break: the
resolver holds no markup, the renderer holds no datamodel, and `Journey`
holds no chart internals. A page cannot reach past `Journey` into the run,
which is why the presentation contract below is a contract rather than a
description.

### R10b, what the screen Composite could not be asked to do

R10b asks for a screen block whose slots are "one outcome per call to action
the document declares plus `timed_out`". The package cannot express that, and
k2 proved it three ways rather than asserting it once.

1. A composite's outcomes are its **expansion root's** and nothing deeper
   (`Composite.derived_outcomes/2` reads the head member). The arrangement a
   screen needs - a group whose body presents and parks and whose
   `interrupts` hold one handler per button - is rooted at `core.group`,
   which declares the default single `done`. Three buttons, one outcome.
2. **`StatifierBlocks.Composite.Data` is not a way around it.** The bead
   asked for this to be tried rather than assumed; it was.
   `Data.outcomes/2` delegates to the same `Composite.derived_outcomes/2`,
   so a declaration held as data answers the root's outcomes exactly as the
   `use` form does. A data declaration can change *what the root is*, and
   nothing else about this. That is the verdict, and it is a clean no.
3. `timed_out` is reachable only by giving up the arrangement: `core.await`
   declares it, so an await-rooted composite surfaces it - and then has
   nowhere to hang a button handler, because the only slots admitting an
   interrupt handler are the `interrupts` of `core.group` and
   `core.resumable_group`. The two halves of R10b's request are individually
   expressible and jointly are not.

k3 then ran it, and the runtime half is worse than the compile-time half. The
deadline works - the stored Oban job fires and the feed carries `timed_out on
blk_sp_account_park` - but what the *Path* sees is `done`, the same word a
button produces, because the composite has no other outcome to give it. A
timed-out screen and an answered one are distinguishable downstream only by
what was captured, and a timeout captures nothing while an unanswered submit
captures `:undefined`. Those are two different states that look the same one
level up.

**The Composite is still the right first shape.** Nothing here argues for
promoting `myapp.screen` to a native BlockType, which R10b reserves for "the
pilot hits something a Composite cannot express". This is that, twice over -
but both limits are in `derived_outcomes/2` and in the `core.*` vocabulary,
not in the Composite mechanism, so a native block type would inherit them
rather than fix them. The asks below are the fix.

### R10c, where validation ran and what it needed

`StatifierExamples.Signup.Validation` is a pure function
(`lib/statifier_examples/signup/validation.ex:76`), called by
`Journey.submit/3` before anything reaches the chart. It stands in for
R10c's `riddler_elements`. Three things it needed that no document said:

1. **A named format check, invented here.** `required` is the element
   document's own boolean and it was already there. `format` was not, so
   `"format": "email"` was added to the account screen's address question and
   the module implements exactly one name (`validation.ex:100`, one regex,
   not RFC 5322). A format name it does not implement **raises**
   (`:108`) rather than passing, on the rule that a document asking for a
   check nobody runs is a document that silently accepts anything. Both
   halves - the vocabulary of names, and what an unknown name does - are the
   elements package's to rule.
2. **Rules run over *resolved* nodes, not declared ones.** The confirm
   screen's referral question only exists for a business plan. A check over
   the raw document would refuse a personal signup for not answering a
   question it never saw. So `validate/2` is handed what `Screens.resolve/2`
   left on the screen, and whichever package owns the rules owns this too:
   they are rules about a screen **as drawn**.
3. **A per-button opt-out, tried and withdrawn.** A Back button must not
   refuse to leave an unfinished screen. k3 shipped a `"validate": false`
   field for it and then removed it: the one screen with a second button
   asks for nothing required, so no press of Back can be refused, and the
   field could not be sabotaged into failing any test. It is recorded as an
   ask rather than shipped, because a field no screen can exercise is a field
   no test can defend. That is the honest state - the need is real and the
   evidence for the shape is not.

One more, which is R10c's seam rather than its vocabulary: **a hidden button
is not a button anyone pressed.** `submit/3` looks for the named outcome
among the *resolved* nodes, so pressing the business plan without a seat
count is `{:unknown_outcome, _}`. Nothing in either document says whether a
condition on a button hides it from the reader alone or from the chart as
well; the skeleton chose both and nothing forced the choice.

### R10d and Q17, the responses layout used, and what Back did

**Layout: flat.** One root, `responses.<element_key>` (spelled `answers` in
the shipped bytes; see the Vocabulary note), declared once in the Path
document's datamodel envelope alongside `created`, which the closing
`core.invoke` writes its receipt to. No per-screen namespacing was tried,
because nothing in three screens needed it, and the flat form is what makes
k2's uniqueness check meaningful at all: a key is a datamodel path, so two
screens claiming one key are two screens claiming one cell.

**Uniqueness is a host check, and a narrower one than R10d's sentence.**
`Path.validate/1` (`lib/statifier_examples/signup/path.ex:102`) reads
`Screens.answer_keys/1`, which reads `text_question` nodes only, so what is
held unique is the keys that actually carry a response - hence the
`:duplicate_answer_key` tag. Two screens sharing a `heading` or `button` key
are not reported. Building it turned up that the commonest instance is not
two screens sharing a key but **one screen shown twice**, so the finding names
the blocks that reach a repeated name rather than the screens. And the check
is necessarily the host's: the element document is not a block document, the
compiler never reads it, and nothing upstream can see two screens claiming
one key.

**Back navigation was not built and cannot be built on this shape.** This is
the part of R10d the spike was meant to exercise and could not. The plan
screen declares a Back button (`priv/fixtures/signup_screens.json:102-104`,
key `plan_back`, outcome `went_back`), and because a composite answers only
`done` (R10b above), `went_back` reaches no outcome slot and the Path has no
way to tell it from `Continue`. **Pressing Back moves the Path forward.**
Two consequences follow, and both are findings about the ruling rather than
about this app:

- R10d's "back navigation and re-asks overwrite" is **untested here**. The
  skeleton has no back navigation to test it with. A linear Path never
  returns to a screen, which is also why k3's sabotage of the renderer's
  stored-response attribute reddened nothing: no input is ever redrawn over a
  response the chart holds.
- The overwrite that *does* happen is the destructive one nobody asked for.
  Every question on a screen is in every button's capture map, so whichever
  button ends the screen writes all of that screen's response paths - filling
  the unanswered ones in as `:undefined`. Press Back on the plan screen
  without typing a seat count and `responses.seats` is written `:undefined`
  rather than left absent. Nothing downstream can tell "not answered" from
  "answered with nothing", and a guard reading such a path gets a value
  instead of a missing one.

So Q17's open half - flat versus namespaced, and how back navigation and
re-asks overwrite - gets one input from this spike and it is not the one the
question expects: **before the layout question can be answered, a Path needs a
way to go backwards at all.** That is R10b's outcome limit again, met from the
other side.

`context` - A2's host-supplied root - does not exist in the skeleton. The
Path declares `answers` and `created` and nothing else; no value enters a run
from the host except through a button's event payload. A Path that needed to
read who the visitor is, or what plan the marketing page offered them, has
nowhere to put it today.

### R10e and Q13, the resolve/submit pair, and the third state

The contract, as it came out (k3's table, repeated here because it is the
deliverable R10e asked for):

| Function | Takes | Answers |
|---|---|---|
| `Journey.current/1` | a run id | the screen the run is parked on, its resolved nodes, the responses so far, the status |
| `Journey.submit/3` | a run id, the outcome a button named, the form's responses | `{:ok, next view}`, `{:invalid, same view with findings}`, or `{:error, reason}` |
| `Journey.resolve/2` | a view and a **draft** | the same view re-resolved over responses the reader has typed and not sent |

Four properties are the contract rather than the implementation:

1. **Neither of the first two takes a run.** Both take an *id* and load from
   storage (`journey.ex:156`, `:201`). No process, no session, nothing in a
   socket that the next press depends on - which is what makes a Journey
   survive a deploy and `submit/3` callable from a controller, a job or a
   test as readily as from a page.
2. **Neither returns a chart.** A screen, some nodes, the responses and a
   status. A transport built on this pair cannot reach into the run.
3. **`resolve/2` is not optional.** A first draft of any such contract leaves
   it out, and this document breaks it: the plan screen's two plan buttons are
   conditional on a seat count typed two lines above them, so a surface that
   resolved only against stored responses would draw a screen with no way off
   it. The draft is never persisted and never sent.
4. **There is a third resting state, and a two-state contract has nowhere to
   put it.** The Path's business arm runs `myapp:signup` as an Oban job, so
   between the plan screen and the confirm screen the run rests with **no
   screen at all**: a live invocation, a persisted position, nothing holding
   it. `current/1` answers `screen: nil` and the page says so. This is not
   exotic - any step a host runs asynchronously produces it - and a contract
   offering only "here is a screen" and "the journey is over" is wrong about
   every Path that calls anything.

Point 4 is also the one input this spike has for Q13's streaming half. The
page learned the job had answered because it subscribes to the run's topic
and redrew on a `:run_advanced` broadcast, with nothing clicked between the
two frames (`se-7wt-confirm-screen.png`). A transport whose only verb is a
request cannot express that frame; whether the answer is a subscription, a
poll, or a contract that simply blocks is Q13's, but the state exists whether
or not the transport admits it.

The spike has **no** input on Q13's other two halves: auth and tenant scoping
never entered the picture (see Q16 below), and field-level shape is a
GraphQL question this app never posed.

### Q16, how a Journey was keyed before an account existed

`Journey.start/0` mints the run id with `Durable.new_run_id/0` -
`16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)`
(`lib/statifier_examples/charts/durable.ex:538`) - and that id is the entire
identity. It goes in the page's URL as `?run=<id>`
(`lib/statifier_examples_web/live/signup_journey_live.ex:63`), and
`handle_params/3` loads whatever run the query string names. There is no
cookie, no signed token, no host session, and nothing in the socket the next
press depends on.

Three things that gives Q16 to work with:

- **An unguessable id is the whole of the authorization.** Anyone holding the
  id holds the Journey and can read every response in it. For a spike over
  fictional data that is fine and it is deliberate - the id is 128 bits of
  entropy, not a counter - but it is a decision, not an absence of one, and
  it is the decision Q16 has to either adopt or replace. Note what it costs
  if adopted: the id travels in a URL, so it lands in browser history, in a
  `Referer`, and in any log that records paths.
- **The handoff is not built.** The account is created by the *last* block of
  the Path (`blk_sp_create_account`, a `core.invoke` sending
  `answers=answers` and writing its receipt to `created`), after every
  response is already collected. Nothing then associates the run with the
  account it just created; `created` holds a receipt and the run holds the
  responses, and the join between them exists only in the log line the stub
  handler writes. A real Guide needs that join to be a thing a host can query
  from either end, and the skeleton has no opinion on which end owns it.
- **"What the host may read before the account exists" is, today,
  everything.** The responses are in the run's datamodel from the first
  submit, readable by run id alone through `Journey.current/1`, with no
  account, no tenant and no scope anywhere in the call. Personal data
  collected by screens is meant to live in the encrypted datamodel (statifier
  D12); this skeleton stores it plainly, because encryption was out of the
  bead's scope. That gap is worth stating loudly in a spike whose fixture
  collects a name and an email address, even though every value in it is
  fiction.

### What the authoring half (q2) adds to this

The element-editor spike (`se-aud`, notes under
`.claude/fleet/pending/SF040-spikes/se-aud-authoring-notes.md`) re-authored
k1's fixture in the blocks editor over an element palette. Its headline
matters to the asks below: the editor was not the obstacle - the per-node
authoring cost is flat - but the `element.*` vocabulary carried only 39 of
the fixture's 64 fields, with the Findings pane at 0 for every loss. What it
could not express is the same list this document keeps arriving at from the
running side: a key on a non-question node, a condition, a `writes` map, a
payload, a `format`, and a screen container. Two spikes approaching the
element document format from opposite ends found the same holes, which is
the strongest evidence either of them produced.

### Upstream asks, with the beads that carry them

These were discovered by k2, k3 and the sd spike (t1) and **filed by the
campaign conductor** under consent clause 8, unscheduled, at P4, labelled
`campaign-SF040` and `sf041-candidate`. Listed here by id so a reader of this
document can follow each one.

| Bead | Repo | Ask | From |
|---|---|---|---|
| `sb-5ee4` | `statifier_blocks` | A composite cannot declare its own outcomes: `derived_outcomes/2` reads the expansion root only | k2 findings 1-3 |
| `sb-5imu` | `statifier_blocks` | A `core.on_event` capture **destination** is always typed `:unknown`, even where the handler declares a payload that would type it | k2 finding 5 |
| `sb-m6ru` | `statifier_blocks` | A capture map cannot express a **constant**, so no event source can record its own identity | k2 finding 6 |
| `sb-oy84` | `statifier_blocks` | No park-until-interrupted-with-a-deadline primitive: `core.await` requires an event | k2 finding 4 |
| `sb-j0cz` | `statifier_blocks` | A capture pair whose source is absent from the payload should leave its destination unwritten | k3 finding 2 |
| `sb-jc3x` | `statifier_blocks` | A composite (or the ViewModel) answers which member a position is resting in, so a host need not reconstruct member ids | k3 finding 4 |
| `sb-czla` | `statifier_blocks` | A reads-before-writes check over the typed environment walk | the sd spike (t1) |

Two of those are load-bearing for this skeleton rather than nice to have.
`sb-5ee4` is why Back moves the Path forward and why `timed_out` is invisible
one level up; `sb-m6ru` is why a Path's branch rests on a host contract that
neither document states and nothing can check.

Residue in this app, filed by the conductor and open here:

| Bead | What |
|---|---|
| `se-3nf` | two sabotage notes in `screens_test.exs` overclaim their discriminating mutation (k1) |
| `se-zq7` | the coverage floor sits at 70 while the tree measures 82.2% (k1) |
| `se-kbq` | three prose stragglers after the k2 cure, one of which is this file's "What k2 shipped" row calling `validate/1` the R10d uniqueness check (k2) |
| `se-3e4` | the two capture tests assert at config level, not the compiled emission (k2) |
| `se-w4i` | `Charts.Durable.resume/1` discards the `MachineState` it built, so `current/1` walks storage twice per view (k3) |
| `se-u9a` | pass-2 residue on the Journey: a stale doc row, an unguarded `resolve/2` call, a hand-duplicated status union, two prose imprecisions (k3) |
| `se-ah4` | the rename this document's Vocabulary note describes: `answers` -> `responses`, `answer_options` on questions, `context` as the host root |

`se-kbq` is deliberately not fixed here even though its third straggler is in
this file: this section adds, it does not rewrite, and a docs-only PR that
edited a merged sibling's prose would make the two changes indistinguishable
in review.

### Riddler asks

These belong to the product's own decision record, not to any fleet tracker,
so they are written here rather than filed:

- **The element document format needs a validation vocabulary** (R10c). Three
  parts, all met above: the set of named `format` checks and what an unknown
  name does; the rule that checks run over resolved nodes rather than
  declared ones; and a way for a button to say it does not validate.
- **A node needs a way to declare what pressing it records, as a literal**
  (R10b/R10d). `capture` is path-to-path by construction, so a button cannot
  record its own identity - the one thing a multi-button screen most
  obviously needs. Either the element document format grows the notion or
  `capture` grows a literal arm (`sb-m6ru`); the two owners should agree
  which. Until then a Path carries an unstated host contract that nothing can
  check.
- **The presentation contract needs a third answer** (R10e). "No screen, the
  run is working", as above.
- **An element document format needs a written rule for an undecidable
  condition, and for a malformed one** (k1 findings 1 and 8). The skeleton
  hides a node on `false`, on `:undefined`, on an absent root **and** on a
  parse error, which folds an author's typo in with an unanswered question.
  The opposite rule - unknown means show - is just as defensible for a screen
  that explains itself before it is filled in, and a malformed condition is
  closer to an unknown element type (which raises) than to an unanswered one.
  Two screens taking this differently is a Path that behaves differently
  depending on which renderer drew it.
- **R10a's Guide clause should say host-side pure functions, not effect
  executors**, for the reason in the R10a section above. This is the only ask
  here that proposes changing a ruling's words rather than filling a gap in
  one.
- **`statifier_examples` should declare `predicator` directly** when the
  skeleton leaves spike status (k1's second ask; this repo's, on the bead that
  promotes it). The call is transitive through `statifier` today, which is a
  spike's licence and not a shape to keep.

### What this spike did not prove

A spike that only reports what it proved is more useful than one that implies
it proved everything. These are the gaps, each one a place where a later bead
should not read this document as evidence:

- **Back navigation, and therefore R10d's overwrite rule.** No Path here goes
  backwards; see the R10d section.
- **A response redrawn into an input.** The renderer takes a stored-response
  map for exactly that and it is unobservable on a linear Path - deleting the
  attribute's value reddened nothing in either suite.
- **That a capture value can never be a literal.** The claim is true and it
  is the ground under `sb-m6ru`, but the two tests pinning it assert at config
  level, so both would stay green if the package grew a literal arm. `se-3e4`
  carries the case that would close it.
- **Three submits and one timeout in one run.** They cannot share a run on
  this Path: three screens, and a timed-out screen is by definition one that
  was not submitted. Two runs assert the two halves; the divergence is k3's
  and is recorded in its own section rather than papered over.
- **Anything about encryption, auth, tenancy or scale.** None entered the
  bead. The datamodel is stored plainly and the run id is the only credential.
- **That the Composite arrangement is the best one.** k2 identified
  `core.resumable_group` as the better root for the park - its stated purpose
  is re-entering a group after an interrupt - and the skeleton reached for
  `core.group` first and never went back. Trying the resumable root is real
  work nobody has done.

### Reviewer qualifications

Left for the cold docs review of this bead. Consent clause 6 gives a spike
findings document no cure: a QUALIFIED verdict is recorded here, in the
reviewer's terms, and the document merges with the qualification standing.

_No qualifications recorded._
