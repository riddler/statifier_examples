# Quality configuration for statifier_examples.
#
#   mix quality                 - full gate: format, compile, credo, dialyzer,
#                                 deps audit, full test suite with coverage.
#                                 Run before every commit.
#
#   mix quality --profile loop  - inner loop while implementing: skips dialyzer
#                                 and coverage, runs only the tests covering
#                                 changed code. Use between edits.
#
# Agents: prefer `--format json --report -` when you want to route on results.
#
# This is the family's simplest profile, copied from statifier_blocks. The
# custom stages statifier-ex carries - the gate guard, the ADR guard and
# judge, the regression ratchet - protect a conformance corpus and an accepted
# ADR set that this app does not have. Adopting one here is a decision to
# record when there is something for it to protect, not a default to inherit.
#
# There is deliberately no .credo.exs either: credo's own defaults under
# --strict are the gate until this app has a reason to deviate from one.
#
# Recorded deviation from the fleet's 90% coverage floor. `coveralls.json`
# sets minimum_coverage to 67, not 90, and that is the highest whole number
# this tree actually meets today (67.1%). The reason is that `mix phx.new`
# ships ~660 lines of relevant UI code - `core_components.ex` and
# `layouts.ex` - that nothing in the app calls yet, and 102 of
# core_components' 120 relevant lines are uncovered on their own. Nothing
# else about the gate is weakened: format, warnings-as-errors, credo
# --strict, dialyzer and the deps audit all run at full strength.
#
# Ratchet history: 29 at the scaffold (se-nuk); 67 once se-5de's signup
# domain and se-rrd's ten card-processing block types, their handlers and
# the card-processing fixture put real code under test. se-5de landed its
# code without moving the floor, so se-rrd's raise covers both.
#
# The floor is a ratchet, not a setting. Every bead that puts generated
# components to real use (se-06z's host page, se-rrd and se-5de's domains)
# should raise this number to whatever the tree then meets. It is not to be
# lowered again.

[
  format: [
    check: true
  ],
  compile: [
    warnings_as_errors: true
  ],
  credo: [
    strict: true
  ],
  profiles: [
    loop: [
      stages: [:format, :compile, :credo, :test],
      test: [scope: :changed, coverage: false]
    ]
  ]
]
