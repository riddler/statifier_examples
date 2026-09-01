defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is a Hex requirement on the 0.13 line. 0.12.0 was the
  # floor it held before, as the first release carrying the drafts shelf -
  # `core.drafts` and `core.placeholder`, `StatifierBlocks.Shelf`, and the
  # `.sb-slot--tray` strip the editor draws a parked fragment in. On 0.11.0
  # the `card_processing_sketch` fixture names two types no palette
  # resolves, so the reference embedder cannot show the tray it exists to
  # show. Five interim git pins served this arm across the campaign era
  # (se-p22's pattern); they are retired. 0.13.0 opens a non-empty shelf
  # folded and moves nothing else.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong
  # previous line `"0.12."` and left `mix.lock` alone; it went red reporting
  # the resolved `0.13.0` entry against the mutated expectation. Reverted
  # from a backup copy. The lock assertion is the one that ties the
  # requirement to a resolved 0.13-line Hex release; the membership
  # assertion above it is textual, proving only that the committed
  # requirement is the exact string named here.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.13"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.13.)
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

  # The durable stepper is held on the 0.4 line. 0.3.0 was the floor before
  # it, as the first release carrying ADR-0007's asynchronous invocation
  # seam - the dispatch fun's `:pending` arm and the `done_invocation/5` /
  # `failed_invocation/5` re-entry doors an answer arriving from an Oban job
  # comes back through (se-d74). On 0.2.0 every call is answered inside the
  # step that made it, so the asynchronous handler this app registers has no
  # seam to hang on. The interim git pin this arm carried before the release
  # is retired.
  #
  # 0.4.0 is breaking for a storage adapter that encodes `run_status/0` by
  # an exhaustive match, since it gains a fourth terminal value
  # `:cancelled`. `StatifierExamples.Persistence` delegates every
  # status-bearing callback to the package's own Ecto adapter and matches no
  # status itself, so it rides the library's encoding.
  #
  # Sabotage: pointed the requirement expectation at the
  # real-but-wrong previous floor `"~> 0.3"` and left `mix.exs` alone; the
  # membership assertion went red reporting the mutated expectation against
  # the committed `"~> 0.4"`. Reverted from a backup copy.
  test "the statifier_persistence dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.4"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.4.)
  end

  # The durable-timer package is held on the 0.4 line. Its previous
  # requirement was the patch-level `~> 0.3.1`, not `~> 0.3`, because
  # 0.3.0's cancellation query matches the delivering job itself: the
  # wizard's reminder job cancels its own delivery mid-flight and the live
  # reminder never arrives (se-p22). `~> 0.4` cannot resolve back to 0.3.0
  # at all, so the guarantee that bought the patch-level spelling is kept by
  # the major-line move and the spelling is no longer needed.
  #
  # The lock assertion is what ties the requirement to a resolved 0.4-line
  # Hex release; without it the textual check below would pass against a
  # tree still holding 0.3.1.
  #
  # Sabotage: pointed that lock assertion at the real-but-wrong
  # previous line `"0.3."` and left `mix.lock` alone; it went red reporting
  # the resolved `0.4.0` entry against the mutated expectation. Reverted
  # from a backup copy. This arm had no lock assertion before se-t8a - the
  # membership check alone would have passed against an unmoved tree.
  test "the statifier_oban dep is on the line carrying the cancel fix" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, "~> 0.4"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_oban": )))

    assert lock_line, "statifier_oban has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_oban, "0.4.)
  end
end
