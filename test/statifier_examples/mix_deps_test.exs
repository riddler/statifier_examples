defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is the Hex requirement. It was an INTERIM git pin for the
  # length of campaign 021, on the `statifier_blocks` main commit carrying the
  # host marking seam, the drawer host-tab seam and the `invoke_types` assign;
  # 0.9.0 ships all three, so the pin came out (se-p22).
  # Sabotage: changed the requirement in the else arm of
  # `statifier_blocks_dep/0` to the real previous one, `"~> 0.8"`; this test
  # went red on the membership assertion. That requirement still resolves
  # (0.9.0 satisfies it) and the lock did not move, so the run reached ExUnit
  # - a nonexistent version would not have, `mix` refusing on resolution
  # first.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex release" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.9"} in deps
  end
end
