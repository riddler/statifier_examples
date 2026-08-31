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
  alias StatifierExamples.Charts.{Fixture, Icons, InvokeHandler, Messaging}

  @themes [:light, :dark, :brand]

  # The three handler modules, in one list because two functions read them:
  # `invoke_types/0` for the union of the names, `dispatch/2` for which
  # module answers one. A fourth domain's module joins here and nowhere
  # else.
  @handler_modules [CardAuth.Handlers, Messaging.Handlers, Signup.Handlers]

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
  Resolves a block type or control name to an icon name this app can render.

  The seam `se-06z` filled in. Block types carry their own `icon` in
  `palette_entry/0` - heroicon outline names, per ADR-0005 decision 10k - and
  this app carries the `heroicons` dependency the Phoenix generator installs,
  so the answer for a name the set has is the name itself.

  It answers a **name**, never markup: what turns a name into an `<svg>` is
  `StatifierExamplesWeb.Icons.icon/1`, the component the editor's `icon`
  assign takes. Keeping the two apart is what lets the resolution be asserted
  without a renderer, which is what the palette walk in
  `test/statifier_examples/charts_test.exs` does.

  A name the set does not have resolves to `nil`, which callers render as "no
  icon" rather than as an error - a block type naming a glyph nobody drew is
  a missing tile, not a broken page.
  """
  @spec icon(String.t() | atom()) :: String.t() | nil
  def icon(name) when is_atom(name), do: icon(Atom.to_string(name))

  def icon(name) when is_binary(name) do
    if Icons.known?(name), do: name, else: nil
  end

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

  All three handler modules answer `invoke_types/0`, so the union is one
  concatenation and not three spellings of "what can this module do": that
  is the point of the app having a single handler-module shape.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types do
    @handler_modules |> Enum.flat_map(& &1.invoke_types()) |> Enum.sort()
  end

  @doc """
  The `%{invoke type => module}` map a session is started with
  (st-ADR-0051's per-session registration).

  Every name points at `StatifierExamples.Charts.InvokeHandler`, the one
  adapter that implements `Statifier.Invoke.Handler` for this app and
  routes back through `dispatch/2`. Built from `invoke_types/0` rather than
  written out, so registering a new handler name is one line in one handler
  module and nothing here - and so the set the compiler lints against and
  the set a session will actually answer cannot come apart.
  """
  @spec invoke_handlers() :: %{String.t() => module()}
  def invoke_handlers do
    Map.new(invoke_types(), &{&1, InvokeHandler})
  end

  @doc """
  Runs one call, by routing `type` to whichever handler module registered
  it.

  The deployment half of ADR-0002's two-registry seam, read the running way
  round: `invoke_types/0` answers "what can this app be asked", and this
  answers "who answers it". A name no module registered is
  `{:error, {:unknown_invoke_type, type}}`, which is what the handler
  modules themselves answer for a name they do not hold - the same event,
  raised one level up, so a caller routes on one shape rather than two.
  """
  @spec dispatch(String.t(), map()) ::
          {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def dispatch(type, params) when is_binary(type) and is_map(params) do
    case Enum.find(@handler_modules, &(type in &1.invoke_types())) do
      nil -> {:error, {:unknown_invoke_type, type}}
      module -> module.handle(type, params)
    end
  end

  @spec registrations() :: [Palette.registration()]
  defp registrations do
    [CardAuth.block_types(), Signup.block_types(), Messaging.block_types()]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.sort()
  end
end
