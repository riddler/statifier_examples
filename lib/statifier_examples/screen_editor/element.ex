defmodule StatifierExamples.ScreenEditor.Element do
  @moduledoc """
  What every block type in the screen-element palette shares: the two
  fields every element of a screen document carries, the checks on them,
  and the chart an element compiles to.

  ## The two common fields

  `key` names the element, and it is required and key-shaped - a lowercase
  letter, then lowercase letters, digits and underscores - because a
  question's key is where its response lands (`responses.<key>`) and a
  condition reads it back by that name. `condition` is optional, an
  expression over `responses` and `context` that decides whether the
  element is shown at all. Both are spelled as the screen document spells
  them, so the walk from a block document to a screen document copies a
  field rather than renaming it.

  ## What an element compiles to

  The blocks editor compiles every document it holds for its findings pane,
  and a screen document is not a chart: nothing executes a screen's
  elements in order. So an element compiles to an inert state that is
  entered and done at once, and a container
  (`StatifierExamples.ScreenEditor.Screen` and
  `StatifierExamples.ScreenEditor.Variant`) compiles to its elements in
  document order. What the pane then reports is what an author can act on:
  a field a type refuses, a slot arity the document breaks. The chart
  itself is never run; the screen editor's profile mounts the editor with
  no run pane (`StatifierExamples.ScreenEditor.profile/0`).
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @key_shape ~r/\A[a-z][a-z0-9_]*\z/
  @check_code ~r/\Acheck(\.[a-z][a-z0-9_]*)+\z/

  @doc """
  The `key` and `condition` field declarations, in that order, ahead of a
  type's own fields.
  """
  @spec common_fields() :: [BlockType.field_decl()]
  def common_fields do
    [
      field("key", :string, "Key", true, ""),
      field("condition", :expression, "Show when", false, "")
    ]
  end

  @doc "A field declaration in the shape `config_schema/1` answers."
  @spec field(String.t(), BlockType.field_type(), String.t(), boolean(), Block.json()) ::
          BlockType.field_decl()
  def field(key, type, label, required?, default) do
    %{key: key, type: type, label: label, required?: required?, default: default}
  end

  @doc """
  Whether `value` is key-shaped: what an element key, an option value and
  an outcome name are held to.

      iex> StatifierExamples.ScreenEditor.Element.key?("card_type")
      true

      iex> StatifierExamples.ScreenEditor.Element.key?("Card type")
      false
  """
  @spec key?(term()) :: boolean()
  def key?(value), do: is_binary(value) and Regex.match?(@key_shape, value)

  @doc """
  The findings on the common fields, then `checks`' own, as
  `validate_config/1` answers them.

  `checks` is a list of `{field, message}` findings already worked out by
  the type, so one call answers `:ok` only when neither half found
  anything.
  """
  @spec validate(Block.config(), [BlockType.finding()]) :: :ok | {:error, [BlockType.finding()]}
  def validate(config, checks) do
    case key_findings(config) ++ checks do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @doc """
  A finding on `field` when the config's value there is not a non-blank
  string, for a field an element cannot be read without.
  """
  @spec present(Block.config(), String.t(), String.t()) :: [BlockType.finding()]
  def present(config, field, message) do
    case Map.get(config, field) do
      value when is_binary(value) -> if String.trim(value) == "", do: [{field, message}], else: []
      _absent -> [{field, message}]
    end
  end

  @doc """
  The `checks` field every question type declares after its own fields:
  conditions a patron's response has to satisfy, one row per check.

  The document holds `checks` as a list of objects - `condition`, `code`
  and `message` - and the editor's field types have no list of objects. So
  each row is written `code: condition => message`, split at its first `:`
  and then at the first ` => ` after it: `check.birth_date_in_future:
  trim(responses.birth_date)::date <= context.today::date => A date of
  birth cannot be in the future.` That is unambiguous for the code, which
  is `check.` and key-shaped segments and so never holds a `:`, and for a
  condition outside its string literals, where ` => ` is no operator; a
  condition whose string literal holds ` => ` cannot be written this way.
  """
  @spec checks_field() :: BlockType.field_decl()
  def checks_field, do: field("checks", {:list, :string}, "Checks", false, [])

  @doc """
  The check objects `rows` hold, in order, or `:error` when a row is not
  `code: condition => message` with a code in the `check.` shape.

      iex> StatifierExamples.ScreenEditor.Element.checks(["check.adult: responses.age >= 18 => You must be 18."])
      {:ok, [%{"code" => "check.adult", "condition" => "responses.age >= 18", "message" => "You must be 18."}]}

      iex> StatifierExamples.ScreenEditor.Element.checks(["adult: responses.age >= 18 => You must be 18."])
      :error
  """
  @spec checks([String.t()]) :: {:ok, [%{String.t() => String.t()}]} | :error
  def checks(rows) when is_list(rows) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      case check_row(row) do
        {:ok, check} -> {:cont, {:ok, [check | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, checks} -> {:ok, Enum.reverse(checks)}
      :error -> :error
    end
  end

  @doc """
  The findings on a question's `checks` rows: each row readable, and each
  code used once on the question, as the document will hold them.
  """
  @spec check_findings(Block.config()) :: [BlockType.finding()]
  def check_findings(config) do
    case Map.get(config, "checks") do
      blank when blank in [nil, []] ->
        []

      rows when is_list(rows) ->
        case checks(rows) do
          {:ok, checks} -> unique_code_findings(Enum.map(checks, & &1["code"]))
          :error -> [{"checks", "each check is written check.<name>: condition => message"}]
        end

      _other ->
        [{"checks", "each check is written check.<name>: condition => message"}]
    end
  end

  defp unique_code_findings(codes) do
    if Enum.uniq(codes) == codes,
      do: [],
      else: [{"checks", "each check's code is used once on the question"}]
  end

  defp check_row(row) when is_binary(row) do
    with [code, rest] <- String.split(row, ":", parts: 2),
         code = String.trim(code),
         true <- Regex.match?(@check_code, code),
         [condition, message] <- String.split(rest, " => ", parts: 2),
         condition = String.trim(condition),
         message = String.trim(message),
         true <- condition != "" and message != "" do
      {:ok, %{"condition" => condition, "code" => code, "message" => message}}
    else
      _not_a_check -> :error
    end
  end

  defp check_row(_row), do: :error

  @doc "The inert state a leaf element compiles to: entered, and done at once."
  @spec emit_leaf(Context.t()) :: {:ok, StatifierBlocks.Emission.t()}
  def emit_leaf(context) do
    done = Context.done_id(context)
    {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
  end

  @doc "A container's elements, in document order."
  @spec emit_elements(Context.t()) :: {:ok, StatifierBlocks.Emission.t()}
  def emit_elements(context), do: Emit.ordered(context, Context.children(context, "elements"))

  @spec key_findings(Block.config()) :: [BlockType.finding()]
  defp key_findings(config) do
    if key?(Map.get(config, "key")) do
      []
    else
      [
        {"key",
         "an element key starts with a lowercase letter and holds only lowercase letters, " <>
           "digits and underscores"}
      ]
    end
  end
end
