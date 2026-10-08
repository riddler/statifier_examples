defmodule UpgradeHost.Spans do
  @moduledoc """
  Reads the spans one test exported. The SDK's simple processor exports on
  the process that ended the span (`config/test.exs`), and
  `:otel_exporter_pid` sends each one to a pid as a `{:span, record}`
  message, so pointing it at the test process reads that test's spans.
  """

  require Record

  Record.defrecordp(
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  Record.defrecordp(
    :event,
    Record.extract(:event, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  @typedoc "One exported span: its name, its attributes and its events' attributes."
  @type collected :: %{name: String.t(), attributes: map(), events: [{String.t(), map()}]}

  @doc "Points the exporter at the calling process."
  @spec attach() :: :ok
  def attach do
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  @doc "Every span exported to this process so far, oldest first."
  @spec drain() :: [collected()]
  def drain, do: drain([])

  defp drain(acc) do
    receive do
      {:span, record} -> drain([collect(record) | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp collect(record) do
    events =
      for event <- record |> span(:events) |> :otel_events.list() do
        {to_string(event(event, :name)), :otel_attributes.map(event(event, :attributes))}
      end

    %{
      name: to_string(span(record, :name)),
      attributes: :otel_attributes.map(span(record, :attributes)),
      events: events
    }
  end
end
