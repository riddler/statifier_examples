defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is INTERIM (campaign 021, bead se-p22): a git dep pinned
  # to the `statifier_blocks` main commit carrying the host marking seam, the
  # drawer host-tab seam and the `invoke_types` assign, none of which are on
  # Hex. The final half of the bead returns this assertion to the Hex
  # requirement `{:statifier_blocks, "~> 0.9"}` once the operator publishes
  # 0.9.0.
  # Sabotage: changed the ref in the else arm of `statifier_blocks_dep/0` to
  # the previous `statifier_blocks` main commit
  # `"21ed991b1ff7cd81e81678b5ae320d281a28f8cb"`; this test went red on the
  # membership assertion. A nonexistent ref would not reach the assertion at
  # all - `mix` refuses the run on the outdated lock first.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the pinned git ref" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks,
            git: "https://github.com/riddler/statifier_blocks.git",
            ref: "093836a79ddfb29a6de545f597c272b19111d630"} in deps
  end
end
