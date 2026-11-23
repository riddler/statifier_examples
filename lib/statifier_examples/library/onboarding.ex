defmodule StatifierExamples.Library.Onboarding do
  @moduledoc """
  A branch library joining the network: one Path that asks which branch is
  joining, lets it pick the integrations it needs, and runs the setup of
  each one it picked as a durable child execution of its own.

  Two documents, as for every Path built from `myapp.step`:
  `priv/fixtures/branch_onboarding.json` is the block half and
  `priv/fixtures/branch_onboarding_screens.json` says what is on the
  branch's own screens. The setups are the three
  `StatifierExamples.Library.Setups` lists, each with its own Path and its
  own screens.

  ## Which children run is data

  The pick is a multi-select whose answer options' values are the setups'
  document ids, so the press writes the list of ids the branch chose to
  `responses.integrations`. A `core.foreach` walks that list, binding each
  id to `setup_document`, and the one block in its body is a
  `core.subchart` that names its child by `chart_from: "setup_document"`
  rather than by a literal `chart`. Each pass therefore starts the setup
  the branch picked, in the order the options list them, and the Path
  goes on to its closing screen once the last one has finished.

  The subchart declares the one outcome `done`, which is the one root
  outcome each setup declares (`StatifierExamples.Library.Setups`' "How a
  setup finishes"). statifier_blocks refuses, at child creation, a child
  whose root declares an outcome the block did not.

  ## The allow-list: `resolve_chart/2`

  This module is the subchart host for this Path. Its `resolve_chart/2`
  answers the three setups by their document ids, through
  `StatifierExamples.Library.Setups.fetch_document/1`, and `:error` for
  every other id - a fixture this app ships included - which
  statifier_blocks refuses as `unknown_document` before any child exists.
  A data-named child is exactly where an id could come from somewhere
  other than the author, so the list of what may run is this Path's and
  nobody else's.

  Each setup is handed back compiled, through
  `StatifierExamples.Charts.Subchart.child_compile/1`, the one child
  recipe: the bytes a child runs are then the bytes every other reader of
  a child compiles (`StatifierExamples.Charts.Durable`'s chart resolver,
  and `StatifierExamples.Signup.Journey` resuming the child with
  `child: true`).

  `StatifierExamples.Charts.Durable` hands a subchart invocation to this
  module when the invoking execution's chart is this Path
  (`parent?/1`), and to `StatifierExamples.Charts.Subchart` otherwise.

  ## Where a press goes: `focus/1`

  While a setup runs, the onboarding execution rests on its subchart's
  invocation and shows no screen of its own; the screen the branch sees is
  the setup's. `focus/1` answers which execution a page presents and
  presses, and with which `StatifierExamples.Signup.Journey` options: the
  onboarding execution's active child, read through
  `StatifierPersistence.Executions.active_children/2`, when it has one,
  and the onboarding execution itself otherwise. A page asks again after
  every press, because the press that finishes a setup moves the
  onboarding execution on.

  Back inside a setup goes back between the setup's own steps; Back
  between the branch's own screens goes back between those. Back across
  the boundary between the two is not offered: the setup's first step has
  nothing behind it in the setup's own execution.
  """

  use StatifierBlocks.Runtime.Subchart

  alias Statifier.Invoke.Handler
  alias Statifier.Machine.Identity
  alias StatifierBlocks.{Compiled, Decode, Document, Palette}
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{Durable, Subchart}
  alias StatifierExamples.Library.Setups
  alias StatifierPersistence.{Executions, Storage}

  @key "branch_onboarding"
  @path_file "branch_onboarding.json"
  @screens_file "branch_onboarding_screens.json"

  @doc "The key a page names this Path by."
  @spec key() :: String.t()
  def key, do: @key

  @doc "The Path: the block document."
  @spec document() :: Document.t()
  def document do
    case Decode.decode(File.read!(fixture(@path_file))) do
      {:ok, document} -> document
      {:error, error} -> raise "#{@path_file} is not a block document: #{inspect(error)}"
    end
  end

  @doc "The screens document the Path's own steps name, decoded."
  @spec screens() :: map()
  def screens, do: @screens_file |> fixture() |> File.read!() |> Jason.decode!()

  @doc """
  The options every `StatifierExamples.Signup.Journey` call over the
  onboarding execution itself takes: its screens document and its Path.
  """
  @spec options() :: [screens: map(), path: Document.t()]
  def options, do: [screens: screens(), path: document()]

  @doc """
  The setup whose document id is `document_id`, compiled for use as a
  child, or `:error` for any id that is not one of the three setups
  (the moduledoc's "The allow-list").
  """
  @impl StatifierBlocks.Runtime.Subchart
  @spec resolve_chart(term(), Handler.ctx()) :: {:ok, Compiled.t()} | {:ok, Document.t()} | :error
  def resolve_chart(document_id, _ctx) when is_binary(document_id) do
    with {:ok, document} <- Setups.fetch_document(document_id) do
      case Subchart.child_compile(document) do
        {:ok, compiled} -> {:ok, compiled}
        # Handed back uncompiled, so the package compiles it and refuses
        # it in its own words.
        {:error, _findings} -> {:ok, document}
      end
    end
  end

  def resolve_chart(_not_an_id, _ctx), do: :error

  @doc "The palette a child is compiled against: this app's own."
  @impl StatifierBlocks.Runtime.Subchart
  @spec palette() :: Palette.t()
  def palette, do: Charts.palette()

  @doc """
  Whether `content_hash` is the content hash of this Path as a Journey
  compiles it, so an invocation from that chart is this module's to
  resolve.
  """
  @spec parent?(String.t()) :: boolean()
  def parent?(content_hash) when is_binary(content_hash) do
    case Durable.compile(document(), []) do
      {:ok, %Compiled{scxml: scxml}} -> Identity.of_source(scxml).content_hash == content_hash
      {:error, _findings} -> false
    end
  end

  @doc """
  Which execution a page presents for the onboarding execution
  `execution_id`, and the `StatifierExamples.Signup.Journey` options a
  call over it takes (the moduledoc's "Where a press goes").

  `{:ok, {execution_id, options()}}` while no setup is running, and
  `{:ok, {child_id, options}}` while one is: the child's setup's own
  screens and Path, with `child: true`. `{:error, {:unknown_child,
  child_id}}` for an active child that is none of the three setups, and
  the storage layer's own refusals otherwise.
  """
  @spec focus(String.t()) :: {:ok, {String.t(), keyword()}} | {:error, term()}
  def focus(execution_id) when is_binary(execution_id) do
    with {:ok, store} <- Storage.new(StatifierExamples.Persistence, []),
         {:ok, children} <- Executions.active_children(store, execution_id) do
      case children do
        [] -> {:ok, {execution_id, options()}}
        [child | _later] -> child_focus(child)
      end
    end
  end

  @spec child_focus(StatifierPersistence.Execution.t()) ::
          {:ok, {String.t(), keyword()}} | {:error, {:unknown_child, String.t()}}
  defp child_focus(%{execution_id: child_id, content_hash: content_hash}) do
    with {:ok, key} <- setup_of(content_hash),
         {:ok, options} <- Setups.options(key) do
      {:ok, {child_id, options ++ [child: true]}}
    else
      :error -> {:error, {:unknown_child, child_id}}
    end
  end

  # The setup whose child compile hashes to `content_hash`.
  @spec setup_of(String.t()) :: {:ok, String.t()} | :error
  defp setup_of(content_hash) do
    Enum.find_value(Setups.keys(), :error, fn key ->
      with {:ok, document} <- Setups.document(key),
           {:ok, %Compiled{scxml: scxml}} <- Subchart.child_compile(document),
           true <- Identity.of_source(scxml).content_hash == content_hash do
        {:ok, key}
      else
        _other -> nil
      end
    end)
  end

  @spec fixture(String.t()) :: Path.t()
  defp fixture(file),
    do: Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
end
