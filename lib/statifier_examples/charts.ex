defmodule StatifierExamples.Charts do
  @moduledoc """
  Shared host plumbing for the `statifier_blocks` editor: the palette this
  app hands the editor, the icon lookup, the theme tokens, and the fixture
  documents.

  This module is the seam the two example domains meet in. It is
  deliberately thin: `statifier_blocks` owns the document model, the
  block-type registry and the compiler, and this app owns only the choices
  a host makes. Bead `se-06z` builds the editor host page on top of it.
  """

  alias StatifierBlocks.Palette
  alias StatifierExamples.{CardAuth, Signup}
  alias StatifierExamples.Charts.{Fixture, Messaging}

  @themes [:light, :dark, :brand]

  @doc """
  The palette the editor is given: `statifier_blocks`' `core.*` structural
  vocabulary with this app's own types on top.

  A value, built here and handed in explicitly - never a global registry.
  The registrations are ordered and later ones win, so a domain that
  deliberately swapped in its own `core.wait` would say so by writing it
  after `core: true`. None does today, and every name this app adds is in
  the `myapp.*` namespace: registering a `core.*` name here would take a
  decision that belongs to `statifier_blocks`, not to a host.
  """
  @spec palette() :: Palette.t()
  def palette do
    Palette.from_modules(registrations(), core: true)
  end

  @doc """
  The theme tokens the host page offers in its THEME control.
  """
  @spec themes() :: [atom()]
  def themes, do: @themes

  @doc """
  Resolves a block type or control name to an icon name.

  A seam: `se-06z` decides the icon set and the naming. Block types carry
  their own `icon` in `palette_entry/0` - heroicon outline names, per
  ADR-0005 decision 10k - so this answers only for the names that are not
  a block type's, and until `se-06z` lands every name resolves to `nil`,
  which callers must render as "no icon" rather than as an error.
  """
  @spec icon(String.t() | atom()) :: String.t() | nil
  def icon(name) when is_binary(name) or is_atom(name), do: nil

  @doc """
  The example block documents this app hosts, in the order the DOCUMENT
  switcher lists them.

  See `StatifierExamples.Charts.Fixture` for the entry shape and for why
  they are decoded at compile time.
  """
  @spec fixtures() :: [Fixture.t()]
  def fixtures, do: CardAuth.fixtures() ++ Signup.fixtures()

  @doc """
  The fixture stored under `key`, or `:error`.

  `:error` rather than a raise: `key` arrives from a query string, so a
  name nobody registered is an ordinary answer the host page renders,
  not an exception.
  """
  @spec fixture(String.t()) :: {:ok, Fixture.t()} | :error
  def fixture(key) when is_binary(key) do
    case Enum.find(fixtures(), &(&1.key == key)) do
      nil -> :error
      fixture -> {:ok, fixture}
    end
  end

  @doc """
  Every invoke type this app registers a handler for, sorted.

  The list a host hands `StatifierBlocks.Compiler.compile/3` as
  `:known_invoke_types`, which is what turns "this document names a handler
  nobody registered" from a runtime surprise into a compile-time warning.

  It is the union of both domains' handlers and the shared messaging one -
  the deployment half of ADR-0002's two-registry seam, assembled where the
  palette is, because a document is compiled against both at once and this
  is the one place that holds them together.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types do
    Enum.sort(
      CardAuth.Handlers.invoke_types() ++
        Messaging.Handlers.invoke_types() ++
        Map.keys(Signup.Handlers.handlers())
    )
  end

  @spec registrations() :: [Palette.registration()]
  defp registrations do
    [CardAuth.block_types(), Signup.block_types(), Messaging.block_types()]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.sort()
  end
end
