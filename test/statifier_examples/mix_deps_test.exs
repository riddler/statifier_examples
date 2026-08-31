defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `statifier_blocks` main at the commit that accepted ADR-0001 decision 11
  # (sb PR 188), which is the first commit whose decoder reads the document
  # `datamodel` key this app's fixtures now carry.
  @statifier_blocks_ref "4561598f703fbae565be9e38bf540a764930fff2"

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is an INTERIM git pin, for the second time. It was one
  # for the length of campaign 021 and came out at 0.9.0 (se-p22); it is one
  # again for se-1xc, because sb ADR-0001 decision 11's document `datamodel`
  # key postdates 0.9.0 and the three fixtures under `priv/fixtures/` now
  # carry it. Verified rather than assumed: with the ref moved back to the
  # 0.9.0 release-prep commit the fixtures still decode - the older decoder
  # drops an envelope key it does not recognize in silence, which is the
  # round-trip hole decision 11e closes - and every declaration in them is
  # simply gone. That is why this is a floor and not a preference. Re-pin
  # to `~> 0.10` once that release exists.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than each
  # against a hope, the way `DependencyPinsTest` checks the other git pin: a
  # `mix.exs` edit without the matching lock entry resolves to whatever was
  # already fetched.
  #
  # Sabotage: pointed the `ref:` at
  # c35c02baba49631dee61c5aa9e75d0f1342e7b08 - the real `statifier_blocks`
  # main commit before this one, so `mix deps.get` still succeeds and ExUnit
  # still runs, which a nonexistent ref would not - then `mix deps.get`;
  # both assertions went red reporting that ref. Reverted.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the recorded git ref" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    assert File.read!("mix.exs") =~ ~s(ref: "#{@statifier_blocks_ref}")

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ @statifier_blocks_ref
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
