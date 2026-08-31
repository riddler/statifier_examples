defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is a Hex requirement with 0.11.0 as its floor: the
  # first release carrying ADR-0007's `StatifierBlocks.InvokeStep` - the
  # base every `myapp.*` step is one declaration on (se-4dt.1) - and
  # `StatifierBlocks.Runtime.Subchart` (se-4dt.4). 0.10.0 predates both, so
  # a resolution that could only reach it would leave the twelve step
  # modules uncompilable and no subchart handler to register. Four interim
  # git pins served this arm across the campaign era (se-p22's pattern);
  # they are retired.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched.
  #
  # Sabotage: pointed the requirement expectation here at the
  # real-but-wrong previous floor `"~> 0.10"` and left `mix.exs` alone; the
  # membership assertion went red reporting `"~> 0.11"` against the mutated
  # expectation. Reverted from a backup copy. What that proves is textual -
  # the committed requirement is the exact string asserted - and the lock
  # assertion below is what ties it to a resolved 0.11-line Hex release.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.11"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.11.)
  end

  # The engine's floor is 2.3.0: the first release carrying
  # `Statifier.Invoke.SyncHandler` and its wrapping adapter, which the
  # three domain handler modules are written against while
  # `StatifierExamples.Charts.SyncAdapter` is generated over the adapter
  # (se-4dt.2). No `override: true` remains - with every statifier-family
  # dep on Hex, each package states a requirement the resolver satisfies at
  # one version, and asserting the bare two-tuple here is what would catch
  # an override quietly returning.
  #
  # Sabotage: pointed the requirement expectation at the real-but-wrong
  # previous floor `"~> 2.2"` and left `mix.exs` alone; the membership
  # assertion went red reporting `"~> 2.3"` against the mutated
  # expectation. Reverted from a backup copy.
  test "the statifier dep is the Hex requirement, with no override" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier, "~> 2.3"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier": )))

    assert lock_line, "statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier, "2.3.)
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
