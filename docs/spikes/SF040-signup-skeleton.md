# SF040 - the signup walking skeleton

A spike, in four beads. A Path is a `statifier_blocks` document plus one
element document per screen (Riddler R10a); this app is where that claim gets
built small enough to argue with.

| Bead | What it added |
|---|---|
| `se-e68` (k1) | the element document, four element types, and the renderer |
| `se-19h` (k2) | the screen Composite and a three-screen Path |
| k3 | a durable run of that Path |
| `k4` | the findings this document collects |

This file is created by k1 and completed by k4. Each bead appends its own
section; nothing rewrites an earlier one.

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
