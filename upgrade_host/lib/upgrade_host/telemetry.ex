defmodule UpgradeHost.Telemetry do
  @moduledoc """
  Attaches the three OpenTelemetry bridges `opentelemetry_statifier`
  ships: the engine's macrostep spans, the durable step spans around them,
  and the Oban job spans a fired timer or an answered invocation opens.

  Datamodel values stay out of every span (`record_datamodel_values:
  false`): a loan's datamodel names a patron, and a span is not where a
  patron's name belongs.
  """

  @opts [record_datamodel_values: false]

  @doc "Attaches all three bridges; `:ok` or the first refusal."
  @spec setup() :: :ok | {:error, term()}
  def setup do
    with :ok <- OpentelemetryStatifier.setup(@opts),
         :ok <- OpentelemetryStatifier.Persistence.setup(@opts) do
      OpentelemetryStatifier.Oban.setup(@opts)
    end
  end
end
