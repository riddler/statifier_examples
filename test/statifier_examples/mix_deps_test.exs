defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # The statifier-ex commit the interim pin names: PR 251's merge on that
  # repo's main, which is the first commit carrying
  # `:inherit_invoke_handlers`. Written once here so the `mix.exs`
  # requirement and the `mix.lock` entry are asserted against the same
  # string rather than two hand-copied ones.
  @statifier_ref "6b4ff697b6db3f8c7378001fa15a7f9f8b901ef6"

  # The statifier_persistence commit the second interim pin names: the tip
  # of that repo's main carrying ADR-0007's asynchronous invocation seam
  # (PR 35), which is the first commit with a `:pending` dispatch arm and
  # the two re-entry doors. Written once here for the same reason
  # `@statifier_ref` is: `mix.exs` and `mix.lock` are asserted against one
  # string rather than two hand-copied ones.
  @statifier_persistence_ref "65ef280d77b70c7560fb045ae71e1ec3bc08709d"

  # The statifier_blocks commit the third interim pin names: the tip of that
  # repo's main carrying the drafts shelf (PR 201), which is the first
  # commit with `core.drafts`, `core.placeholder`, `StatifierBlocks.Shelf`
  # and the `.sb-slot--tray` strip. Written once here for the same reason
  # the two refs above are: `mix.exs` and `mix.lock` are asserted against
  # one string rather than two hand-copied ones.
  @statifier_blocks_ref "a3833479257fb0692eea65ed50c00c939b489f36"

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is an INTERIM git pin (se-ihm, campaign-024). 0.11.0 -
  # the Hex floor this arm held - carries ADR-0007's
  # `StatifierBlocks.InvokeStep`, the base every `myapp.*` step is one
  # declaration on (se-4dt.1), and `StatifierBlocks.Runtime.Subchart`
  # (se-4dt.4). What it does not carry is the drafts shelf: without
  # `core.drafts` and `core.placeholder` the `card_processing_sketch`
  # fixture names two types no palette resolves, so the reference embedder
  # cannot show the tray it exists to show.
  #
  # No `override: true` here: nothing else in this tree states a
  # requirement on `statifier_blocks`, so the git ref is the only claim on
  # it and resolves on its own.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched.
  #
  # Sabotage: pointed the `ref:` expectation at the real-but-wrong previous
  # statifier_blocks main `487cebf146c5e46f0e674c57a85f4806aeeec8ac` (the
  # commit se-4dt.4 pinned) and left `mix.exs` alone; the membership
  # assertion went red reporting the real ref against the mutated
  # expectation. Reverted from a backup copy.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the interim git pin" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, github: "riddler/statifier_blocks", ref: @statifier_blocks_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"

    assert lock_line =~
             ~s({:git, "https://github.com/riddler/statifier_blocks.git", "#{@statifier_blocks_ref}")
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

  # The durable stepper is on an INTERIM git pin too (se-d74,
  # campaign-024 ruling R-c). 0.2.0 - the floor this arm held - carries
  # `StatifierPersistence.Driver`, but every call it drives is answered
  # inside the step that made it: the `:pending` dispatch arm and the
  # `done_invocation/5` / `failed_invocation/5` re-entry doors an Oban job
  # answers through arrived with that package's ADR-0007, unpublished at
  # the time of this pin.
  #
  # No `override: true` here, unlike the engine's pin above: nothing else
  # in this tree states a requirement on `statifier_persistence`, so the
  # git ref is the only claim on it and resolves on its own.
  #
  # `mix.exs` and `mix.lock` are checked against each other, as every
  # assertion in this module is.
  #
  # Sabotage: pointed the `ref:` expectation at the real-but-wrong
  # previous statifier_persistence main `6e64b81` (the ADR status flip,
  # one commit before the 0.3.0 prep) and left `mix.exs` alone; the
  # membership assertion went red reporting the real ref against the
  # mutated expectation. Reverted from a backup copy.
  test "the statifier_persistence dep is the interim git pin, in mix.exs and mix.lock alike" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence,
            github: "riddler/statifier_persistence", ref: @statifier_persistence_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"

    assert lock_line =~
             ~s({:git, "https://github.com/riddler/statifier_persistence.git", "#{@statifier_persistence_ref}")
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
