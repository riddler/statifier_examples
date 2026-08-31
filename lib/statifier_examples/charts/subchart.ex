defmodule StatifierExamples.Charts.Subchart do
  @moduledoc """
  This app's `statifier_blocks:subchart` handler: the canonical one
  `StatifierBlocks.Runtime.Subchart` ships, with the two callbacks a host
  supplies - which document a `core.subchart`'s `chart` id names, and the
  palette a child is compiled against.

  `core.subchart` names a chart and never runs one (ADR-0002 decision 2's
  two-registry seam), so until se-4dt.4 this app registered no handler for
  the type at all and `signup_invitations` compiled with a standing
  `no handler registered for invoke type "statifier_blocks:subchart"`
  warning. The package writes that handler now, so what is left here is
  only the part that is genuinely a host's: a lookup over
  `StatifierExamples.Charts.fixtures/0`.

  ## The resolver is a document-id lookup, and that is the whole of it

  `src` carries the **document id** the author typed into `chart` and not
  a chart identity (`StatifierBlocks.Core.Subchart`'s "What `src` names"):
  a host resolves that stable authoring-time name to whichever chart it
  currently publishes for that document. This app publishes exactly the
  documents it ships in `priv/fixtures/`, so the resolution is a find over
  the fixture list by `document.id`, and a name nobody ships is `:error` -
  the handler's `unknown_document` refusal, one of campaign-023 ruling
  R-b's three.

  Documents are handed back **uncompiled**, which is the arm that lets the
  package compile them itself with `child_use: true` and with the invoke
  types the running session actually registered. `identities/1` below
  compiles the same document the same way for its own reasons, and says
  there why the two compiles have to agree.

  ## `{:cycle, _}` is unreachable for this host, and a test says so

  The fourth answer exists for hosts whose document graph is data. This
  app's is source: the shipped fixture list is fixed at build time and
  single-level, which `StatifierExamples.Charts.SubchartTest` asserts by
  walking it. A
  cycle within one document is refused earlier still, by
  `StatifierBlocks.Compiler.SelfReference`. So this module answers two of
  the four shapes, and grows the third the day a host document graph stops
  being a list in `StatifierExamples.Signup`.

  ## Single-level only, and why that is not a shortcut

  A child session is started by `Statifier.Session` with `invoked_by:`, a
  seeded datamodel and the parent's observer options - and **not** with
  the parent's `:invoke_handlers` (statifier-ex `Session.start_session/4`).
  So a child chart's own `<invoke>`s reach a session that has no handler
  registered for them, whether they are `myapp:*` calls or a nested
  `statifier_blocks:subchart`. That is filed upstream as **st-pvpz**; it is
  the engine's to fix and not this app's to work around, which is the
  posture `CLAUDE.md` requires of the reference embedder.

  What it means here: a parent that embeds a child runs the child's chart,
  and a child that needs its own handlers cannot finish inside it. The
  fixture `signup_onboarding` is written to that limit and says so.

  ## Durable runs are out of scope

  `{:start_child, _, _}` is executed by `Statifier.Session` and by nothing
  else: `StatifierPersistence.Driver` performs an `<invoke>` through this
  app's `dispatch:` fun, which routes sync handlers only. A durable
  subchart needs the child to be its own persisted run with the linkage
  recorded durably, which is campaign-023 ruling R-e's deliberate
  follow-up. What this app records durably today is the pin - see
  `identities/1`.
  """

  use StatifierBlocks.Runtime.Subchart

  alias Statifier.Invoke.Handler
  alias Statifier.Machine.Identity
  alias StatifierBlocks.{Block, Compiled, Compiler, Document, Palette}
  alias StatifierExamples.Charts

  @subchart_type "core.subchart"
  @chart_key "chart"

  @doc """
  The document `document_id` names, out of the shipped fixture list.

  `:error` for a name nothing ships, which the package refuses as
  `unknown_document` (campaign-023 ruling R-b).
  """
  @impl StatifierBlocks.Runtime.Subchart
  @spec resolve_chart(String.t(), Handler.ctx()) :: {:ok, Document.t()} | :error
  def resolve_chart(document_id, _ctx) when is_binary(document_id), do: document(document_id)

  @doc """
  The palette a child is compiled against: this app's own, the same value
  the parent was compiled with.
  """
  @impl StatifierBlocks.Runtime.Subchart
  @spec palette() :: Palette.t()
  def palette, do: Charts.palette()

  @doc """
  The document ids the `core.subchart` blocks in `document` name, in
  document order and deduplicated.

  Read off the blocks rather than off a list somebody maintains beside
  them: which children a chart has is a fact about its bytes.
  """
  @spec references(Document.t()) :: [String.t()]
  def references(%Document{} = document) do
    for %Block{type: @subchart_type, config: config} <- Document.blocks(document),
        chart = Map.get(config, @chart_key),
        is_binary(chart) and chart != "",
        uniq: true,
        do: chart
  end

  @doc """
  The chart identity this host currently publishes for each document
  `document` names as a child: `%{document id => content hash}`.

  Campaign-023 ruling R-d, and the host-provenance pattern
  `StatifierBlocks.Core.Subchart` names - "pinning a *particular* child
  revision at publish time is a host provenance concern, carried in run
  metadata; the compiler does not do it". `src` is a document id, so a run
  started today and a run started after the child is edited both say
  `bdoc_signup_demo` and mean different charts. Recorded at run create
  (`StatifierExamples.Charts.Durable.start/4`), the hash is what tells the
  two apart afterwards.

  The hash is `Statifier.Machine.Identity`'s, taken over the child's
  emitted SCXML - the same bytes, hashed the same way, that
  `Statifier.compile/2` stamps onto a machine and the storage layer's
  identity guard compares (statifier-ex ADR-0052). That is only true while
  the compile here and the compile the handler runs produce the same
  bytes, so both are `child_use: true` against `palette/0` with the
  session's registered invoke types: the package reads
  `Map.keys(ctx.invoke_handlers)` and this reads
  `StatifierExamples.Charts.invoke_types/0`, which are the same set by
  construction (`invoke_handlers/0` is built from it).

  A child that does not resolve, or does not compile, is **absent** rather
  than recorded as an error: metadata is a pin, and there is nothing to
  pin. The run finds out at execution time, where the package refuses with
  `unknown_document` or `child_compile_findings` and the reason reaches the
  chart.
  """
  @spec identities(Document.t()) :: %{optional(String.t()) => String.t()}
  def identities(%Document{} = document) do
    document
    |> references()
    |> Enum.flat_map(&identity/1)
    |> Map.new()
  end

  @spec identity(String.t()) :: [{String.t(), String.t()}]
  defp identity(document_id) do
    with {:ok, child} <- document(document_id),
         {:ok, %Compiled{scxml: scxml}} <- child_compile(child) do
      [{document_id, Identity.of_source(scxml).content_hash}]
    else
      _unresolvable_or_uncompilable -> []
    end
  end

  @spec document(String.t()) :: {:ok, Document.t()} | :error
  defp document(document_id) do
    case Enum.find(Charts.fixtures(), &(&1.document.id == document_id)) do
      nil -> :error
      fixture -> {:ok, fixture.document}
    end
  end

  # The child recipe, in one place for the reason `identities/1` gives.
  @spec child_compile(Document.t()) :: {:ok, Compiled.t()} | {:error, [Compiler.Finding.t()]}
  defp child_compile(%Document{} = document) do
    Compiler.compile(document, palette(),
      child_use: true,
      known_invoke_types: Charts.invoke_types()
    )
  end
end
