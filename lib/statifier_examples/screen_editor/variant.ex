defmodule StatifierExamples.ScreenEditor.Variant do
  @moduledoc """
  `myapp.screens.variant`: an element that shows one of the candidates in
  its `elements` slot, the first whose condition holds - a notice for a patron who
  already holds a card ahead of the default welcome, say. The last
  candidate with no condition is the default.

  Its slot needs at least one candidate, because a variant with none has
  nothing to show. Its own fields are the two every element carries
  (`StatifierExamples.ScreenEditor.Element`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def slots(_config), do: [{"elements", :at_least_one, "Candidates"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config), do: Element.common_fields()

  @impl StatifierBlocks.BlockType
  def validate_config(config), do: Element.validate(config, [])

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Variant",
      group: "Screens",
      description: "Shows the first candidate whose condition holds.",
      icon: "arrows-right-left",
      keywords: ["variant", "branch", "alternative", "condition"],
      order: 9
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_elements(context)
end
