defmodule StatifierExamples.Charts.FixtureHygieneTest do
  @moduledoc """
  The one rule about the shipped fixtures that is not about what they
  model: they carry no key nothing reads.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierExamples.Charts

  # `label` is a HOST convention, not a document one. A card is titled from a
  # declared `:string` field keyed "label" (`StatifierBlocks.ViewModel`'s
  # `title_override/2`, read by `title/1`), and no type in the `core.*`
  # vocabulary declares one - ADR-0002 amendment H5 makes that the intended
  # shape rather than a gap, because "Wait" is what a wait is called. So a
  # `config["label"]` on a `core.*` block titles nothing, is in no config
  # schema, and renders nowhere: it is dead data in a document a reader is
  # meant to learn the vocabulary from.
  #
  # This app's own types DO declare the field
  # (`StatifierExamples.Charts.Step.label_field/0`), so their labels are live
  # and this test is careful to leave them alone -
  # `StatifierExamples.Charts.StepLabelTest` counts the half this one refuses.
  #
  # Sabotage: put "label" => "Arm the authorization deadline" back on
  # blk_cp_authz_deadline in card_processing.json; this went red, then
  # reverted.
  test "no core.* block in any shipped fixture carries a config label" do
    offenders =
      for %{document: document} <- Charts.fixtures(),
          block <- blocks(document.root),
          String.starts_with?(block.type, "core."),
          Map.has_key?(block.config, "label"),
          do: block.id

    assert offenders == []
  end

  @spec blocks(Block.t()) :: [Block.t()]
  defp blocks(%Block{} = block) do
    children = block.slots |> Map.values() |> List.flatten() |> Enum.flat_map(&blocks/1)

    [block | children]
  end
end
