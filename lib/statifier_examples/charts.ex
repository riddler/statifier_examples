defmodule StatifierExamples.Charts do
  @moduledoc """
  Shared host plumbing for the `statifier_blocks` editor: the palette this
  app hands the editor, the icon lookup, the theme tokens, and the fixture
  documents.

  This module is the seam the two example domains meet in. It is deliberately
  thin: `statifier_blocks` owns the document model, the block-type registry
  and the compiler, and this app owns only the choices a host makes. Bead
  `se-06z` builds the editor host page on top of it, and `se-rrd` / `se-5de`
  merge their domain types into `palette/0`.
  """

  alias StatifierBlocks.Palette

  @themes [:light, :dark, :brand]

  @doc """
  The palette the editor is given.

  Today this is the `core.*` structural vocabulary `statifier_blocks` ships
  and nothing else; `se-rrd` and `se-5de` merge `StatifierExamples.CardAuth`
  and `StatifierExamples.Signup` block types into it.
  """
  @spec palette() :: Palette.t()
  def palette, do: Palette.core()

  @doc """
  The theme tokens the host page offers in its THEME control.
  """
  @spec themes() :: [atom()]
  def themes, do: @themes

  @doc """
  Resolves a block type or control name to an icon name.

  A seam: `se-06z` decides the icon set and the naming. Until then every name
  resolves to `nil`, which callers must render as "no icon" rather than as an
  error.
  """
  @spec icon(String.t() | atom()) :: String.t() | nil
  def icon(name) when is_binary(name) or is_atom(name), do: nil

  @doc """
  The example block documents this app hosts, newest-listed first.

  Empty until `se-rrd` and `se-5de` land their fixture documents; `se-06z`
  reads this to populate the DOCUMENT switcher and the index page.
  """
  @spec fixtures() :: list()
  def fixtures, do: []
end
