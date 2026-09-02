defmodule StatifierExamples.MixDepsTest do
  use ExUnit.Case, async: true

  # `STATIFIER_BLOCKS_PATH` swaps the editor dep for a path dep on a local
  # checkout, and that swap is never committed: the committed default arm is
  # what CI - which sets no env - resolves.
  #
  # That default arm is a Hex requirement on the 0.14 line, and 0.14.0 is
  # the floor: `StatifierBlocks.Runtime.DurableSubchart` - the handler that
  # answers `core.subchart` by starting the child as its own persisted run
  # - landed after 0.13.0, and se-6ag's durable subchart proof is written
  # against it. The 0.13 line carries only the in-memory
  # `StatifierBlocks.Runtime.Subchart`, whose `{:start_child, _, _}`
  # nothing but `Statifier.Session` executes. The sixth interim git pin
  # this arm carried (se-p22's pattern) is retired, and this test is what
  # says no git ref came back.
  #
  # `mix.exs` and `mix.lock` are checked against each other rather than
  # each against a hope: a `mix.exs` edit without the matching lock entry
  # resolves to whatever was already fetched, and the requirement alone
  # would pass against a tree still holding 0.13.0.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.13.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.14.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "with STATIFIER_BLOCKS_PATH unset the statifier_blocks dep is the Hex requirement" do
    refute System.get_env("STATIFIER_BLOCKS_PATH")

    deps = Mix.Project.config()[:deps]

    assert {:statifier_blocks, "~> 0.14"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_blocks": )))

    assert lock_line, "statifier_blocks has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_blocks, "0.14.)
    refute lock_line =~ ":git,"
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

  # The durable stepper. 0.3.0 was the floor two release lines back, as
  # the first release carrying ADR-0007's asynchronous invocation
  # seam - the dispatch fun's `:pending` arm and the `done_invocation/5` /
  # `failed_invocation/5` re-entry doors an answer arriving from an Oban job
  # comes back through (se-d74). On 0.2.0 every call is answered inside the
  # step that made it, so the asynchronous handler this app registers has no
  # seam to hang on. The interim git pin this arm carried before the release
  # is retired.
  #
  # It is held on the 0.5 line as of se-a5y, and 0.5.0 is REQUIRED rather
  # than tidy. 0.4.0 carries all of ADR-0008's durable subchart machinery
  # except the one piece a host has to have: sp-2yx widened
  # `StatifierPersistence.Driver.dispatch_context/0` to carry `:invoke`,
  # the whole effect being dispatched, without which a dispatch fun cannot
  # reach `src` and `StatifierBlocks.Runtime.DurableSubchart` raises rather
  # than guess. sp-i21 then landed ADR-0009's storage-phase telemetry, and
  # `[:statifier_persistence, :run, :step, :start | :stop]` is the span
  # every durable macrostep nests inside and the one the capstone's trace
  # graph is built out of. Both are in 0.5.0 and neither is in 0.4.0.
  #
  # 0.4.0 was also breaking for a storage adapter that encodes
  # `run_status/0` by an exhaustive match, since it gains a fourth terminal
  # value `:cancelled`. `StatifierExamples.Persistence` delegates every
  # status-bearing callback to the package's own Ecto adapter and matches no
  # status itself, so it rides the library's encoding.
  #
  # The two interim git pins this arm carried across campaign 026 are
  # retired, and the `refute` below is what says neither came back.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.4.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.5.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the statifier_persistence dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_persistence, "~> 0.5"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_persistence": )))

    assert lock_line, "statifier_persistence has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_persistence, "0.5.)
    refute lock_line =~ ":git,"
  end

  # The durable-timer package. An earlier
  # requirement here was the patch-level `~> 0.3.1`, not `~> 0.3`, because
  # 0.3.0's cancellation query matches the delivering job itself: the
  # wizard's reminder job cancels its own delivery mid-flight and the live
  # reminder never arrives (se-p22). `~> 0.4` cannot resolve back to 0.3.0
  # at all, so the guarantee that bought the patch-level spelling is kept by
  # the major-line move and the spelling is no longer needed.
  #
  # The lock assertion is what ties the requirement to the resolved Hex
  # release; without it the membership check alone would pass against a
  # tree still holding an older one.
  #
  # It is held on the 0.5 line as of se-a5y, and that floor is REQUIRED
  # too: sob-43q landed ADR-0006's eleven telemetry events after 0.4.0,
  # and two of them are edges the capstone's trace graph asserts -
  # `[:statifier_oban, :timer, :scheduled]` and `[..., :timer, :fired]`.
  # On 0.4.0 a timer arms and fires and the graph has no edge across the
  # gap. The interim git pin this arm carried for se-opg is retired, and
  # the `refute` below is what says it did not come back.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.4.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.5.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the statifier_oban dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:statifier_oban, "~> 0.5"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "statifier_oban": )))

    assert lock_line, "statifier_oban has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :statifier_oban, "0.5.)
    refute lock_line =~ ":git,"
  end

  # The OTel bridge, which this app had no dependency on before se-opg -
  # nothing here produced a trace, so there was nothing to bridge.
  #
  # Held on the 0.3 line, with 0.3.0 as the floor: the two SIBLING setup
  # calls the capstone needs, `OpentelemetryStatifier.Persistence.setup/1`
  # and `OpentelemetryStatifier.Oban.setup/1`, landed after 0.2.0. On
  # 0.2.0 only the interpreter half exists, which in a durable run bridges
  # nothing at all. The interim git pin this arm was introduced on for
  # se-opg is retired, and the `refute` below is what says so.
  #
  # Sabotage: pointed the LOCK assertion at the real-but-wrong previous
  # release line (`"0.2.`) and left `mix.lock` alone; it went red
  # reporting the resolved 0.3.0 entry against the mutated expectation.
  # Reverted from a backup copy.
  test "the opentelemetry_statifier dep is the Hex requirement" do
    deps = Mix.Project.config()[:deps]

    assert {:opentelemetry_statifier, "~> 0.3"} in deps

    lock_line =
      "mix.lock"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find(&String.starts_with?(&1, ~s(  "opentelemetry_statifier": )))

    assert lock_line, "opentelemetry_statifier has no mix.lock entry"
    assert lock_line =~ ~s({:hex, :opentelemetry_statifier, "0.3.)
    refute lock_line =~ ":git,"
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
