# Release extension

There is no release here, and this file exists to say so in the place a
reader looks for one.

`/wurk:release` reads `.claude/wurk.json`'s `release` block before anything
else. In this repo that block is `null`, and the skill's own contract is to
refuse when the project has no recipe. That refusal is the correct outcome,
not a gap: nothing below adds a step, because there is no recipe for a step
to be added to.

## Why there is no recipe

This project is an application, not a package. `CLAUDE.md`'s "What this
project is" section says so outright:

> It is an app, not a library. It is **never** an umbrella, and it is
> **never** a Hex package: there is no `package/0` in `mix.exs`, no Hex
> metadata, and no publishing lane, and adding one is a decision for the
> operator to record here rather than a gap to fill.

and the sentence just above it gives the app the role it has instead:

> `statifier_examples`: a flat Phoenix application that hosts the statifier
> family's two canonical example domains - credit-card processing and a
> signup wizard with A/B testing - as the **reference embedder** for the
> `statifier_blocks` editor.

A reference embedder proves the packages are pleasant to embed. It is
consumed by reading it and by running it, never by depending on it, so it has
no version anyone outside this repo can pin. `mix.exs` carries a version
because Mix requires one; nothing reads it.

So a "release" here means nothing at all. There is no tag to cut, no artifact
to publish, no `@version` to promote, and no version bump - the authority
table in `CLAUDE.md` gives "a release, a version bump" the row
`never | always`, so a bump here is forbidden outright, not merely
unnecessary. The one place a version-shaped change is legitimate is a
dependency **pin**: this app pins `statifier_blocks` (and, at times, other
family packages), and moving a pin is ordinary work on an ordinary bead, not
a release.

If that ever changes - if the operator records a decision in `CLAUDE.md` that
this app becomes publishable - then `release` in `.claude/wurk.json` grows a
recipe and this file is rewritten to extend it. Until that decision is
recorded, a reader who arrived here looking for release steps has found the
answer: there are none.

## Why there are no changelog fragments

`.claude/wurk.json` declares `"changelog": {"mode": "none"}`. That is a
deliberate declaration, not an omission, and it is consistent with everything
above: fragments exist to be assembled into a version section at a release,
and this repo has no release to assemble them at.

The consequences, stated so that no one has to re-derive them:

- **This repo keeps no changelog fragments.** There is no `changelog.d/`, and
  a bead worked here does not write one.
- **`changelog.d/` is not to be created.** `mode: "none"` disclaims the
  directory; creating it would stand up fragment infrastructure the manifest
  says this repo does not have, and the first release that never comes would
  never consume it. The sibling packages that do keep fragments -
  `statifier_blocks` and `statifier-ui`, both `mode: "fragments"` with a
  `changelog.d` dir and a `kind: "hex"` recipe - are the contrast, not the
  model.
- **There is no `CHANGELOG.md` promotion step**, because there is no
  changelog and no release commit to put one in.

A bead worked here therefore has no changelog obligation of any kind. Its
history is its commits and its bead notes.

### The sibling-re-check rule, and why it is dormant here

The fleet carries a standing rule for fragment-keeping repos: a release prep
consumes and deletes the `changelog.d/` fragments that exist when it runs, so
**a sibling branch that merges after a release prep has landed must re-check
its own fragment by hand** - the prep could not have consumed a fragment that
was not on `main` yet, and the fragment is left stranded in `changelog.d/`
pointing at a version that already shipped.

That rule cannot fire in this repo, because there is no prep and no fragment
for a prep to strand. It is written down anyway so that its absence is a
recorded consequence rather than an oversight: **it applies here only if
`changelog.mode` is ever changed to `fragments`**, and on that day it applies
in full - a sibling merging after a release prep re-checks its own fragment by
hand, and whoever flips the mode adds the step to this file rather than
leaving the rule implicit.

## What a release commit touches here

Nothing. There is no release commit in this repo, so there is no file table.
