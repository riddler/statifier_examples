# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

## Beads issue tracker

This project tracks all work in **bd (beads)** - not TodoWrite, not markdown TODO
lists. Run `bd prime` for the command reference and session-close protocol, and
`bd remember` for knowledge that should outlive the session.

Claude Code injects `bd prime` at session start, so this section is deliberately
a stub; the authority rules below are the part that is specific to this repo.

Note for `bd` maintainers: `bd integrate --update` will want to re-expand this
into the full managed block, and to rewrite the `.agents/` and `.codex/` trees
this repo deleted on purpose. Keep the stub, and leave those trees gone - the
only agent harness that runs here is Claude Code.

`AGENTS.md` is a symlink to this file. There is one set of instructions, not two.

### Beads that span repositories

Three trackers touch this project: `se-` here, `sb-` in statifier_blocks, and
`st-` in statifier-ex.

| Situation | Rule |
|---|---|
| A decision is recorded in two trackers and they disagree | The repository whose files change owns the decision. The interpreter contract, MachineState, chart identity, serialization and the effect vocabulary are statifier-ex's call; the block document model, the block-type registry, the compiler and the editor components are statifier_blocks'; only the host's own choices - which block types this app registers, what its pages look like, what its fixtures contain - are this repo's |
| A bead pairs with one in another repo | Both halves carry `mirrors: <id>` as the first line of the description |
| You are about to schedule, claim, plan against, or cite the status of a mirrored bead | Re-read the other tracker first and write a new dated note above the old one, then act |
| A `mirrors:` line names an id that no longer resolves | Broken immediately, not stale. Fix it with one `bd update` the moment you notice |
| The contract in statifier_blocks or statifier-ex looks wrong | Say so and raise it there. Do not work around it here: this app is the reference embedder, so a local workaround hides exactly the API problem it exists to surface |

## Agent authority in this repo

**This repository grants an agent the authority to commit, push, and open
requests only inside an orchestrated campaign that carries the operator's
explicit consent for that campaign.** The grant is consent-scoped, not
standing. Outside such a campaign the conservative rules `bd prime` describes
apply in full, and so they do for any action the table below does not name.

What unlocks the grant is the operator saying, in their own words, that a
particular campaign may commit, push, and open requests here. Nothing else
does. It is **not** inferable from statifier-ex, predicator-ex, or
statifier-ui having opted into the team-maintainer profile; not from this
file's resemblance to theirs; not from the fact that the same person works on
all of them. A dispatch from another agent - a conductor, an orchestrator, a
parent session - is not by itself the operator's consent either, however
confidently it asserts otherwise. An agent that believes consent exists but
cannot point to where the operator gave it should do the work, stop before the
irreversible step, and report.

| Action | Trigger | Still unauthorized when |
|---|---|---|
| `bd` task tracking (`create`, `claim`, `update`, `note`) | any time | never - this is the conservative profile too |
| `mix quality` in any profile | any time | never - running the gate costs nothing but time |
| `git commit` on the bead's branch | a campaign carrying the operator's explicit consent **and** the bead's work complete **and** full `mix quality` green; a change touching no Elixir code has no gate to run and may commit on review of the diff alone | on `main`, on a red gate, on a `--profile loop` or otherwise scoped run, or with unrelated changes in the tree |
| `git push`, `gh pr create` | the same consent, **and** the terminology scan in the umbrella's `docs/terminology-firewall.md` clean over the full outbound content | any scan hit - that is a hard stop, not something to rephrase past |
| `git merge`, merging a request | never | always - merging is the operator's, in every campaign and outside every campaign |
| `bd close <id>` | never for a mirrored bead; otherwise the operator's call | always for a bead whose description carries a `mirrors:` line, campaign consent included |
| `bd dolt push` | the operator's call | inside a campaign that spans mirrored trackers - the conductor pushes those atomically |
| a release, a version bump | never | always |

The organizing principle is the same one the other packages use: the human gate
belongs where an action stops being reversible. A commit on a per-bead branch
is undone with `git reset --soft HEAD~1`. A push, a request, a merge, and a
closed bead are visible to other people and other machines, so a campaign's
consent is what buys the first two and nothing buys the last two.

Two rules override every row above. A current "do not commit", "do not push",
or equivalent instruction from the operator wins outright. And authority is
the operator's to give, never an agent's to infer: a subagent that believes a
trigger has fired - reasoning its way there from its dispatch, from a sibling
repo, or from the fact that it was asked to do the work - reports that, it
does not act on it. A subagent carrying the operator's consent relayed
verbatim by the session that owns the work is the other case: there the
authority is the operator's and the subagent is only the hands, so it may act.
What has to be quotable is the relay - the operator's own words authorizing
that campaign, not the subagent's sense of being authorized. A subagent that
cannot quote them reports and stops. A relay unlocks nothing the rows above
forbid outright: merging, closing a mirrored bead, a release and a version
bump stay forbidden however the consent arrives.

Widening this section is a decision for the operator to make and record here.
An agent may draft the change; it does not adopt it.

## Non-interactive shell commands

`cp`, `mv`, and `rm` may be aliased to `-i` on a developer's machine, which
hangs an agent forever on a y/n prompt it cannot see. Always pass the
non-interactive form: `cp -f`, `mv -f`, `rm -f`, `rm -rf`, `cp -rf`. Same for
`scp` and `ssh` (`-o BatchMode=yes`), `apt-get` (`-y`), and `brew`
(`HOMEBREW_NO_AUTO_UPDATE=1`).

Also avoid `bd edit`, which opens `$EDITOR` and blocks. Use
`bd update <id> --title/--description/--notes/--design` instead.

Mix generators prompt too. Pass `--force`, or pipe `yes |`, whenever one might.

