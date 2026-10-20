defmodule StatifierExamples.ScreenEditor.ChoiceQuestion do
  @moduledoc """
  `myapp.screens.choice_question`: a question a patron answers by choosing
  among `answer_options` - which library card they want, say, a standard
  card or a family card.

  `select` is required and fixes what a submission holds: `one` is one
  option value, `many` a list of them. `style` is an open hint to the
  renderer (radio or dropdown for one; checkboxes or list for many), and a
  renderer with no hint picks by the option count. `required` asks for a
  choice; `min_selections` and `max_selections` bound how many, and only a
  `many` question reads them.

  ## `answer_options`, one row per option

  The document holds the options as a list of `{value, label}` objects,
  and the editor's field types have no list of objects. So the field is a
  list of rows, each written `value=Label` - `standard=Standard card` -
  and split at its first `=`. That is unambiguous because a value is
  key-shaped and so never holds an `=`, while a label may hold anything.
  Each value is checked here as the document will check it: key-shaped,
  and unique within the question.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @selects [{"one", "One"}, {"many", "Many"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Node.common_fields() ++
      [
        Node.field("label", :string, "Label", true, ""),
        Node.field("select", {:select, @selects}, "Select", true, "one"),
        Node.field("answer_options", {:list, :string}, "Answer options", true, []),
        Node.field("style", :string, "Style", false, ""),
        Node.field("required", :boolean, "Required", false, false),
        Node.field("min_selections", :integer, "Min selections", false, nil),
        Node.field("max_selections", :integer, "Max selections", false, nil)
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    options = Map.get(config, "answer_options")

    Node.validate(
      config,
      Node.present(config, "label", "a question needs the label a patron is asked") ++
        option_findings(options) ++ selection_findings(config, options)
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Choice question",
      group: "Screens",
      description: "A question answered by choosing one option, or several.",
      icon: "list-bullet",
      keywords: ["question", "choice", "select", "options", "radio", "checkboxes"],
      order: 5
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_leaf(context)

  @doc """
  The `{value, label}` pairs `rows` hold, in order, or `:error` when a row
  is not `value=Label`.

      iex> StatifierExamples.ScreenEditor.ChoiceQuestion.answer_options(["standard=Standard card"])
      {:ok, [{"standard", "Standard card"}]}

      iex> StatifierExamples.ScreenEditor.ChoiceQuestion.answer_options(["standard"])
      :error
  """
  @spec answer_options([String.t()]) :: {:ok, [{String.t(), String.t()}]} | :error
  def answer_options(rows) when is_list(rows) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case row_pair(row) do
        {:ok, pair} -> {:cont, {:ok, [pair | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      :error -> :error
    end
  end

  defp row_pair(row) when is_binary(row) do
    case String.split(row, "=", parts: 2) do
      [value, label] when label != "" -> {:ok, {value, label}}
      _no_label -> :error
    end
  end

  defp row_pair(_row), do: :error

  defp option_findings(rows) when is_list(rows) and rows != [] do
    case answer_options(rows) do
      {:ok, pairs} -> value_findings(Enum.map(pairs, &elem(&1, 0)))
      :error -> [{"answer_options", "each option is written value=Label"}]
    end
  end

  defp option_findings(_none),
    do: [{"answer_options", "a choice question needs at least one option"}]

  defp value_findings(values) do
    cond do
      not Enum.all?(values, &Node.key?/1) ->
        [{"answer_options", "an option value is key-shaped, like a node key"}]

      Enum.uniq(values) != values ->
        [{"answer_options", "each option value is unique within the question"}]

      true ->
        []
    end
  end

  defp selection_findings(config, options) do
    min = Map.get(config, "min_selections")
    max = Map.get(config, "max_selections")

    if Map.get(config, "select") == "many",
      do: bound_findings(min, max, option_count(options)),
      else: one_findings(min, max)
  end

  defp one_findings(nil, nil), do: []

  defp one_findings(_min, _max),
    do: [{"min_selections", "min_selections and max_selections bound a select of many only"}]

  defp bound_findings(min, max, count) do
    if bound?(min) and bound?(max),
      do: order_findings(min, max, count),
      else: [{"min_selections", "a selection bound is a non-negative integer"}]
  end

  defp order_findings(min, max, count) do
    cond do
      above?(min, max) ->
        [{"min_selections", "min_selections is not above max_selections"}]

      above?(min, count) ->
        [{"min_selections", "min_selections is not above the number of options"}]

      above?(max, count) ->
        [{"max_selections", "max_selections is not above the number of options"}]

      true ->
        []
    end
  end

  defp above?(bound, limit), do: is_integer(bound) and is_integer(limit) and bound > limit

  defp bound?(nil), do: true
  defp bound?(value), do: is_integer(value) and value >= 0

  defp option_count(options) when is_list(options), do: length(options)
  defp option_count(_none), do: 0
end
