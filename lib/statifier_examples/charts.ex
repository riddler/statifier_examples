defmodule StatifierExamples.Charts do
  @moduledoc """
  Shared host plumbing for the `statifier_blocks` editor: the palette this
  app hands the editor, the icon lookup, the theme tokens, and the fixture
  documents.

  This module is the seam the two example domains meet in. It is
  deliberately thin: `statifier_blocks` owns the document model, the
  block-type registry and the compiler, and this app owns only the choices
  a host makes. Bead `se-06z` builds the editor host page on top of it.

  ## It is also this app's invoke registration

  Two registries meet here, and they are still two. A block type **names**
  an invoke type and `invoke_types/0` is the union of the names; a handler
  **runs** one, and `Statifier.Session`'s `:invoke_handlers` is a
  `%{type => module}` map of the modules. This module is the join.

  Two kinds of handler are joined, and they are written by two different
  packages rather than by this app. The three domain modules are plain
  `Statifier.Invoke.SyncHandler` implementations - `invoke_types/0` and
  `handle/3`, no lifecycle of their own - and the engine wraps them in the
  `Statifier.Invoke.Handler` every host would otherwise write by hand,
  which this app holds as `StatifierExamples.Charts.SyncAdapter`
  (se-4dt.2; that module says why the `use` lives there and not here).
  `statifier_blocks:subchart` is the other kind: a full handler with a
  lifecycle, written once in `statifier_blocks` and given this app's two
  callbacks by `StatifierExamples.Charts.Subchart` (se-4dt.4).

  `invoke_types/0` and `invoke_handlers/0` below are the union of the two,
  built one from the other so the set a document is linted against and the
  set a session will answer still cannot come apart. Registering the
  subchart handler is what retired this app's standing
  `no handler registered for invoke type "statifier_blocks:subchart"`
  warning on `signup_invitations`.
  """

  alias StatifierBlocks.Palette
  alias StatifierBlocks.Runtime
  alias StatifierExamples.{CardAuth, Signup}
  alias StatifierExamples.Charts.{Fixture, Icons, Messaging, Subchart, SyncAdapter}

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
  Every `<invoke type>` this app answers, sorted - the list a document is
  linted against as `:known_invoke_types`.

  The sync adapter's own union with the one type
  `StatifierExamples.Charts.Subchart` serves. Two sources because the two
  handlers are two kinds; one answer because a document is linted against
  one set.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: Enum.sort([Runtime.Subchart.invoke_type() | SyncAdapter.invoke_types()])

  @doc """
  The `%{invoke type => module}` map a `Statifier.Session` is started with
  (st-ADR-0051).

  Built from the same two sources as `invoke_types/0`, and the keys are
  exactly its answer - which
  `StatifierExamples.Charts.InvokeAdapterTest` asserts, because a set the
  compiler lints against that a session cannot answer is the failure this
  join exists to prevent.
  """
  @spec invoke_handlers() :: %{String.t() => module()}
  def invoke_handlers do
    Map.merge(SyncAdapter.invoke_handlers(), Runtime.Subchart.handlers(Subchart))
  end

  @doc """
  The `Statifier.Invoke.SyncHandler` modules the adapter is generated
  over, in dispatch order.

  The subchart handler is deliberately not in it: it is not a sync call
  and `dispatch/3` cannot perform one. See that function on what the
  durable driver does with a subchart.
  """
  @spec sync_handlers() :: [module()]
  def sync_handlers, do: SyncAdapter.sync_handlers()

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

  It is an `Enum.find` over `sync_handlers/0` rather than a call
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

  ## The subchart type is refused here by name

  `statifier_blocks:subchart` is registered by this app and is **not** a
  sync call: starting a child chart is a `{:start_child, _, _}`
  instruction, which `Statifier.Session` executes and
  `StatifierPersistence.Driver` has no executor for. A durable run that
  reaches one is therefore refused, and it is refused as
  `{:error, {:durable_subchart_unsupported, type}}` rather than falling
  through to `:unknown_invoke_type` - which would be untrue in the one way
  that matters to a reader of the feed, since the type *is* registered and
  a `Statifier.Session` answers it. Durable subcharts are campaign-023
  ruling R-e's follow-up.
  """
  @spec dispatch(String.t(), map(), call_context()) ::
          {:ok, map()}
          | {:error,
             {:unknown_invoke_type, String.t()} | {:durable_subchart_unsupported, String.t()}}
  def dispatch(type, params, context \\ %{}) when is_binary(type) and is_map(params) do
    if type == Runtime.Subchart.invoke_type() do
      {:error, {:durable_subchart_unsupported, type}}
    else
      case Enum.find(sync_handlers(), &(type in &1.invoke_types())) do
        nil -> {:error, {:unknown_invoke_type, type}}
        module -> module.handle(type, params, context)
      end
    end
  end

  @spec registrations() :: [Palette.registration()]
  defp registrations do
    [CardAuth.block_types(), Signup.block_types(), Messaging.block_types()]
    |> Enum.flat_map(&Enum.to_list/1)
    |> Enum.sort()
  end
end
