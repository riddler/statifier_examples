defmodule StatifierExamples.ScreenEditor.Variant do
  @moduledoc """
  `myapp.screens.variant`: a node that shows one of the candidates in its
  `nodes` slot, the first whose condition holds - a notice for a patron who
  already holds a card ahead of the default welcome, say. The last
  candidate with no condition is the default.

  Its slot needs at least one candidate, because a variant with none has
  nothing to show. Its own fields are the two every node carries
  (`StatifierExamples.ScreenEditor.Node`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @impl StatifierBlocks.BlockType
  def slots(_config), do: [{"nodes", :at_least_one, "Candidates"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config), do: Node.common_fields()

  @impl StatifierBlocks.BlockType
  def validate_config(config), do: Node.validate(config, [])

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Variant",
      group: "Screens",
      description: "Shows the first candidate whose condition holds.",
      icon: "arrows-right-left",
      keywords: ["variant", "branch", "alternative", "condition"],
      order: 8
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_nodes(context)
end