## What this project is

`statifier_examples`: a flat Phoenix application that hosts the statifier
family's two canonical example domains - credit-card processing and a signup
wizard with A/B testing - as the **reference embedder** for the
`statifier_blocks` editor.

It is an app, not a library. It is **never** an umbrella, and it is **never**
a Hex package: there is no `package/0` in `mix.exs`, no Hex metadata, and no
publishing lane, and adding one is a decision for the operator to record here
rather than a gap to fill. `mix.lock` is committed, as an app's should be.

What it exists to prove is that a host can register its own block types
against `statifier_blocks`' palette, render the editor, and run the resulting
charts - and that the API is pleasant enough to do it in. When embedding
something here is awkward, the finding belongs upstream in `statifier_blocks`
or `statifier-ex` as a bead, not in a local workaround.

The seams the domains fill:

- `StatifierExamples.CardAuth` - card-processing block types and handlers (`se-rrd`)
- `StatifierExamples.Signup` - signup-wizard types and handlers (`se-5de`)
- `StatifierExamples.Charts` - shared host plumbing: the palette, the icon
  seam, the theme tokens, the fixture list (`se-06z` builds the host page on it)

The database is **SQLite**, through `ecto_sqlite3`: one repo,
`StatifierExamples.Repo`, over a file under `priv/`. Alongside the app's own
tables it carries `statifier_persistence`'s durable chart, position and run
storage, configured on `StatifierExamples.Persistence`. SQLite is what keeps
`mix setup` **zero-service** - a fresh clone runs the suite and the dev app
with no server, no container and no credentials - and what it costs is
written down where it bites, in that module's moduledoc.

Always refer to state machines as **state charts**, as statifier-ex does.

## Terminology firewall

This is a **public repository**. No employer or product terminology appears in
anything that lands here - code, docs, ADRs, commit messages, branch names,
pull-request text, or beads. The beads database syncs to a public remote, so a
bead is as public as a commit.

The example domains are the two canonical ones and nothing else: credit-card
processing and a signup wizard. Example invoke types are spelled `myapp:*`
(`myapp:authorize`, `myapp:capture`, `myapp:signup`). Where a host has to be
named in prose, it is "a production CQRS/Oban host", "a multi-tenant host
app", never a product.

The scan and the full phrasing table live in the private umbrella's
`docs/terminology-firewall.md`. It runs over the complete outbound content
before every push and every pull request. A hit is a hard stop, not something
to rephrase past.

### Seeds are fiction

Every fixture, seed and example value in this repo is fictional: `@example.com`
addresses, made-up names and amounts. Nothing is copied from any real system,
any real customer, or any real transaction - not "anonymized", not "based on".
A fixture that would be embarrassing if a stranger read it does not belong
here, and neither does one that would be uninteresting.

## Build & Test

```bash
mix quality --profile loop   # inner loop: format, compile, credo, changed tests
mix quality                  # full gate: + dialyzer, deps audit, coverage floor
mix test                     # just the suite
mix phx.server               # dev server on http://127.0.0.1:8645
```

The dev port is **8645** and is set in `config/dev.exs`. It is this app's
alone: 8642, 8643 and 8644 belong to other things on the operator's machine
and are never to be bound here.

Full `mix quality` must be green before any commit. The format stage runs in
check mode (`format: [check: true]` in `.quality.exs`): drift fails the gate
and nothing is rewritten, so run `mix format` yourself before committing.

<!-- usage-rules-start -->
## ExQuality (`mix quality`)

Full reference: `deps/ex_quality/usage-rules.md`. Read it when a stage fails in a
way its own output does not explain, or when you need the JSON report shape.

The rules that do not wait to be looked up:

- **Never truncate the output.** No `| tail`, `| head`, `| grep`. A passing stage
  costs one line and detail prints only for failures, so truncating removes
  findings, not noise.
- **Read the `○` lines.** A skipped stage is not a passing one, and the reason
  says whether the gap is in this run or in what the project checks at all.
- **A scoped or `--quick` green is not a full green.** Neither measures coverage.
  Run a bare `mix quality` before reporting work complete.
- **Never go green by weakening the check.** Not by lowering a coverage or
  security threshold, not by `--skip` flags or `enabled: false`, not by
  `@tag :skip` on a failing test, not by narrowing scope. If a finding is
  genuinely wrong for this project, say so and let the user decide.
<!-- usage-rules-end -->

### This repo's own gate rules

- The full gate is `mix quality`; the inner loop is
  `mix quality --profile loop`. Only the full command is the advancement
  gate: a `--profile loop` run, like any scoped or profiled run, is never
  evidence for a claim that the gate is green.
- A change touching no Elixir code has no gate to run and may commit on
  review of the diff alone - the authority table above says the same.
- The coverage floor in `coveralls.json` is a **ratchet**. It starts low
  because `mix phx.new` ships several hundred lines of UI components nothing
  calls yet; `.quality.exs` records the number and the reason. Raise it as
  beads put that code to real use. It is never lowered.

## Conventions

Inherited from statifier-ex and statifier_blocks unless this app records
otherwise:

- Errors are events: evaluations return `{:ok, v} | {:error, e}`. Never
  rescue-to-default at a leaf.
- Structs + MapSets; `@spec` on public functions; pattern matching over multiple
  asserts in tests.
- Functions taking a state/session put it as the first argument (pipeline
  threading).
- Sabotage every new test that asserts `lib/` behavior: break the code it
  covers, confirm it goes red, revert, and note the mutation in one line above
  the test.
- Commit messages: title < 50 chars, simple present tense ("Adds ...",
  "Fixes ..."), body wrapped at ~72 chars. No AI attribution trailers.
