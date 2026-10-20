defmodule StatifierExamples.ScreenEditor.Node do
  @moduledoc """
  What every block type in the screen-node palette shares: the two fields
  every node of a screen document carries, the checks on them, and the
  chart a node compiles to.

  ## The two common fields

  `key` names the node, and it is required and key-shaped - a lowercase
  letter, then lowercase letters, digits and underscores - because a
  question's key is where its response lands (`responses.<key>`) and a
  condition reads it back by that name. `condition` is optional, an
  expression over `responses` and `context` that decides whether the node
  is shown at all. Both are spelled as the screen document spells them, so
  the walk from a block document to a screen document copies a field
  rather than renaming it.

  ## What a node compiles to

  The blocks editor compiles every document it holds for its findings pane,
  and a screen document is not a chart: nothing executes a screen's nodes
  in order. So a node compiles to an inert state that is entered and done
  at once, and a container (`StatifierExamples.ScreenEditor.Screen` and
  `StatifierExamples.ScreenEditor.Variant`) compiles to its nodes in
  document order. What the pane then reports is what an author can act on:
  a field a type refuses, a slot arity the document breaks. The chart
  itself is never run; the screen-node profile mounts the editor with no
  run pane (`StatifierExamples.ScreenEditor.profile/0`).
  """

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit

  @key_shape ~r/\A[a-z][a-z0-9_]*\z/

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
  Whether `value` is key-shaped: what a node key, an option value and an
  outcome name are held to.

      iex> StatifierExamples.ScreenEditor.Node.key?("card_type")
      true

      iex> StatifierExamples.ScreenEditor.Node.key?("Card type")
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
  string, for a field a node cannot be read without.
  """
  @spec present(Block.config(), String.t(), String.t()) :: [BlockType.finding()]
  def present(config, field, message) do
    case Map.get(config, field) do
      value when is_binary(value) -> if String.trim(value) == "", do: [{field, message}], else: []
      _absent -> [{field, message}]
    end
  end

  @doc "The inert state a leaf node compiles to: entered, and done at once."
  @spec emit_leaf(Context.t()) :: {:ok, StatifierBlocks.Emission.t()}
  def emit_leaf(context) do
    done = Context.done_id(context)
    {:ok, Emit.state(context.state_id, done, [Emit.final(done)])}
  end

  @doc "A container's nodes, in document order."
  @spec emit_nodes(Context.t()) :: {:ok, StatifierBlocks.Emission.t()}
  def emit_nodes(context), do: Emit.ordered(context, Context.children(context, "nodes"))

  @spec key_findings(Block.config()) :: [BlockType.finding()]
  defp key_findings(config) do
    if key?(Map.get(config, "key")) do
      []
    else
      [
        {"key",
         "a node key starts with a lowercase letter and holds only lowercase letters, " <>
           "digits and underscores"}
      ]
    end
  end
end
