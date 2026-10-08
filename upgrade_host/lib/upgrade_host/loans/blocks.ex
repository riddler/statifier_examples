defmodule UpgradeHost.Loans.Blocks do
  @moduledoc """
  The host's own palette: the `core.*` vocabulary with three block types
  of the host's on top of it.

    * `myapp.until_returned` - `UpgradeHost.Loans.Blocks.UntilReturned`,
      a `StatifierBlocks.BlockType` written directly.
    * `myapp.assess_fine` - `UpgradeHost.Loans.Blocks.AssessFine`, a step
      declared through `StatifierBlocks.InvokeStep`.
    * `myapp.notify_patron` - `UpgradeHost.Loans.Blocks.NotifyPatron`, the
      same.

  The palette is built the way a host merges its entries into the core
  vocabulary: the types and recipes of `StatifierBlocks.Palette.core/0`,
  with the host's types merged over them, through
  `StatifierBlocks.Palette.new/2`. Nothing here mounts an editor; the
  palette is what the document is checked against and compiled with.
  """

  alias StatifierBlocks.{Block, BlockType, Emission, InvokeStep, Palette}
  alias UpgradeHost.Loans.Blocks.{AssessFine, NotifyPatron, UntilReturned}

  @types %{
    "myapp.until_returned" => UntilReturned,
    "myapp.assess_fine" => AssessFine,
    "myapp.notify_patron" => NotifyPatron
  }

  @doc "The host's palette: the core vocabulary and the host's three types."
  @spec palette() :: Palette.t()
  def palette do
    %Palette{types: core_types, recipes: core_recipes} = Palette.core()
    Palette.new(Map.merge(core_types, @types), recipes: core_recipes)
  end

  @doc "The host's own block types, by type name."
  @spec types() :: %{String.t() => module()}
  def types, do: @types

  @doc """
  A `<param>` named `name` that reads the datamodel root the block's
  `config_key` field holds, or the field's declared default when the
  block stores none. The expression is attributed to the field, so a
  finding inside it lands on the author's value.
  """
  @spec param(Block.t(), String.t(), String.t()) :: Emission.t()
  def param(%Block{config: config}, name, config_key) do
    "param"
    |> Emission.element([{"expr", Map.get(config, config_key, name)}, {"name", name}])
    |> Emission.attribute_from_config("expr", config_key)
  end

  @doc """
  Refuses a stored `key` that is not a bare datamodel root, and passes an
  absent one, which reads the field's default.
  """
  @spec check_root([BlockType.finding()], Block.config(), String.t()) :: [BlockType.finding()]
  def check_root(findings, config, key) when is_map_key(config, key),
    do:
      InvokeStep.check_identifier(findings, config, key, "must be a datamodel root, like #{key}")

  def check_root(findings, _config, _key), do: findings
end
