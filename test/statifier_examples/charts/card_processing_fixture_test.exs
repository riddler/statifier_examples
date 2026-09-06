defmodule StatifierExamples.Charts.CardProcessingFixtureTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Compiler
  alias StatifierExamples.Charts

  setup do
    {:ok, fixture} = Charts.fixture("card_processing")

    %{document: fixture.document, datamodel: fixture.datamodel}
  end

  # The whole document against the palette the app actually ships, in one
  # pass. Until se-bv9 this took two: `myapp.legacy_check` was deliberately
  # unregistered, the compiler reports findings from the first failing stage
  # only, and so every stage after resolution could only be reached through a
  # stand-in palette the suite kept for the purpose. The shipped palette
  # resolves every type the document names now, so the shipped bytes are
  # clean under the shipped registry - which is the condition on a finding in
  # this document being one an author produced.
  #
  # Sabotage: dropped "myapp.legacy_check" from CardAuth.block_types(); the
  # compile came back {:error, [unknown_block_type]} and this went red.
  # Reverted from a backup copy.
  test "the shipped document compiles clean against the shipped palette",
       %{document: document, datamodel: datamodel} do
    assert {:ok, compiled} =
             Compiler.compile(document, Charts.palette(),
               known_invoke_types: Charts.invoke_types(),
               datamodel: datamodel
             )

    assert compiled.warnings == []
    assert compiled.record.document_id == "bdoc_cp_demo"
    assert compiled.record.revision == 43
  end

  # Sabotage: dropped the core.send block the timeout port added; this went
  # red, then reverted.
  test "the proposed core.timeout block ported onto the shipped clock pair",
       %{document: document} do
    types = block_types(document)

    refute "core.timeout" in types
    assert "core.send" in types

    assert %{"event" => "card.authz_timed_out", "delay" => "15m"} =
             config(document, "blk_cp_authz_deadline")

    assert %{"event" => "card.authz_timed_out", "outcome" => "abandon"} =
             config(document, "blk_cp_authz_timeout")
  end

  # Sabotage: left blk_cp_authorize's params as the spike's map; this went red,
  # then reverted.
  test "core.invoke's params arrive in the shipped one-per-line spelling",
       %{document: document} do
    assert %{"params" => params} = config(document, "blk_cp_authorize")

    assert params == "amount=amount_cents\ncurrency=currency\ncustomer=customer.id"
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
