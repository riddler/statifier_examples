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

The seams are declared and empty today; the beads named in each module's
`@moduledoc` fill them.

Every fixture, seed and example value in this repository is fictional.
