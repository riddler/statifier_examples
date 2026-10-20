defmodule StatifierExamples.ScreenEditor.BooleanQuestion do
  @moduledoc """
  `myapp.screens.boolean_question`: a lone checkbox or toggle submitting
  true or false - "I agree to the library's lending rules". `required`
  asks for true.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Node.common_fields() ++
      [
        Node.field("label", :string, "Label", true, ""),
        Node.field("required", :boolean, "Required", false, false)
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Node.validate(
      config,
      Node.present(config, "label", "a question needs the label a patron is asked")
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Yes or no question",
      group: "Screens",
      description: "A checkbox or toggle answered true or false.",
      icon: "check-circle",
      keywords: ["question", "checkbox", "toggle", "agree", "boolean"],
      order: 6
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_leaf(context)
end
