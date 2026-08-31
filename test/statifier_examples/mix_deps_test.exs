defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is the Hex requirement. It was an INTERIM git pin for the
  # length of campaign 021, on the `statifier_blocks` main commit carrying the
  # host marking seam, the drawer host-tab seam and the `invoke_types` assign;
  # 0.9.0 ships all three, so the pin came out (se-p22).
  # Sabotage: changed the requirement in the else arm of
  # `statifier_blocks_dep/0` to the real previous one, `"~> 0.8"`; this test
  # went red on the membership assertion. That requirement still resolves
  # (0.9.0 satisfies it) and the lock did not move, so the run reached ExUnit
  # - a nonexistent version would not have, `mix` refusing on resolution
  # first.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex release" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.9"} in deps
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
