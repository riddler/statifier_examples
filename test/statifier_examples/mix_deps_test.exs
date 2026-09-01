defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is a Hex requirement with 0.12.0 as its floor: the
  # first release carrying the drafts shelf - `core.drafts` and
  # `core.placeholder`, `StatifierBlocks.Shelf`, and the `.sb-slot--tray`
  # strip the editor draws a parked fragment in. On 0.11.0 the
  # `card_processing_sketch` fixture names two types no palette resolves, so
  # the reference embedder cannot show the tray it exists to show. Five
  # interim git pins served this arm across the campaign era (se-p22's
  # pattern); they are retired.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched.
  #
  # Sabotage: pointed the requirement expectation here at the
  # real-but-wrong previous floor `"~> 0.11"` and left `mix.exs` alone; the
  # membership assertion went red reporting `"~> 0.12"` against the mutated
  # expectation. Reverted from a backup copy. What that proves is textual -
  # the committed requirement is the exact string asserted - and the lock
  # assertion below is what ties it to a resolved 0.12-line Hex release.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.12"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.12.)
  end

  # The engine's floor is 2.4.0: the first release carrying
  # `Statifier.Session`'s `:inherit_invoke_handlers` option, without which a
  # child session holds no handler map and the `signup_onboarding` wizard
  # child parks at its first step (se-8zp). 2.3.0 carries
  # `Statifier.Invoke.SyncHandler` and its wrapping adapter (se-4dt.2) but
  # not the inherited map. No `override: true` remains - with every
  # statifier-family dep on Hex, each package states a requirement the
  # resolver satisfies at one version, and asserting the bare two-tuple here
  # is what would catch an override quietly returning.
  #
  # Sabotage: pointed the requirement expectation at the real-but-wrong
  # previous floor `"~> 2.3"` and left `mix.exs` alone; the membership
  # assertion went red reporting `"~> 2.4"` against the mutated
  # expectation. Reverted from a backup copy.
  test "the statifier dep is the Hex requirement, with no override" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier, "~> 2.4"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier": )))

    assert lock_line, "statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier, "2.4.)
  end

  # The durable stepper's floor is 0.3.0: the first release carrying
  # ADR-0007's asynchronous invocation seam - the dispatch fun's `:pending`
  # arm and the `done_invocation/5` / `failed_invocation/5` re-entry doors
  # an answer arriving from an Oban job comes back through (se-d74). On
  # 0.2.0 every call is answered inside the step that made it, so the
  # asynchronous handler this app registers has no seam to hang on. The
  # interim git pin this arm carried before the release is retired.
  #
  # Sabotage: pointed the requirement expectation at the real-but-wrong
  # previous floor `"~> 0.2"` and left `mix.exs` alone; the membership
  # assertion went red reporting `"~> 0.3"` against the mutated
  # expectation. Reverted from a backup copy.
  test "the statifier_persistence dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.3"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.3.)
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
