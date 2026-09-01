defmodule StatifierExamples.TraceCollector do
  @moduledoc """
  Collects the spans one test produced, and renders them as the trace
  graph a reader navigates.

  The SDK's simple processor exports on the process that ended the span,
  synchronously (`config/test.exs`), and `:otel_exporter_pid` sends each
  exported span to a pid as a `{:span, record}` message. Pointing that at
  the test's own pid is what keeps two tests in one node from reading
  each other's spans.

  ## Why this renders a graph rather than a tree

  The family's design puts a root boundary at every seam that could
  outlive a request - macrostep, child run, fired timer - and joins the
  roots with links and with `statifier.session_id` instead
  (`StatifierExamples.Charts.Tracing` has the citations). So a renderer
  that only walked `parent_span_id` would draw a dozen unrelated
  stumps and hide the entire structure. `graph/1` walks parents *and*
  links, and `render/1` prints link edges with an arrow so the two kinds
  of edge stay visually distinct.
  """

  require Record

  @span_fields Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:span, @span_fields)

  @link_fields Record.extract(:link, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:link, @link_fields)

  @event_fields Record.extract(:event, from_lib: "opentelemetry/include/otel_span.hrl")
  Record.defrecordp(:event, @event_fields)

  @typedoc """
  One collected span, flattened out of the SDK's record into the shape
  the assertions and the renderer both want.
  """
  @type collected :: %{
          name: String.t(),
          trace_id: String.t(),
          span_id: String.t(),
          parent_span_id: String.t() | nil,
          attributes: %{optional(String.t()) => term()},
          events: [{String.t(), %{optional(String.t()) => term()}}],
          links: [String.t()],
          start_time: integer()
        }

  @doc """
  Points the simple processor's exporter at the calling process for the
  rest of the test, and restores nothing afterwards - the next test that
  calls this claims it in turn.
  """
  @spec attach() :: :ok
  def attach do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
  end

  @doc """
  Every span exported to this process so far, oldest start first.

  Drains the mailbox with a zero timeout: the processor is synchronous,
  so anything that was going to arrive has arrived by the time the work
  under test has returned.
  """
  @spec drain() :: [collected()]
  def drain, do: drain([])

  @doc """
  The spans reachable from the spans `from` selects, by parent edges, link
  edges, and shared correlation ids - the campaign-026 proof's
  navigability claim, made checkable.

  Reachability is deliberately over the undirected graph. A link points
  from the fired timer back to the trace that armed it, and from a
  macrostep back to its predecessor, so a reader starting at the parent's
  first span follows some edges backwards; that they can get there at all
  is the claim.
  """
  @spec reachable([collected()], (collected() -> boolean())) :: MapSet.t(String.t())
  def reachable(spans, from) when is_function(from, 1) do
    roots = for s <- spans, from.(s), do: s.span_id

    spans
    |> adjacency()
    |> walk(roots, MapSet.new(roots))
  end

  @doc """
  The collected spans as text: one line per span, nested by parent, with
  each span's link edges, its span events, and the attributes that make
  the graph navigable.

  This is what the campaign capture is a copy of, which is why it is here
  rather than in the test - a capture rendered by throwaway code in a
  scratch file proves nothing a month later.
  """
  @spec render([collected()]) :: String.t()
  def render(spans) do
    by_parent = Enum.group_by(spans, & &1.parent_span_id)

    spans
    |> Enum.filter(&is_nil(&1.parent_span_id))
    |> Enum.sort_by(& &1.start_time)
    |> Enum.map_join("\n", &render_span(&1, by_parent, 0))
  end

  @spec drain([collected()]) :: [collected()]
  defp drain(acc) do
    receive do
      {:span, record} -> drain([collect(record) | acc])
    after
      0 -> Enum.sort_by(acc, & &1.start_time)
    end
  end

  @spec collect(tuple()) :: collected()
  defp collect(record) do
    %{
      name: to_string(span(record, :name)),
      trace_id: hex(span(record, :trace_id), 32),
      span_id: hex(span(record, :span_id), 16),
      parent_span_id: parent(span(record, :parent_span_id)),
      attributes: attributes(span(record, :attributes)),
      events: events(span(record, :events)),
      links: links(span(record, :links)),
      start_time: span(record, :start_time)
    }
  end

  # `:undefined` is the SDK's "no parent", and a root span is exactly what
  # this proof expects most spans to be.
  @spec parent(term()) :: String.t() | nil
  defp parent(:undefined), do: nil
  defp parent(id) when is_integer(id), do: hex(id, 16)
  defp parent(_other), do: nil

  # Both attributes and events arrive wrapped in the SDK's own bounded
  # collections; `:otel_attributes.map/1` and `:otel_events.list/1` are the
  # accessors, and neither is guaranteed to be present on a record built by
  # an older SDK, hence the map/list fallbacks.
  @spec attributes(term()) :: map()
  defp attributes(attributes) when is_tuple(attributes) do
    attributes
    |> :otel_attributes.map()
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp attributes(_other), do: %{}

  @spec events(term()) :: [{String.t(), map()}]
  defp events(events) when is_tuple(events) do
    events
    |> :otel_events.list()
    |> Enum.map(fn record ->
      {to_string(event(record, :name)), attributes(event(record, :attributes))}
    end)
  end

  defp events(_other), do: []

  @spec links(term()) :: [String.t()]
  defp links(links) when is_tuple(links) do
    links
    |> :otel_links.list()
    |> Enum.map(&hex(link(&1, :span_id), 16))
  end

  defp links(_other), do: []

  @spec hex(term(), pos_integer()) :: String.t()
  defp hex(id, width) when is_integer(id) do
    id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
  end

  defp hex(_id, _width), do: ""

  # The correlation keys a reader actually follows between two roots. They
  # are the ids the three contracts agree on: a logical session, a durable
  # run, the two ends of a parent/child link, and `statifier_oban`'s scope
  # (which the bridge already aliases onto `statifier.session_id`).
  @correlation ~w(
    statifier.session_id
    statifier_persistence.run_id
    statifier_persistence.parent_run_id
    statifier_persistence.child_run_id
    statifier_oban.scope
  )

  @doc """
  Every correlation id a span carries, its span events included.

  The span events matter more than the span's own attributes here: the
  `child.started` and `child.answered` edges are *points*, so the bridge
  lands them on whatever step span is open around them, and the child's
  run id is on the event rather than on its host span.
  """
  @spec identifiers(collected()) :: MapSet.t(String.t())
  def identifiers(span) do
    [span.attributes | Enum.map(span.events, &elem(&1, 1))]
    |> Enum.flat_map(fn attributes ->
      for key <- @correlation, value = attributes[key], is_binary(value), do: value
    end)
    |> MapSet.new()
  end

  # Parent edges, link edges, and shared-identifier edges, all undirected.
  # The last is what the design leans on hardest: with every seam that can
  # outlive a request deliberately rooting its own trace, a shared run id
  # is the only thing joining two of them.
  @spec adjacency([collected()]) :: %{optional(String.t()) => MapSet.t(String.t())}
  defp adjacency(spans) do
    ids = Map.new(spans, &{&1.span_id, identifiers(&1)})

    by_id =
      spans
      |> Enum.flat_map(fn s -> for id <- ids[s.span_id], do: {id, s.span_id} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Enum.reduce(spans, %{}, fn s, acc ->
      neighbours =
        [s.parent_span_id]
        |> Enum.concat(s.links)
        |> Enum.concat(Enum.flat_map(ids[s.span_id], &Map.get(by_id, &1, [])))
        |> Enum.reject(&(is_nil(&1) or &1 == s.span_id))

      Enum.reduce(neighbours, acc, fn other, acc ->
        acc
        |> Map.update(s.span_id, MapSet.new([other]), &MapSet.put(&1, other))
        |> Map.update(other, MapSet.new([s.span_id]), &MapSet.put(&1, s.span_id))
      end)
    end)
  end

  @spec walk(map(), [String.t()], MapSet.t(String.t())) :: MapSet.t(String.t())
  defp walk(_adjacency, [], seen), do: seen

  defp walk(adjacency, [current | rest], seen) do
    next =
      adjacency
      |> Map.get(current, MapSet.new())
      |> Enum.reject(&MapSet.member?(seen, &1))

    walk(adjacency, next ++ rest, MapSet.union(seen, MapSet.new(next)))
  end

  @spec render_span(collected(), map(), non_neg_integer()) :: String.t()
  defp render_span(span, by_parent, depth) do
    pad = String.duplicate("  ", depth)

    [
      "#{pad}#{span.name}  [trace #{short(span.trace_id)} span #{short(span.span_id)}]",
      render_attributes(span, pad),
      render_links(span, pad),
      render_events(span, pad),
      by_parent
      |> Map.get(span.span_id, [])
      |> Enum.sort_by(& &1.start_time)
      |> Enum.map(&render_span(&1, by_parent, depth + 1))
    ]
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # Only the keys that carry the graph. A span's full attribute set is
  # large and most of it is counters; what a reader of the capture is
  # checking is identity and linkage.
  @navigational ~w(
    statifier.session_id statifier.trigger statifier.outcome statifier.driver
    statifier_persistence.run_id statifier_persistence.parent_run_id
    statifier_persistence.child_run_id statifier_persistence.invoke_id
    statifier_oban.scope statifier_oban.send_id statifier_oban.job_id
  )

  @spec render_attributes(collected(), String.t()) :: [String.t()]
  defp render_attributes(span, pad) do
    for key <- @navigational, value = span.attributes[key], value != nil do
      "#{pad}  · #{key} = #{inspect(value)}"
    end
  end

  @spec render_links(collected(), String.t()) :: [String.t()]
  defp render_links(span, pad) do
    for target <- span.links, do: "#{pad}  --link--> span #{short(target)}"
  end

  @spec render_events(collected(), String.t()) :: [String.t()]
  defp render_events(span, pad) do
    for {name, attributes} <- span.events do
      detail =
        for key <- @navigational, value = attributes[key], value != nil do
          "#{key}=#{inspect(value)}"
        end

      "#{pad}  * #{name}#{if detail == [], do: "", else: "  (" <> Enum.join(detail, " ") <> ")"}"
    end
  end

  @spec short(String.t()) :: String.t()
  defp short(id), do: String.slice(id, 0, 8)
end
