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
