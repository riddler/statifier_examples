defmodule StatifierExamples.ScreenEditor.Text do
  @moduledoc """
  `myapp.screens.text`: a block of prose, its `text` a template that may
  read a response back - "Welcome, {{ responses.first_name }}."
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config),
    do: Element.common_fields() ++ [Element.field("text", :string, "Text", true, "")]

  @impl StatifierBlocks.BlockType
  def validate_config(config),
    do: Element.validate(config, Element.present(config, "text", "a text element needs its text"))

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Text",
      group: "Screens",
      description: "A block of prose.",
      icon: "document-text",
      keywords: ["text", "copy", "paragraph"],
      order: 3
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)
end
