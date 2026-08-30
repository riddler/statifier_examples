defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is INTERIM (campaign 019, bead se-9o0): a git dep pinned
  # to the `statifier_blocks` main commit carrying the findings anatomy work,
  # so the sweep runs against the unreleased editor. The final half of the bead
  # returns this assertion to the Hex requirement `{:statifier_blocks, "~> 0.7"}`
  # once the operator publishes 0.7.0.
  # Sabotage: changed the ref in the else arm of `statifier_blocks_dep/0` to
  # `"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"`; this test went red on the
  # membership assertion.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the pinned git ref" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks,
            git: "https://github.com/riddler/statifier_blocks.git",
            ref: "ec05e5632c373f6ae71abef6cc9e12ecc8abf6e9"} in deps
  end
end
