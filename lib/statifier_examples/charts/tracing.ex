defmodule StatifierExamples.Charts.Tracing do
  @moduledoc """
  The host half of the family's OpenTelemetry story: which bridges this
  app attaches, and the one value it stamps that no library can stamp for
  it.

  `opentelemetry_statifier` turns the family's `:telemetry` events into
  spans. It depends on `opentelemetry_api` alone - a bridge that dragged
  an SDK in would be choosing the host's exporter for it - so naming the
  SDK, the processor and the exporter is this app's job, and so is
  deciding which of the three bridge halves to attach.

  ## Three setup calls, not one

  Each family is attached separately (st-ADR-0062, ots-ADR-0002 decision
  2), the shape `opentelemetry_ecto` and `opentelemetry_oban` compose in:

    * `OpentelemetryStatifier.setup/1` - the interpreter's family, the
      `statifier.macrostep` spans and every effect and trace event on
      them;
    * `OpentelemetryStatifier.Persistence.setup/1` - the durable
      stepper's, whose `statifier_persistence.run.step` span is the one
      paired seam in the family and the span a durable macrostep nests
      inside;
    * `OpentelemetryStatifier.Oban.setup/1` - the durable timer and
      asynchronous invoke seams.

  This app attaches all three because it is the one host that exercises
  all three. Attaching the persistence half without the interpreter half
  would produce step spans with nothing inside them, which that module's
  moduledoc says in its own words.

  ## What the trace graph actually looks like

  Worth stating plainly, because the shape surprises people who expect
  one trace per business operation, and because this app is where the
  family's observability story is looked at first.

  **It is a graph of linked roots, not one trace.** Every seam this app
  crosses is a deliberate root boundary in the design:

    * a macrostep span is the root of its own trace, stitched to the
      previous macrostep of the same session with a link
      (statifier-ex `docs/opentelemetry.md`; ots-ADR-0003 decision 8 -
      spans start from a fresh context, never the ambient one);
    * a durable child run is **linked** from its parent's step, never
      parented by it, because parenthood would hold the parent's trace
      open for the child's whole life (sp `docs/telemetry.md`,
      ADR-0008);
    * a fired timer is **linked** to the trace that armed it, never
      parented, for the same reason across a longer gap
      (sob-ADR-0006 decision 7).

  What joins them is `statifier.session_id`, present on every span in
  all three families, plus those link edges. `compile` is outside the
  graph entirely: `StatifierBlocks.Compiler` emits no telemetry, so a
  compile has no span under any configuration, and the arc this app
  proves starts at session start rather than at compile.

  Within one process one thing does nest, and it is the useful one: the
  bridge parents a span under whatever span **it itself** has open in
  **that** process (ots-ADR-0004). So a durable step span contains its
  macrostep span, and a child run created inside its parent's step -
  which is where `{:start_child, _, _}` creates it - contains the child's
  step span too. That nesting comes from the bridge's own table and never
  from the process's ambient OTel context, which is why the host span
  `drive/2` opens below parents nothing.

  ## The one value only a host can stamp

  `caller_context` is st-ADR-0063's opaque host slot. It rides from an
  event onto the effects that event's macrostep produces, through
  `statifier_oban`'s job row untouched, and back onto the fired event
  days later - and no package in the family ever reads it. Reading it as
  a trace context is `opentelemetry_statifier`'s, writing it is ours, and
  the wire form is fixed: `%{"traceparent" => "00-<trace>-<span>-01"}`,
  W3C text, because the row outlives the node and a pid, a ref or an
  unfamiliar atom comes back meaningless or undecodable.

  Without it a fired timer is an unlinked root correlated by
  `statifier.session_id` alone - the ordinary detached case both sibling
  contracts describe, and not an error. With it there is an edge across
  the gap, which is the whole of what `drive/2` and `caller_context/0`
  buy.

  A timer armed by the run's **first** drive carries no stamp whatever
  this module does: `Statifier.Interpreter` sets `caller_context` to
  `nil` for the `:initialize` macrostep, because that macrostep has no
  calling event to inherit one from. Only a timer armed by an
  event-driven step can carry one.
  """

  require OpenTelemetry.Tracer

  @doc """
  Attaches all three bridge halves. Safe to call more than once - every
  `setup/1` in the bridge detaches its own ids first.

  Returns `:ok`, or raises: a misconfigured bridge is a boot-time fact
  about this app, not something to discover as missing spans later.
  """
  @spec setup(keyword()) :: :ok
  def setup(opts \\ []) do
    :ok = attach(fn -> OpentelemetryStatifier.setup(opts) end, "interpreter")
    :ok = attach(fn -> OpentelemetryStatifier.Persistence.setup(opts) end, "persistence")
    :ok = attach(fn -> OpentelemetryStatifier.Oban.setup(opts) end, "oban")
  end

  @doc """
  Detaches all three halves. `setup/1`'s inverse, for a test that wants
  the bridge off.
  """
  @spec teardown() :: :ok
  def teardown do
    :ok = OpentelemetryStatifier.teardown()
    :ok = OpentelemetryStatifier.Persistence.teardown()
    :ok = OpentelemetryStatifier.Oban.teardown()
  end

  @doc """
  Runs `fun` inside a host span named `name`, so that the work under it
  has a trace context to stamp into `caller_context/0`.

  This is the "request span" both sibling contracts talk about when they
  say a fired timer links to *the trace that armed it*. It parents no
  bridge span - the bridge nests through its own table and ignores the
  ambient context - so its role is precisely and only to be a link
  target with a name a reader recognises.
  """
  @spec drive(String.t(), map(), (-> result)) :: result when result: term()
  def drive(name, attributes \\ %{}, fun) when is_binary(name) and is_function(fun, 0) do
    OpenTelemetry.Tracer.with_span name, %{attributes: attributes} do
      fun.()
    end
  end

  @doc """
  The current trace context in the durable, node-independent form the
  family asks a host to stamp, or `nil` when nothing is being traced.

  `nil` rather than an empty map on purpose: `nil` is the value both
  sibling contracts name for "no context was attached", and a
  `%{}` would round-trip through the job row as a term that decodes to
  something and links to nothing.

  Built through the configured text-map propagators rather than by
  formatting the span context by hand, so a host that adds `tracestate`
  or swaps in B3 gets whatever those propagators write.
  """
  @spec caller_context() :: %{optional(String.t()) => String.t()} | nil
  def caller_context do
    case :otel_propagator_text_map.inject([]) do
      [] -> nil
      carrier when is_list(carrier) -> Map.new(carrier)
    end
  end

  @spec attach((-> :ok | {:error, term()}), String.t()) :: :ok
  defp attach(setup, half) do
    case setup.() do
      :ok -> :ok
      {:error, reason} -> raise "the #{half} bridge is misconfigured: #{inspect(reason)}"
    end
  end
end
