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

  ## Single-level only, and why that is now a choice rather than a limit

  A child session is started by `Statifier.Session` with `invoked_by:`, a
  seeded datamodel and the parent's observer options. Whether it also gets
  the parent's `:invoke_handlers` is the root session's call: the engine
  defaults `:inherit_invoke_handlers` to `false`, and a root that opts in
  hands every child its handler map along with the flag itself, so the
  opt-in is transitive down the invoke tree (statifier-ex **st-pvpz**).

  Off, a child chart's own `<invoke>`s reach a session with no handler
  registered for them at all, whether they are `myapp:*` calls or a nested
  `statifier_blocks:subchart` - which is what `signup_onboarding` did for
  its whole life before that option existed, its wizard child parking at
  its first step. On, the child answers them. This app opts in where it
  starts a root session, so the shipped embed runs to depth 2: the wizard
  child dispatches its own `myapp:signup` calls, advances through its own
  steps and ends with an outcome the parent's `on_done` and `on_abandon`
  slots route on. `StatifierExamples.Charts.SubchartTest` drives both
  positions, which is what keeps the sentence above honest.

  That the option is opt-in rather than the default is the engine's
  deliberate stance and not a gap: inheritance would otherwise run a
  host's handlers inside charts nobody registered them for. A host that
  embeds charts states it, and this app is the reference embedder stating
  it - the posture `CLAUDE.md` requires, in place of a workaround.

  Inheritance is transitive, so a subchart inside a subchart would run
  too. That the shipped documents stay one level deep is therefore an
  authoring choice about the example set, and it is the choice that keeps
  `resolve_chart/2`'s missing `{:cycle, _}` arm honest - see above.

  ## Durable runs, and why this module serves both

  `{:start_child, _, _}` used to be executed by `Statifier.Session` and by
  nothing else, so a durable run reaching a subchart was refused. It is
  not any more (se-6ag): `StatifierPersistence.Driver` executes the same
  instruction by creating the child as its **own persisted run**, linked
  to the parent by run metadata and pinned to the child's content hash
  (sp ADR-0008).

  Which of the two runs a `core.subchart` is host wiring rather than a
  fact about the document (sb ADR-0008 decision 1), and the two handlers
  are two modules serving one invoke type: `StatifierBlocks.Runtime.Subchart`
  in memory, `StatifierBlocks.Runtime.DurableSubchart` durably. This
  module is the **host callbacks for both** - `resolve_chart/2` and
  `palette/0` are shared and unchanged (decision 2), so the same lookup
  answers a session run and a durable run and there is no second place a
  document id is resolved. `StatifierExamples.Charts.invoke_handlers/0`
  registers the in-memory one for a session; the durable one is reached
  from `StatifierExamples.Charts.Durable`'s dispatch fun, which is where
  a driver's `<invoke>` goes.

  The pin `identities/1` records is unchanged and is still worth having
  on the durable path, though the two answer different questions. The pin
  says which child revision this run was *created* against, at create; the
  child run's own linkage carries the hash the driver actually started,
  at dispatch. They agree, and a reader with both can say so.
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

  @doc """
  Compiles `document` the way a *child* is compiled: `child_use: true`,
  against `palette/0`, with the invoke types this app registers.

  The child recipe, in one place for the reason `identities/1` gives - the
  hash it takes has to be the hash of the bytes the handler actually runs,
  which is only true while there is one recipe. It is public because there
  is a second reader now: `StatifierExamples.Charts.Durable`'s
  `chart_resolver:` walks both compiles of every shipped document to answer
  a durable subchart's parent, and a private copy of this recipe there
  would be the second definition this function exists to prevent.
  """
  @spec child_compile(Document.t()) :: {:ok, Compiled.t()} | {:error, [Compiler.Finding.t()]}
  def child_compile(%Document{} = document) do
    Compiler.compile(document, palette(),
      child_use: true,
      known_invoke_types: Charts.invoke_types()
    )
  end
end
