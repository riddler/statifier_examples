defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is the Hex requirement. It was an INTERIM git pin twice:
  # for the length of campaign 021, until 0.9.0 shipped the seams it stood in
  # for (se-p22); and again for campaign 022, on the `statifier_blocks` commit
  # accepting ADR-0001 decision 11, because the document `datamodel` key the
  # three fixtures under `priv/fixtures/` carry postdates 0.9.0 - the older
  # decoder drops an envelope key it does not recognize in silence, which is
  # the round-trip hole decision 11e closes, so on 0.9.0 the fixtures decoded
  # and every declaration in them was simply gone. 0.10.0 ships the key, the
  # allowlist and the `core.on_event` `cond`, so the pin came out (se-1xc).
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than each
  # against a hope, the way `DependencyPinsTest` checks the remaining git pin:
  # a `mix.exs` edit without the matching lock entry resolves to whatever was
  # already fetched. The lock assertion is what makes the requirement a floor
  # rather than a spelling - `~> 0.10` is satisfied by a range of releases,
  # and this records which one the app is actually built and tested against.
  #
  # Sabotage: changed the expected requirement here to the real-but-wrong
  # previous spelling `"~> 0.9"` and re-ran; the membership assertion went red
  # reporting `{:statifier_blocks, "~> 0.10"}` against a deps list holding
  # nothing of the sort. `"~> 0.9"` still admits 0.10.0, so `mix` resolved and
  # the lock did not move, which is why the run reached ExUnit at all - a
  # nonexistent version would have aborted at resolution and proved nothing.
  # Reverted from a backup copy.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex release" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.10"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.10.0",)
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
