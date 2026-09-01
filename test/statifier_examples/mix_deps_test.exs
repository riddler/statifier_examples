defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is an INTERIM GIT PIN and not a Hex requirement, which
  # is the sixth of them this arm has carried (se-p22's pattern) and the
  # one this test now guards. `StatifierBlocks.Runtime.DurableSubchart` -
  # the handler that answers `core.subchart` by starting the child as its
  # own persisted run - landed after 0.13.0, and se-6ag's durable subchart
  # proof is written against it. The 0.13 line carries only the in-memory
  # `StatifierBlocks.Runtime.Subchart`, whose `{:start_child, _, _}`
  # nothing but `Statifier.Session` executes.
  #
  # **A re-pin to the Hex release carrying sb-2i04 is owed**, and this test
  # is what makes forgetting it loud rather than silent: the pin is written
  # out here in full, so the arm has to be edited deliberately to move.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong ref of the
  # commit before it (`84fd1c8...`) and left `mix.lock` alone; it went red
  # reporting the resolved `05f0a4a...` entry against the mutated
  # expectation. Reverted from a backup copy.
  @statifier_blocks_ref "05f0a4ab0c9a1adb1c8857d0b5642a8b19cc7e98"

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
    assert lock_line =~ ~s({:git, "https://github.com/riddler/statifier_blocks.git")
    assert lock_line =~ @statifier_blocks_ref
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
  # It is an INTERIM GIT PIN as of se-6ag, and not the `~> 0.4` Hex
  # requirement it held before. 0.4.0 carries all of ADR-0008's durable
  # subchart machinery except the one piece a host has to have: sp-2yx
  # widened `StatifierPersistence.Driver.dispatch_context/0` to carry
  # `:invoke`, the whole effect being dispatched, without which a dispatch
  # fun cannot reach `src` and `StatifierBlocks.Runtime.DurableSubchart`
  # raises rather than guess.
  #
  # **A re-pin to the Hex release carrying sp-2yx is owed**, and as with
  # the editor arm above this test is what makes forgetting it loud.
  #
  # 0.4.0 was also breaking for a storage adapter that encodes
  # `run_status/0` by an exhaustive match, since it gains a fourth terminal
  # value `:cancelled`. `StatifierExamples.Persistence` delegates every
  # status-bearing callback to the package's own Ecto adapter and matches no
  # status itself, so it rides the library's encoding.
  #
  # The pin moved FORWARD for se-opg and is still interim: sp-i21 landed
  # ADR-0009's storage-phase telemetry after 1416a7b, and
  # `[:statifier_persistence, :run, :step, :start | :stop]` is the span
  # every durable macrostep nests inside and the one the capstone's trace
  # graph is built out of. On 1416a7b the durable subchart runs correctly
  # and emits nothing.
  #
  # Sabotage: pointed the pin constant at the commit before this one
  # (`b25dd5b`, padded to a full-length ref) and left `mix.exs` and
  # `mix.lock` alone; it went red on the membership assertion, reporting
  # the real `0749481...` arm against the mutated expectation. Reverted
  # from a backup copy.
  @statifier_persistence_ref "0749481762a0b06db6be5f0a6f71f13e658aa259"

  test "the statifier_persistence dep is the interim git pin" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence,
            github: "riddler/statifier_persistence", ref: @statifier_persistence_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:git, "https://github.com/riddler/statifier_persistence.git")
    assert lock_line =~ @statifier_persistence_ref
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
  # It is an INTERIM GIT PIN as of se-opg, and no longer the `~> 0.4` Hex
  # requirement. sob-43q landed ADR-0006's eleven telemetry events after
  # 0.4.0, and two of them are edges the capstone's trace graph asserts:
  # `[:statifier_oban, :timer, :scheduled]` and `[..., :timer, :fired]`.
  # On 0.4.0 a timer arms and fires and the graph has no edge across the
  # gap.
  #
  # **A re-pin to the Hex release carrying sob-43q is owed** (se-a5y), and
  # this test is what makes forgetting it loud.
  #
  # Sabotage: pointed the pin constant at the commit before this one
  # (`4f9df2e`, padded to a full-length ref) and left `mix.exs` and
  # `mix.lock` alone; it went red on the membership assertion, reporting
  # the real `4bf3a7d...` arm against the mutated expectation. Reverted
  # from a backup copy.
  @statifier_oban_ref "4bf3a7d195086e055bb9bc84fe174ed4a14e5d67"

  test "the statifier_oban dep is the interim git pin" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, github: "riddler/statifier_oban", ref: @statifier_oban_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_oban": )))

    assert lock_line, "statifier_oban has no mix.lock entry"
    assert lock_line =~ ~s({:git, "https://github.com/riddler/statifier_oban.git")
    assert lock_line =~ @statifier_oban_ref
  end

  # The OTel bridge, which this app had no dependency on before se-opg -
  # nothing here produced a trace, so there was nothing to bridge.
  #
  # Also an INTERIM GIT PIN: the two SIBLING setup calls the capstone needs,
  # `OpentelemetryStatifier.Persistence.setup/1` and
  # `OpentelemetryStatifier.Oban.setup/1`, landed after 0.2.0. On 0.2.0
  # only the interpreter half exists, which in a durable run bridges
  # nothing at all.
  #
  # **A re-pin to the Hex release carrying the sibling setups is owed**
  # (se-a5y).
  #
  # Sabotage: pointed the pin constant at the commit before this one
  # (`2ab436d`, padded to a full-length ref) and left `mix.exs` and
  # `mix.lock` alone; it went red on the membership assertion, reporting
  # the real `99d7791...` arm against the mutated expectation. Reverted
  # from a backup copy.
  @opentelemetry_statifier_ref "99d7791dcfd11918464b3a1ad3cdd43614379588"

  test "the opentelemetry_statifier dep is the interim git pin" do
    deps = Mix.Project.config()[:deps]

    assert {:opentelemetry_statifier,
            github: "riddler/opentelemetry_statifier", ref: @opentelemetry_statifier_ref} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "opentelemetry_statifier": )))

    assert lock_line, "opentelemetry_statifier has no mix.lock entry"
    assert lock_line =~ ~s({:git, "https://github.com/riddler/opentelemetry_statifier.git")
    assert lock_line =~ @opentelemetry_statifier_ref
  end

  # The SDK behind the bridge. `opentelemetry_statifier` depends only on
  # `opentelemetry_api` on purpose - a bridge that dragged an SDK into
  # every host would be choosing the host's exporter for it - so the host
  # is where both are named, and this asserts they are Hex requirements
  # rather than pins that would need retiring with the others.
  #
  # Sabotage: changed the expected requirement for `opentelemetry` to
  # `"~> 1.4"`; it went red on the membership assertion, which is the
  # point - the resolved 1.7.0 satisfies `~> 1.4` perfectly well, so only
  # a check on the literal arm catches the requirement being loosened.
  # Reverted from a backup copy.
  test "the OpenTelemetry SDK and API are plain Hex requirements" do
    deps = Mix.Project.config()[:deps]

    assert {:opentelemetry_api, "~> 1.5"} in deps
    assert {:opentelemetry, "~> 1.5"} in deps
  end
end
