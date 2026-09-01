defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # The statifier-ex commit the interim pin names: PR 251's merge on that
  # repo's main, which is the first commit carrying
  # `:inherit_invoke_handlers`. Written once here so the `mix.exs`
  # requirement and the `mix.lock` entry are asserted against the same
  # string rather than two hand-copied ones.
  @statifier_ref "6b4ff697b6db3f8c7378001fa15a7f9f8b901ef6"

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

  # The engine is on an INTERIM git pin (se-8zp, campaign-024): 2.3.0 - the
  # floor this arm held - carries `Statifier.Invoke.SyncHandler` and its
  # wrapping adapter (se-4dt.2) but not `Statifier.Session`'s
  # `:inherit_invoke_handlers`, without which a child session holds no
  # handler map and the `signup_onboarding` wizard child parks at its first
  # step (statifier-ex st-pvpz, PR 251, merged as this ref).
  #
  # `override: true` is asserted rather than tolerated: a git ref satisfies
  # none of the Hex requirements `statifier_blocks`, `statifier_persistence`
  # and `statifier_oban` each state on `statifier`, so without it the tree
  # does not resolve at all. Both go at the FINAL re-pin to 2.4.0.
  #
  # `mix.exs` and `mix.lock` are checked against each other, as the two
  # assertions above are: an edit to one without the other resolves to
  # whatever was already fetched.
  #
  # Sabotage: pointed the `ref:` expectation at the real-but-wrong previous
  # statifier-ex main `df705b8` (the commit before PR 251) and left
  # `mix.exs` alone; the membership assertion went red reporting the real
  # ref against the mutated expectation. Reverted from a backup copy.
  test "the statifier dep is the interim git pin, in mix.exs and mix.lock alike" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier, github: "riddler/statifier-ex", ref: @statifier_ref, override: true} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier": )))

    assert lock_line, "statifier has no mix.lock entry"

    assert lock_line =~
             ~s({:git, "https://github.com/riddler/statifier-ex.git", "#{@statifier_ref}")
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
