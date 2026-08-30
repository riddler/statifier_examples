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

```sh
mix setup        # deps, tailwind, esbuild
mix phx.server   # http://127.0.0.1:8645
```

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
  `card.authorization_timed_out` at the head of the authorization group's
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
