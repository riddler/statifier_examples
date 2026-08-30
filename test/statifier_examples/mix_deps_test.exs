defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default has to
  # be the Hex requirement so CI - which sets no env - resolves from Hex.
  # Sabotage: changed the else arm of `statifier_blocks_dep/0` to
  # `{:statifier_blocks, "~> 0.5"}`; this test went red on the membership
  # assertion.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.6"} in deps
  end
end
