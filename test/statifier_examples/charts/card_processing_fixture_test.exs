defmodule StatifierExamples.Charts.CardProcessingFixtureTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts
  alias StatifierExamples.Test.LegacyCheck

  setup do
    {:ok, fixture} = Charts.fixture("card_processing")

    %{document: fixture.document}
  end

  # Sabotage: registered myapp.legacy_check in CardAuth.block_types(); this
  # went red, then reverted.
  test "the fixture compiles with one finding, the deliberate unresolved type",
       %{document: document} do
    assert {:error, [finding]} = Compiler.compile(document, Charts.palette(), [])

    assert finding.severity == :error
    assert finding.block_id == "blk_cp_legacy"
    assert finding.reason == {:unknown_block_type, "myapp.legacy_check"}
  end

  # The compiler reports errors from the first failing stage only, so the
  # unresolved block above masks every stage after resolution. This is the
  # masked half: with a stand-in registered for that one type, the rest of the
  # document has to be clean on its own.
  #
  # Sabotage: put "myapp:not_a_handler" in blk_cp_intake's invoke_type; the
  # warning assertion went red, then reverted.
  test "with the one type stood in for, the rest of the document is clean",
       %{document: document} do
    assert {:ok, compiled} =
             Compiler.compile(document, stand_in_palette(),
               known_invoke_types: Charts.invoke_types()
             )

    assert compiled.warnings == []
    assert compiled.record.document_id == "bdoc_cp_demo"
    assert compiled.record.revision == 42
  end

  # Sabotage: dropped the core.send block the timeout port added; this went
  # red, then reverted.
  test "the proposed core.timeout block ported onto the shipped clock pair",
       %{document: document} do
    types = block_types(document)

    refute "core.timeout" in types
    assert "core.send" in types

    assert %{"event" => "card.authorization_timed_out", "delay" => "15m"} =
             config(document, "blk_cp_authz_deadline")

    assert %{"event" => "card.authorization_timed_out", "outcome" => "abandon"} =
             config(document, "blk_cp_authz_timeout")
  end

  # Sabotage: left blk_cp_authorize's params as the spike's map; this went red,
  # then reverted.
  test "core.invoke's params arrive in the shipped one-per-line spelling",
       %{document: document} do
    assert %{"params" => params} = config(document, "blk_cp_authorize")

    assert params == "amount=amount_cents\ncurrency=currency\ncustomer=customer.id"
  end

  @spec stand_in_palette() :: Palette.t()
  defp stand_in_palette do
    palette = Charts.palette()

    %{palette | types: Map.put(palette.types, "myapp.legacy_check", LegacyCheck)}
  end

  defp block_types(document), do: document.root |> blocks() |> Enum.map(& &1.type) |> Enum.uniq()

  defp config(document, id) do
    document.root
    |> blocks()
    |> Enum.find(&(&1.id == id))
    |> Map.fetch!(:config)
  end

  defp blocks(block) do
    [block | block.slots |> Map.values() |> List.flatten() |> Enum.flat_map(&blocks/1)]
  end
end
