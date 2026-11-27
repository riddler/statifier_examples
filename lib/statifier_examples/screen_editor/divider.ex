defmodule StatifierExamples.ScreenEditor.Divider do
  @moduledoc """
  `myapp.screens.divider`: a rule between the elements before it and the
  elements after it - between a patron's contact details and the PIN they
  choose, say. It carries no field of its own, only the two every element
  carries (`StatifierExamples.ScreenEditor.Element`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config), do: Element.common_fields()

  @impl StatifierBlocks.BlockType
  def validate_config(config), do: Element.validate(config, [])

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Divider",
      group: "Screens",
      description: "A rule between one part of a screen and the next.",
      icon: "minus",
      keywords: ["divider", "rule", "separator", "section"],
      order: 11
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)
end
