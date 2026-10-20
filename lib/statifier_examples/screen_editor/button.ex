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
  first `=`, so a path that holds an `=` cannot be written this way. The
  value is read as JSON when it is JSON - `responses.guests=2` writes a
  number, `responses.branch_code="12"` the string `"12"` - and as the text
  itself when it is not, so `responses.card=family` writes the string
  `"family"` (`StatifierExamples.ScreenEditor.Walk.split_write/1`). Each
  path is written once: two rows writing one path are a finding here, and
  the walk refuses them rather than keeping only the last.
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
    cond do
      not Enum.all?(rows, &write_row?/1) ->
        [{"writes", "each write is written responses.<path>=value"}]

      duplicate_path?(rows) ->
        [{"writes", "each response path is written once"}]

      true ->
        []
    end
  end

  defp writes_findings(nil), do: []
  defp writes_findings(_other), do: [{"writes", "each write is written responses.<path>=value"}]

  defp write_row?(row) when is_binary(row) do
    case String.split(row, "=", parts: 2) do
      [path, _value] -> response_path?(path)
      _no_value -> false
    end
  end

  defp write_row?(_row), do: false

  defp duplicate_path?(rows) do
    paths = Enum.map(rows, &(&1 |> String.split("=", parts: 2) |> hd()))
    Enum.uniq(paths) != paths
  end

  @doc """
  Whether `path` addresses a response, `responses.<path>`: what the left
  side of a write row is held to.

      iex> StatifierExamples.ScreenEditor.Button.response_path?("responses.card")
      true

      iex> StatifierExamples.ScreenEditor.Button.response_path?("card")
      false
  """
  @spec response_path?(term()) :: boolean()
  def response_path?(path), do: is_binary(path) and Regex.match?(@response_path, path)
end
