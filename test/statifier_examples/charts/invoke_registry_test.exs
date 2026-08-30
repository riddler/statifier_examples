defmodule StatifierExamples.Charts.InvokeRegistryTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.{Compiler, Palette}
  alias StatifierExamples.Charts
  alias StatifierExamples.Test.LegacyCheck

  # The two-registry seam, asserted over the whole shipped fixture set
  # rather than one document: a block type NAMES an invoke type and a
  # handler module RUNS one, and nothing in the type system connects the
  # two. What connects them is this test - it compiles every fixture with
  # `known_invoke_types: Charts.invoke_types()` and reads the compiler's own
  # lint, so a fixture that names a handler this app does not register
  # fails here instead of at runtime with `error.execution`.
  #
  # `myapp:*` and nothing else. `signup_invitations` also emits
  # `statifier_blocks:subchart`, which is the HOST's to register and which
  # this app deliberately does not: that warning is the fixture working as
  # documented, not a gap. Filtering on the namespace is what keeps this
  # test about the app's own registration.

  # Sabotage: dropped "myapp:receipt" from CardAuth.Handlers' @invoke_types;
  # this went red naming card_processing, then reverted (and took the
  # control below with it, which is the coupling working).
  test "every myapp invoke type the shipped fixtures name has a handler registered" do
    for fixture <- Charts.fixtures() do
      assert unregistered(fixture, Charts.invoke_types()) == [],
             "#{fixture.key} names a myapp handler this app does not register"
    end
  end

  # The check above passes trivially if the lint never runs - a wrong
  # option name, a compile that stops before the lint stage, a fixture list
  # that came back empty. This is the control: hold one registered type back
  # and the same walk has to report it, by block.
  #
  # Sabotage: made unregistered/2 answer [] unconditionally; this went red,
  # then reverted.
  test "the walk reports a type the registry is missing, by block" do
    known = Charts.invoke_types() -- ["myapp:signup"]

    found = Enum.flat_map(Charts.fixtures(), &unregistered(&1, known))

    assert {"myapp:signup", "blk_su_account"} in found
    assert Enum.all?(found, fn {type, _block_id} -> type == "myapp:signup" end)
  end

  # Sabotage: added "statifier_blocks:subchart" to Charts.invoke_types();
  # this went red, then reverted.
  test "the subchart handler is the host's to register and this app does not" do
    {:ok, invitations} = Charts.fixture("signup_invitations")

    refute "statifier_blocks:subchart" in Charts.invoke_types()

    assert {"statifier_blocks:subchart", _block_id} =
             invitations
             |> warnings(Charts.invoke_types())
             |> Enum.find(fn {type, _block_id} -> type == "statifier_blocks:subchart" end)
  end

  # Every `myapp:` type the compiler reports as unregistered, with the block
  # that emitted it.
  @spec unregistered(map(), [String.t()]) :: [{String.t(), String.t() | nil}]
  defp unregistered(fixture, known) do
    fixture
    |> warnings(known)
    |> Enum.filter(fn {type, _block_id} -> String.starts_with?(type, "myapp:") end)
  end

  @spec warnings(map(), [String.t()]) :: [{String.t(), String.t() | nil}]
  defp warnings(fixture, known) do
    assert {:ok, compiled} =
             Compiler.compile(fixture.document, palette(), known_invoke_types: known),
           "#{fixture.key} does not compile"

    for %{reason: {:no_registered_invoke_handler, type}} = finding <- compiled.warnings,
        do: {type, finding.block_id}
  end

  # `card_processing` leaves `myapp.legacy_check` unregistered on purpose, and
  # the compiler reports errors from the first failing stage only - so with
  # the shipped palette the unresolved block masks the invoke-type lint
  # entirely. The stand-in is what lets the lint be seen at all; it is the
  # same one `CardProcessingFixtureTest` uses, and it emits no invoke.
  @spec palette() :: Palette.t()
  defp palette do
    palette = Charts.palette()

    %{palette | types: Map.put(palette.types, "myapp.legacy_check", LegacyCheck)}
  end
end
