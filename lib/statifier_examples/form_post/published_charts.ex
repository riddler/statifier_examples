defmodule StatifierExamples.FormPost.PublishedCharts do
  @moduledoc """
  The card application router's two chart lookups: the resolver the router
  asks which chart a new execution of the card application document starts
  on, and the chart resolver it asks for the chart an existing execution
  started on.

  They work as `StatifierExamples.RoutedWorkflow.PublishedCharts` does for
  the parcel route. This app keeps no store of published revisions, so
  "published" means registered: `resolve/2` compiles the one document it
  knows and answers it only when the chart registry already holds that
  compile under its content hash. Any other document, or one never
  registered, is `{:error, :not_published}`, and the router creates
  nothing. `chart/1` rebuilds a chart from the registry by content hash
  alone, so an execution keeps the chart it started on.

  ## The document

  The document is `priv/form_post/card_application.json`, whose id is
  `StatifierExamples.FormPost.Router.document_id/0`. A test that routes
  card applications without that document names another file of the same
  id in the application environment:

      config :statifier_examples, StatifierExamples.FormPost.PublishedCharts,
        document: "/path/to/a/document.json"

  No config file sets it: absent, the document is the one under `priv/`.
  Like `StatifierExamples.FormPost.Steps`' hook, it is a test's knob, not
  something a host ships.
  """

  @behaviour StatifierRouter.Resolver

  alias Statifier.Machine
  alias StatifierBlocks.{Compiled, Compiler, Decode}
  alias StatifierExamples.{Charts, FirstWorkflow}
  alias StatifierExamples.FormPost.Router
  alias StatifierPersistence.Storage

  @document "form_post/card_application.json"

  @impl StatifierRouter.Resolver
  @spec resolve(String.t(), String.t()) :: StatifierRouter.Resolver.result()
  def resolve(_scope, document) do
    with true <- document == Router.document_id(),
         {:ok, machine, _scxml} <- runtime_chart(),
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

  @doc """
  The chart an execution of the card application document runs: the
  document compiled for running, with `terminate: true` so a finished flow
  completes the execution, and the SCXML it was compiled from.

  Answers `{:error, reason}` when the document cannot be read, decoded or
  compiled, or names another document id.
  """
  @spec runtime_chart() :: {:ok, Machine.t(), String.t()} | {:error, term()}
  def runtime_chart do
    with {:ok, json} <- File.read(path()),
         {:ok, document} <- Decode.decode(json),
         :ok <- same_id(document.id),
         {:ok, %Compiled{scxml: scxml}} <-
           Compiler.compile(document, Charts.palette(), terminate: true),
         {:ok, machine} <- Statifier.compile(scxml) do
      {:ok, machine, scxml}
    end
  end

  @spec same_id(String.t()) :: :ok | {:error, {:document_id, String.t()}}
  defp same_id(id) do
    if id == Router.document_id(), do: :ok, else: {:error, {:document_id, id}}
  end

  @spec path() :: Path.t()
  defp path do
    :statifier_examples
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get_lazy(:document, fn ->
      :statifier_examples |> :code.priv_dir() |> Path.join(@document)
    end)
  end
end
