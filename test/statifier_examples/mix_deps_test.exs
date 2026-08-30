defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is INTERIM (campaign 020, bead se-2p4): a git dep pinned
  # to the `statifier_blocks` main commit carrying the collapse command and the
  # document-swap re-fit, so the side-by-side sweep runs against the unreleased
  # editor. The final half of the bead returns this assertion to the Hex
  # requirement `{:statifier_blocks, "~> 0.8"}` once the operator publishes
  # 0.8.0.
  # Sabotage: changed the ref in the else arm of `statifier_blocks_dep/0` to
  # the previous `statifier_blocks` main commit
  # `"500668a7a63d324c1b901ede0c5cf7ab68671050"`; this test went red on the
  # membership assertion. A nonexistent ref would not reach the assertion at
  # all - `mix` refuses the run on the outdated lock first.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the pinned git ref" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks,
            git: "https://github.com/riddler/statifier_blocks.git",
            ref: "00bb94bbf1360d70ed86f5b8688848b6e8f9e850"} in deps
  end
end
