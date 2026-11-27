defmodule StatifierExamples.ScreenEditor.BooleanQuestion do
  @moduledoc """
  `myapp.screens.boolean_question`: a lone checkbox or toggle submitting
  true or false - "I agree to the library's lending rules". `required`
  asks for true, and `help` is a line of guidance shown beside it.
  `checks` are the question's own conditions, one row each
  (`StatifierExamples.ScreenEditor.Element.checks_field/0`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Element.common_fields() ++
      [
        Element.field("label", :string, "Label", true, ""),
        Element.field("help", :string, "Help", false, ""),
        Element.field("required", :boolean, "Required", false, false),
        Element.checks_field()
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      Element.present(config, "label", "a question needs the label a patron is asked") ++
        Element.check_findings(config)
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
  def emit(_block, context), do: Element.emit_leaf(context)
end
