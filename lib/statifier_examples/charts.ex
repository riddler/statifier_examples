defmodule StatifierExamples.Charts do
  @moduledoc """
  Shared host plumbing for the `statifier_blocks` editor: the palette this
  app hands the editor, the icon lookup, the theme tokens, and the fixture
  documents.

  This module is the seam the two example domains meet in. It is
  deliberately thin: `statifier_blocks` owns the document model, the
  block-type registry and the compiler, and this app owns only the choices
  a host makes. Bead `se-06z` builds the editor host page on top of it.

  ## It is also this app's invoke adapter

  Two registries meet here, and they are still two. A block type **names**
  an invoke type and `invoke_types/0` is the union of the names; a handler
  **runs** one, and `Statifier.Session`'s `:invoke_handlers` is a
  `%{type => module}` map of the modules. This module is the join, and it
  is the join by `use`-ing `Statifier.Invoke.SyncHandler.Adapter` over the
  three domain handler modules: that macro supplies the four
  `Statifier.Invoke.Handler` callbacks and both derived registrations -
  `invoke_types/0` for the compiler's `:known_invoke_types` and
  `invoke_handlers/0` for the session - from the one handler list, so the
  set a document is linted against and the set a session will answer
  cannot come apart.

  The app used to write that adapter itself, as
  `StatifierExamples.Charts.InvokeHandler`. The engine writes it now, the
  same way for every host, and the app's three domain modules are plain
  `Statifier.Invoke.SyncHandler` implementations - `invoke_types/0` and
  `handle/3` - with no lifecycle of their own (se-4dt.2).
  """

  alias Statifier.Invoke.SyncHandler.Adapter
  alias StatifierBlocks.Palette
  alias StatifierExamples.{CardAuth, Signup}
  alias StatifierExamples.Charts.{Fixture, Icons, Messaging}

  # The three domain handler modules, named once. `invoke_types/0`,
  # `invoke_handlers/0` and the `Statifier.Invoke.Handler` callbacks are all
  # generated over this list, and `dispatch/3` reads it back as
  # `sync_handlers/0`. A fourth domain's module joins here and nowhere else.
  use Adapter, handlers: [CardAuth.Handlers, Messaging.Handlers, Signup.Handlers]

  @themes [:light, :dark, :brand]

  @typedoc """
  What the driver of a call knows about the call that the chart does not.

  Two drivers reach the handlers, and they know different things.
  `Statifier.Session` drives through the adapter, which hands a handler the
  engine's own plan context - `session_id` and the two registrations, and
  no run, because a session has none. `StatifierExamples.Charts.Durable`
  drives the pure core itself and calls `dispatch/3` directly, so it passes
  what it knows: the run id, because a handler that writes needs a stable
  key and the run is the only one this app has (see
  `StatifierExamples.Signup.Accounts`).

  A handler says which it needs by matching on it, and gets the clause for
  "not this driver" otherwise.
  """
  @type call_context :: Statifier.Invoke.SyncHandler.ctx() | %{optional(:run_id) => String.t()}

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
  Runs one call, by routing `type` to whichever handler module registered
  it.

  The deployment half of ADR-0002's two-registry seam, read the running way
  round: `invoke_types/0` answers "what can this app be asked", and this
  answers "who answers it". A name no module registered is
  `{:error, {:unknown_invoke_type, type}}`, which is what the handler
  modules themselves answer for a name they do not hold - the same event,
  raised one level up, so a caller routes on one shape rather than two.

  This is the routing for the app's *other* driver.
  `Statifier.Session` never comes through here: the adapter's generated
  `perform/2` routes the call itself, through
  `Statifier.Invoke.SyncHandler.Adapter.dispatch/4`, and reports the answer
  to the session. `StatifierExamples.Charts.Durable` drives the pure core
  with no session to report to, so it routes through this function and
  feeds the resulting event back into its own step.

  It is a four-line `Enum.find` over `sync_handlers/0` rather than a call
  to that same `dispatch/4`, which the engine does make public for a host
  in exactly this position - because the engine types its fourth argument
  as the plan context a session hands a handler, and what this driver has
  to say about a call is a run id (see `t:call_context/0`). Handing it a
  context of that shape is a contract violation dialyzer reports, so the
  app routes over the same list rather than through the same function. The
  list is still the one place a handler module is named, which is what the
  uptake was for (se-4dt.2).

  `context` is what the *driver* knows and the chart does not; see
  `t:call_context/0`. It defaults to the empty map so a caller with nothing
  to say says nothing, rather than inventing a shape.
  """
  @spec dispatch(String.t(), map(), call_context()) ::
          {:ok, map()} | {:error, {:unknown_invoke_type, String.t()}}
  def dispatch(type, params, context \\ %{}) when is_binary(type) and is_map(params) do
    case Enum.find(sync_handlers(), &(type in &1.invoke_types())) do
      nil -> {:error, {:unknown_invoke_type, type}}
      module -> module.handle(type, params, context)
    end
  end

  @spec registrations() :: [Palette.registration()]
  defp registrations do
    [CardAuth.block_types(), Signup.block_types(), Messaging.block_types()]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.sort()
  end
end
