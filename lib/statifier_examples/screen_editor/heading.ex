defmodule StatifierExamples.ScreenEditor.Heading do
  @moduledoc """
  `myapp.screens.heading`: a section title, its `level` from 1 to 6 and
  its `text` - "Register for a library card" at level 1, say.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Element.common_fields() ++
      [
        Element.field("level", :integer, "Level", true, 1),
        Element.field("text", :string, "Text", true, "")
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      level_findings(Map.get(config, "level")) ++
        Element.present(config, "text", "a heading needs its text")
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Heading",
      group: "Screens",
      description: "A section title.",
      icon: "h1",
      keywords: ["heading", "title"],
      order: 2
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)

  defp level_findings(level) when is_integer(level) and level in 1..6, do: []
  defp level_findings(_level), do: [{"level", "a heading level is an integer from 1 to 6"}]
end
