defmodule StatifierExamples.ScreenEditor.TextQuestion do
  @moduledoc """
  `myapp.screens.text_question`: a question a patron answers with a line of
  text - their first name, or the email the library writes to.

  `label` is what the patron is asked, `placeholder` the hint in the
  empty field and `help` a line of guidance shown beside it. `required`
  says an empty response will not do. `format` is one of the validation
  formats the screen document names, or blank for none; `pattern` is the
  expression the `pattern` format holds a response to, and `min` and
  `max` the bounds the `integer` and `number` formats hold one between. The bounds are written as text, a number or blank,
  because the editor's field types have no number that admits a fraction.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @formats [
    {"", "None"},
    {"email", "Email"},
    {"phone", "Phone"},
    {"pattern", "Pattern"},
    {"integer", "Integer"},
    {"number", "Number"}
  ]

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Element.common_fields() ++
      [
        Element.field("label", :string, "Label", true, ""),
        Element.field("placeholder", :string, "Placeholder", false, ""),
        Element.field("help", :string, "Help", false, ""),
        Element.field("required", :boolean, "Required", false, false),
        Element.field("format", {:select, @formats}, "Format", false, ""),
        Element.field("pattern", :string, "Pattern", false, ""),
        Element.field("min", :string, "Min", false, ""),
        Element.field("max", :string, "Max", false, "")
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      Element.present(config, "label", "a question needs the label a patron is asked") ++
        bound_findings(config, "min") ++ bound_findings(config, "max")
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Text question",
      group: "Screens",
      description: "A question answered with a line of text.",
      icon: "chat-bubble-left-ellipsis",
      keywords: ["question", "input", "field", "email"],
      order: 4
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)

  defp bound_findings(config, field) do
    case Map.get(config, field) do
      blank when blank in [nil, ""] -> []
      value when is_binary(value) -> if number?(value), do: [], else: [not_a_number(field)]
      _other -> [not_a_number(field)]
    end
  end

  defp number?(value), do: match?({_number, ""}, Float.parse(value))

  defp not_a_number(field), do: {field, "#{field} is a number, or blank for no bound"}
end
