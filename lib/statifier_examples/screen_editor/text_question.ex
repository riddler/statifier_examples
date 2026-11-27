defmodule StatifierExamples.ScreenEditor.TextQuestion do
  @moduledoc """
  `myapp.screens.text_question`: a question a patron answers with a line of
  text - their first name, the email the library writes to, or their date
  of birth.

  `label` is what the patron is asked, `placeholder` the hint in the
  empty field and `help` a line of guidance shown beside it. `required`
  says an empty response will not do. `format` is one of the validation
  formats the screen document names, or blank for none: `email`, `phone`,
  `pattern`, the numeric `integer` and `number`, and the date and time
  formats `date`, `time` and `datetime`. The date and time formats are
  choices of this one field and not block types of their own, because the
  document spells them as a text question's `format`.

  `pattern` is the expression the `pattern` format holds a response to.
  `min` and `max` are the bounds a format reads: a number for `integer`
  and `number`, and a value in the format's own shape for `date`, `time`
  and `datetime` (`1900-01-01` for a date). They are written as text,
  because the editor's field types have no number that admits a fraction
  and no date; the walk turns a numeric bound back into a number and
  leaves a date or time bound as the text it is.

  `style` is a hint a renderer reads, offered as an open list
  (`StatifierExamples.ScreenEditor.field_candidates/0`): `multiline`, and
  `slider` and `stepper` for a numeric format. `step` is the increment a
  slider or a stepper moves by, written as text and walked to a number.
  `checks` are the question's own conditions, one row each
  (`StatifierExamples.ScreenEditor.Element.checks_field/0`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @formats [
    {"", "None"},
    {"email", "Email"},
    {"phone", "Phone"},
    {"pattern", "Pattern"},
    {"integer", "Integer"},
    {"number", "Number"},
    {"date", "Date"},
    {"time", "Time"},
    {"datetime", "Date and time"}
  ]

  @dated ["date", "time", "datetime"]

  @doc """
  The formats whose bounds are written in the format's own shape rather
  than as numbers.

      iex> StatifierExamples.ScreenEditor.TextQuestion.dated_formats()
      ["date", "time", "datetime"]
  """
  @spec dated_formats() :: [String.t()]
  def dated_formats, do: @dated

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
        Element.field("max", :string, "Max", false, ""),
        Element.field("style", :string, "Style", false, ""),
        Element.field("step", :string, "Step", false, ""),
        Element.checks_field()
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      Element.present(config, "label", "a question needs the label a patron is asked") ++
        bound_findings(config, "min") ++
        bound_findings(config, "max") ++
        step_findings(Map.get(config, "step")) ++
        Element.check_findings(config)
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Text question",
      group: "Screens",
      description: "A question answered with a line of text, a number or a date.",
      icon: "chat-bubble-left-ellipsis",
      keywords: ["question", "input", "field", "email", "date", "slider"],
      order: 4
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)

  defp bound_findings(config, field) do
    if Map.get(config, "format") in @dated,
      do: [],
      else:
        number_findings(
          Map.get(config, field),
          field,
          "#{field} is a number, or blank for no bound"
        )
  end

  defp step_findings(step),
    do: number_findings(step, "step", "step is a number, or blank for no step")

  defp number_findings(blank, _field, _message) when blank in [nil, ""], do: []

  defp number_findings(value, field, message) when is_binary(value),
    do: if(number?(value), do: [], else: [{field, message}])

  defp number_findings(_other, field, message), do: [{field, message}]

  defp number?(value), do: match?({_number, ""}, Float.parse(value))
end
