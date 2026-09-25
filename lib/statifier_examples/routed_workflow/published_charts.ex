defmodule StatifierExamples.RoutedWorkflow.PublishedCharts do
  @moduledoc """
  The routed recipe's two chart lookups: the resolver the router asks
  which chart a new execution of a document starts on, and the chart
  resolver it asks for the chart an existing execution started on.

  This app keeps no store of published revisions, so "published" here
  means registered: `resolve/2` compiles the one document it knows, the
  way `StatifierExamples.RoutedWorkflow.runtime_chart/0` does, and answers
  it only when the chart registry already holds that compile under its
  content hash. A document it does not know, or one never registered, is
  `{:error, :not_published}`, and the router creates nothing.

  `chart/1` rebuilds a chart from the registry by content hash alone, as
  `StatifierExamples.FirstWorkflow.machine_for/2` does. An execution that
  already exists keeps the chart it started on, and this is how the router
  finds it.
  """

  @behaviour StatifierRouter.Resolver

  alias Statifier.Machine
  alias StatifierExamples.{FirstWorkflow, RoutedWorkflow}
  alias StatifierPersistence.Storage

  @impl StatifierRouter.Resolver
  @spec resolve(String.t(), String.t()) :: StatifierRouter.Resolver.result()
  def resolve(_scope, document) do
    with true <- document == RoutedWorkflow.document_id(),
         {:ok, machine, _scxml} <- RoutedWorkflow.runtime_chart(),
         content_hash = Machine.identity(machine).content_hash,
         {:ok, _chart} <- Storage.fetch_chart(FirstWorkflow.store(), content_hash) do
      {content_hash, machine}
    else
      _unpublished -> {:error, :not_published}
    end
  end

  @doc "The chart registered under `content_hash`, compiled, or `:error`."
  @spec chart(String.t()) :: {:ok, Machine.t()} | :error
  def chart(content_hash) do
    with {:ok, chart} <- Storage.fetch_chart(FirstWorkflow.store(), content_hash),
         {:ok, machine} <- Statifier.compile(chart.chart_blob) do
      {:ok, machine}
    else
      _missing -> :error
    end
  end
end
