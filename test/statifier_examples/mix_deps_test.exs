defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is the Hex requirement `{:statifier_blocks, "~> 0.8"}`.
  # Sabotage: changed the else arm of `statifier_blocks_dep/0` to
  # `{:statifier_blocks, "~> 0.7"}`; this test went red on the membership
  # assertion.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement `~> 0.8`" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.8"} in deps
  end
end
