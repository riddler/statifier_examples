defmodule StatifierExamples.Publish do
  @moduledoc """
  This app's publish step: one pure function that runs every publish-time
  check the family's packages ship over a block document, and answers
  whether the document may be published.

  This is what a host's publish step looks like, and a host's own is the
  host's. The packages ship pure check functions and no publish step - no
  store of published revisions, no process, no manager - so the step that
  calls those functions in order and refuses the publish is always written
  by the host, over its own registries, its own store and its own lookup of
  what is already published. This module is the reference embedder's
  version of that step. It holds nothing and publishes nothing: `check/2`
  judges one document against the host state it is handed and answers, and
  storing the compiled artifact under a revision is the caller's act. The
  editor can run the same function at edit time, and the engine's own
  checks at run time stay the backstop behind it.

  ## The stages

  `check/2` runs seven stages in this order and stops at the first one that
  refuses:

    1. `:findings` - `StatifierBlocks.Publish.findings/3`, the findings the
       editor shows for the same document, before any compile.
    2. `:compile` - `StatifierBlocks.Compiler.compile/3`, and then
       `Statifier.compile/2` over the generated SCXML, which is the machine
       every later stage reads.
    3. `:send_types` - `Statifier.Send.Types.unsupported_sends/2`: a
       `<send>` whose literal `type` names no processor the host registers.
    4. `:routes` - `StatifierRouter.Routes.unregistered/2`: a `<send>` of
       the router's own type whose literal `target` names no route the host
       registered.
    5. `:contracts` - `StatifierRouter.Contracts.check/3`: an event a
       `<send>` or a binding names that its receiving document does not
       accept. Its send types are not judged again here; see below.
    6. `:accepts` - `Statifier.Chart.check_accepts/2`, over the compiled
       machine and the document's own `accepts` list.
    7. `:graph` - `StatifierBlocks.Graph.check/2`: every child document the
       document names is published and declares what the document reads
       from it.

  ## Refused, or passed with warnings

  A stage refuses only on an error. A warning never refuses: it is carried
  to the answer, and the stages after it still run. So `check/2` answers
  `{:ok, compiled, accepts, warnings}` when no stage found an error, and
  `{:refused, %{stage: stage, findings: findings}}` naming the first stage
  that did, with that stage's errors only.

  Which result of each package function is an error and which a warning is
  this host's reading, stated here so it is one decision rather than seven:

    * a `StatifierBlocks.Finding` or a `StatifierBlocks.Compiler.Finding` is
      an error or a warning by its own `severity`; an `:info` finding is
      the editor's advisory, changes no verdict and is not carried;
    * every entry of `unsupported_sends/2`, of `unregistered/2`'s
      `:unregistered` list and of `Contracts.check/3`'s
      `:unregistered_routes`, `:undeclared_events` and
      `:undeclared_binding_events` lists is an error;
    * `Contracts.check/3`'s `:unsupported_types` list is not read. It
      judges each `<send>` type against the send-type snapshot on the
      router configuration's `:persistence_options`, which
      `StatifierRouter.Config.new/1` builds from the router's own
      `:send_type` alone, while the `:send_types` stage has already judged
      every `<send>` type against the host's whole registry, `:send_types`.
      Reading it would refuse a send to a second processor the host
      registers;
    * every `:unchecked` entry of `unregistered/2` and of
      `Contracts.check/3` is a warning: a `<send>` whose type, target,
      event or receiving document is an expression cannot be judged before
      it runs, so it is reported as unchecked rather than refused or passed
      in silence. `Contracts.check/3` repeats `unregistered/2`'s unchecked
      entries, and a warning is carried once;
    * a declared `accepts` name no reachable transition can take is an
      error; a name the chart listens for that the declaration does not
      state is the document's own internal event and is not reported at
      all. An empty `accepts` list declares nothing, and is checked as no
      declaration.

  ## One finding shape, and no shared struct

  Each package reports in its own shape, and no struct is shared across the
  packages. Every error and every warning here is normalized to the same
  plain map, `%{check: check, anchor: anchor, message: message}`, by
  convention only: `check` is an atom naming the rule, `anchor` says where
  the rule was broken - a block-document anchor such as
  `{:config, block_id, key}`, `:document`, `{:scxml, location}` for an
  element of the generated chart, `{:binding, id}` or `{:accepts, name}` -
  and `message` is the package's own words where it has any.

  ## The host map

  `host` is the host's own state, as a map:

    * `:palette` - the `StatifierBlocks.Palette` the document is authored
      against.
    * `:datamodel` - the datamodel document, or `nil` for none.
    * `:declare` - optional: the `<data>` roots this deployment adds, the
      compile's `:declare` list. Absent means `[]`.
    * `:send_types` - the `%{type => module}` map of send processors the
      host registers, `%{}` for none.
    * `:router_config` - the host's resolved `StatifierRouter.Config`. Its
      `:bindings` are the bindings `Contracts.check/3` judges, so the host's
      bindings are handed over inside it.
    * `:accepts_lookup` - the host's lookup from a receiving document id to
      what that document accepts (`t:StatifierRouter.Contracts.lookup/0`).
    * `:document_resolver` - the host's lookup from a child document id to
      its published compiled artifact (`t:StatifierBlocks.Graph.resolver/0`).

  The two lookups are the only calls that reach outside the arguments, and
  they are the host's: `check/2` itself starts no process, touches no store
  and performs no IO.
  """

  alias Statifier.Chart
  alias Statifier.Send.Types
  alias StatifierBlocks.{Compiled, Compiler, Document, Finding, Graph, Palette}
  alias StatifierRouter.{Config, Contracts, Routes}

  @typedoc "The stage a refusal names; see the moduledoc."
  @type stage :: :findings | :compile | :send_types | :routes | :contracts | :accepts | :graph

  @typedoc "One error or warning, normalized by convention; see the moduledoc."
  @type finding :: %{check: atom(), anchor: term(), message: String.t()}

  @typedoc "The host's own state; see the moduledoc."
  @type host :: %{
          required(:palette) => Palette.t(),
          required(:datamodel) => map() | nil,
          optional(:declare) => [{String.t(), String.t() | nil}],
          required(:send_types) => %{optional(String.t()) => module()},
          required(:router_config) => Config.t(),
          required(:accepts_lookup) => Contracts.lookup(),
          required(:document_resolver) => Graph.resolver()
        }

  @type result ::
          {:ok, Compiled.t(), [String.t()], [finding()]}
          | {:refused, %{stage: stage(), findings: [finding()]}}

  @doc """
  Runs the seven publish-time stages over `document` against `host`, in
  order, and stops at the first stage that finds an error.

  Answers `{:ok, compiled, accepts, warnings}` - the compiled artifact, the
  document's declared `accepts` list and every warning the stages found -
  or `{:refused, %{stage: stage, findings: findings}}` with the refusing
  stage and its errors. See the moduledoc for the stages, for which result
  is an error, and for the finding shape.
  """
  @spec check(Document.t(), host()) :: result()
  def check(%Document{} = document, %{palette: %Palette{} = palette} = host) do
    declare = Map.get(host, :declare, [])
    context = %{datamodel: host.datamodel, declare: declare}

    with {:ok, warnings} <- findings_stage(document, palette, context),
         {:ok, compiled, machine, compile_warnings} <-
           compile_stage(document, palette, host.datamodel, declare),
         warnings = warnings ++ compile_warnings,
         :ok <- send_types_stage(machine, host.send_types),
         {:ok, route_warnings} <- routes_stage(host.router_config, machine),
         {:ok, contract_warnings} <-
           contracts_stage(host.router_config, machine, host.accepts_lookup),
         :ok <- accepts_stage(machine, compiled.accepts),
         {:ok, graph_warnings} <- graph_stage(compiled, host.document_resolver) do
      warnings = warnings ++ route_warnings ++ contract_warnings ++ graph_warnings
      {:ok, compiled, compiled.accepts, Enum.uniq(warnings)}
    end
  end

  @spec findings_stage(Document.t(), Palette.t(), StatifierBlocks.Publish.context()) ::
          {:ok, [finding()]} | {:refused, map()}
  defp findings_stage(document, palette, context) do
    document
    |> StatifierBlocks.Publish.findings(palette, context)
    |> Enum.map(&{&1.severity, normalize(&1)})
    |> verdict(:findings)
  end

  @spec compile_stage(Document.t(), Palette.t(), map() | nil, list()) ::
          {:ok, Compiled.t(), Statifier.Machine.t(), [finding()]} | {:refused, map()}
  defp compile_stage(document, palette, datamodel, declare) do
    with {:ok, %Compiled{} = compiled} <-
           Compiler.compile(document, palette, datamodel: datamodel, declare: declare),
         {:ok, machine} <- Statifier.compile(compiled.scxml) do
      {:ok, compiled, machine, Enum.map(compiled.warnings, &normalize/1)}
    else
      {:error, errors} -> refused(:compile, Enum.map(errors, &normalize/1))
    end
  end

  @spec send_types_stage(Statifier.Machine.t(), %{optional(String.t()) => module()}) ::
          :ok | {:refused, map()}
  defp send_types_stage(machine, send_types) do
    case Types.unsupported_sends(machine, Types.from_send_types(send_types)) do
      [] -> :ok
      sends -> refused(:send_types, Enum.map(sends, &unsupported_send/1))
    end
  end

  @spec routes_stage(Config.t(), Statifier.Machine.t()) ::
          {:ok, [finding()]} | {:refused, map()}
  defp routes_stage(%Config{} = config, machine) do
    %{unregistered: unregistered, unchecked: unchecked} = Routes.unregistered(config, machine)

    Enum.map(unregistered, &{:error, unregistered_route(&1)})
    |> Enum.concat(Enum.map(unchecked, &{:warning, unchecked(&1)}))
    |> verdict(:routes)
  end

  @spec contracts_stage(Config.t(), Statifier.Machine.t(), Contracts.lookup()) ::
          {:ok, [finding()]} | {:refused, map()}
  defp contracts_stage(%Config{} = config, machine, lookup) do
    report = Contracts.check(config, machine, lookup)

    # `report.unsupported_types` is left unread: the send_types stage
    # judged every send type against the host's registry; see the moduledoc.
    Enum.map(report.unregistered_routes, &{:error, unregistered_route(&1)})
    |> Enum.concat(Enum.map(report.undeclared_events, &{:error, undeclared_event(&1)}))
    |> Enum.concat(Enum.map(report.undeclared_binding_events, &{:error, undeclared_binding(&1)}))
    |> Enum.concat(Enum.map(report.unchecked, &{:warning, unchecked(&1)}))
    |> verdict(:contracts)
  end

  # sb ADR-0014 decision 5: an empty list and an absent
  # key are the same declaration, which is no declaration at all.
  @spec accepts_stage(Statifier.Machine.t(), [String.t()]) :: :ok | {:refused, map()}
  defp accepts_stage(machine, accepts) do
    declared = if accepts == [], do: nil, else: accepts

    case Chart.check_accepts(machine, declared) do
      %{unreachable: []} -> :ok
      %{unreachable: names} -> refused(:accepts, Enum.map(names, &unreachable/1))
    end
  end

  @spec graph_stage(Compiled.t(), Graph.resolver()) :: {:ok, [finding()]} | {:refused, map()}
  defp graph_stage(compiled, resolver) do
    compiled
    |> Graph.check(resolver)
    |> Enum.map(&{&1.severity, normalize(&1)})
    |> verdict(:graph)
  end

  # A stage's verdict over its `{severity, finding}` pairs: refused on the
  # first error with every error, else passed with every warning.
  @spec verdict([{Finding.severity(), finding()}], stage()) ::
          {:ok, [finding()]} | {:refused, map()}
  defp verdict(pairs, stage) do
    case for({:error, finding} <- pairs, do: finding) do
      [] -> {:ok, for({:warning, finding} <- pairs, do: finding)}
      errors -> refused(stage, errors)
    end
  end

  @spec refused(stage(), [finding()]) :: {:refused, %{stage: stage(), findings: [finding()]}}
  defp refused(stage, findings), do: {:refused, %{stage: stage, findings: findings}}

  @spec normalize(Finding.t() | Compiler.Finding.t() | Statifier.error()) :: finding()
  defp normalize(%Finding{source: source, anchor: anchor, message: message}),
    do: %{check: source, anchor: anchor, message: message}

  defp normalize(%Compiler.Finding{} = finding),
    do: %{check: finding.code, anchor: compiler_anchor(finding), message: finding.message}

  # The engine refusing the generated SCXML. Each of its four error kinds
  # carries a message and the location of the element at fault.
  defp normalize(%{message: message, location: location}),
    do: %{check: :chart, anchor: {:scxml, location}, message: message}

  # The anchor a compiler finding routes to, by the rule
  # `StatifierBlocks.Finding.from_compiler/2` applies: the block it names,
  # narrowed to a field when it names one, and the document when it names
  # no block.
  @spec compiler_anchor(Compiler.Finding.t()) :: Finding.anchor()
  defp compiler_anchor(%Compiler.Finding{block_id: nil}), do: :document
  defp compiler_anchor(%Compiler.Finding{block_id: id, config_key: nil}), do: {:block, id}
  defp compiler_anchor(%Compiler.Finding{block_id: id, config_key: key}), do: {:config, id, key}

  @spec unsupported_send(Types.unsupported_send()) :: finding()
  defp unsupported_send(%{type: type, location: location}) do
    %{
      check: :unsupported_send_type,
      anchor: {:scxml, location},
      message: ~s(no send processor is registered for the type "#{type}")
    }
  end

  @spec unregistered_route(Routes.finding()) :: finding()
  defp unregistered_route(%{route: nil, location: location}) do
    %{
      check: :unregistered_route,
      anchor: {:scxml, location},
      message: "the send names no route in its target"
    }
  end

  defp unregistered_route(%{route: route, location: location}) do
    %{
      check: :unregistered_route,
      anchor: {:scxml, location},
      message: ~s(no route "#{route}" is registered)
    }
  end

  @spec unchecked(Routes.unchecked() | Contracts.unchecked()) :: finding()
  defp unchecked(%{reason: reason, location: location}) do
    %{
      check: :unchecked,
      anchor: {:scxml, location},
      message: "the send cannot be checked before it runs (#{reason})"
    }
  end

  @spec undeclared_event(Contracts.finding()) :: finding()
  defp undeclared_event(%{event: event, document: document, location: location, reason: reason}) do
    %{
      check: reason,
      anchor: {:scxml, location},
      message: ~s("#{document}" does not accept the event "#{event}")
    }
  end

  @spec undeclared_binding(Contracts.binding_finding()) :: finding()
  defp undeclared_binding(%{event: event, document: document, binding_id: id, reason: reason}) do
    %{
      check: reason,
      anchor: {:binding, id},
      message: ~s("#{document}" does not accept the event "#{event}")
    }
  end

  @spec unreachable(String.t()) :: finding()
  defp unreachable(name) do
    %{
      check: :unreachable_accepts,
      anchor: {:accepts, name},
      message: ~s(the document accepts "#{name}" and no transition in its chart takes it)
    }
  end
end
