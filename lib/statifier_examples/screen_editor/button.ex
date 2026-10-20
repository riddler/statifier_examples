defmodule StatifierExamples.ScreenEditor.Button do
  @moduledoc """
  `myapp.screens.button`: a control a patron presses, and the `outcome`
  the press raises - `details_submitted` on a Continue button, say.

  `label` and `outcome` are required. `style` is a renderer's name for how
  the button looks and is never required: a button with none is drawn the
  renderer's default way. `validates` says whether the press checks the
  screen first, and a Back button turns it off.

  ## `writes`, one row per write

  The document holds `writes` as a map from a response path to a constant,
  `{"responses.card": ["const", "family"]}`, and the editor's field types
  have no map. So the field is a list of rows, each written
  `responses.<path>=value` - `responses.card=family` - and split at its
  first `=`. The value is a string constant; a path that holds an `=`
  cannot be written this way.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @response_path ~r/\Aresponses\.[^.\s][^\s]*\z/

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Node.common_fields() ++
      [
        Node.field("label", :string, "Label", true, ""),
        Node.field("outcome", :string, "Outcome", true, ""),
        Node.field("writes", {:list, :string}, "Writes", false, []),
        Node.field("style", :string, "Style", false, ""),
        Node.field("validates", :boolean, "Validates the screen", false, true)
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Node.validate(
      config,
      Node.present(config, "label", "a button needs its label") ++
        outcome_findings(Map.get(config, "outcome")) ++
        writes_findings(Map.get(config, "writes"))
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Button",
      group: "Screens",
      description: "A control a patron presses, and the outcome it raises.",
      icon: "cursor-arrow-rays",
      keywords: ["button", "submit", "continue", "back", "outcome"],
      order: 7
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_leaf(context)

  defp outcome_findings(outcome) do
    if Node.key?(outcome),
      do: [],
      else: [{"outcome", "an outcome is a name like a node key, such as details_submitted"}]
  end

  defp writes_findings(rows) when is_list(rows) do
    if Enum.all?(rows, &write_row?/1),
      do: [],
      else: [{"writes", "each write is written responses.<path>=value"}]
  end

  defp writes_findings(nil), do: []
  defp writes_findings(_other), do: [{"writes", "each write is written responses.<path>=value"}]

  defp write_row?(row) when is_binary(row) do
    case String.split(row, "=", parts: 2) do
      [path, _value] -> Regex.match?(@response_path, path)
      _no_value -> false
    end
  end

  defp write_row?(_row), do: false
end
