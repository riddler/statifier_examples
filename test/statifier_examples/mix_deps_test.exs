defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  @statifier_blocks_ref "487cebf146c5e46f0e674c57a85f4806aeeec8ac"
  @statifier_ref "a0f965e6b15868fb05bd0d05981ac18d64d0344c"

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is an INTERIM git pin, the fourth this dep has carried
  # (se-p22's pattern: pin to the pushed upstream commit, re-pin to Hex at
  # the release). It stands on the `statifier_blocks` commit documenting the
  # shipped subchart handler, which carries both surfaces this app is
  # written against: ADR-0007's `StatifierBlocks.InvokeStep` - the base
  # every `myapp.*` step is one declaration on (se-4dt.1) - and
  # `StatifierBlocks.Runtime.Subchart` (se-4dt.4). 0.10.0 predates both, so
  # on the released package the twelve step modules do not compile at all
  # and there is no subchart handler to register.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than each
  # against a hope, the way `DependencyPinsTest` checks the other git pin: a
  # `mix.exs` edit without the matching lock entry resolves to whatever was
  # already fetched.
  #
  # Sabotage: pointed the expectation here at the real-but-wrong previous
  # `statifier_blocks` main 957ea91ed54abecdc91cc9ae9c6e4c9314e15417 (the
  # ADR-0007 pin this bead moved off) and left `mix.exs` alone; both
  # assertions went red, reporting the subchart-handler ref against the
  # mutated expectation. Reverted from a backup copy.
  #
  # Mutating `mix.exs` instead proves less, not more: on an earlier ref the
  # package has no `StatifierBlocks.InvokeStep` at all, so every step module
  # fails to compile and the run never reaches ExUnit. That the pin is
  # load-bearing is worth knowing; it is not this test going red.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the interim git pin" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks,
            git: "https://github.com/riddler/statifier_blocks.git", ref: @statifier_blocks_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ @statifier_blocks_ref
  end

  # The engine carries an INTERIM git pin of its own, on the commit that
  # adds `Statifier.Invoke.SyncHandler` and its wrapping adapter. Hex 2.2.1
  # has neither, and this app's three domain handler modules are written
  # against the behaviour while `StatifierExamples.Charts` is generated over
  # the adapter, so on the released engine the app does not compile at all
  # (se-4dt.2). `override: true` is part of the assertion rather than
  # incidental: `statifier_persistence`'s git ref brings its own
  # `statifier-ex` dependency, and dropping the override would let this app
  # inherit that one instead of stating its own.
  #
  # Sabotage: pointed the expectation here at the real-but-wrong previous
  # `statifier-ex` main caa9e215d3da3b88c9fe4760c028f9d0bcae1151 (the commit
  # before the SyncHandler pair landed) and left `mix.exs` alone; both
  # assertions went red, reporting the SyncHandler ref against the mutated
  # expectation. Reverted from a backup copy.
  #
  # Mutating `mix.exs` instead proves less, for the same reason the
  # `statifier_blocks` note above gives: on caa9e21 there is no
  # `Statifier.Invoke.SyncHandler.Adapter` to `use`, so the app fails to
  # compile and the run never reaches ExUnit.
  test "the statifier dep is the interim git pin, override included" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier,
            [
              git: "https://github.com/riddler/statifier-ex.git",
              ref: @statifier_ref,
              override: true
            ]} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier": )))

    assert lock_line, "statifier has no mix.lock entry"
    assert lock_line =~ @statifier_ref
  end

  # The durable-timer package is held at `~> 0.3.1`, not `~> 0.3`: 0.3.0's
  # cancellation query matches the delivering job itself, so the wizard's
  # reminder job cancels its own delivery mid-flight and the live reminder
  # never arrives. `~> 0.3` would merely permit the fixed release; this
  # requirement demands it, so a resolution that could only reach 0.3.0
  # fails outright rather than silently losing the reminder (se-p22).
  # Sabotage: changed the requirement to the real-but-wrong previous
  # spelling `"~> 0.3.0"`; this test went red on the membership assertion.
  # What that proves is textual - the committed requirement is the exact
  # string asserted here. What it does NOT prove is a resolution floor:
  # `"~> 0.3.0"` still admits 0.3.1, so the mutated tree resolved and the
  # lock did not move, which is why the run reached ExUnit at all (the same
  # honest reading the `statifier_blocks` assertion above is written under).
  test "the statifier_oban dep requires the release carrying the cancel fix" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, "~> 0.3.1"} in deps
  end
end
