defmodule StatifierExamples.Documents do
  @moduledoc """
  The one place an edited document lives while this app is running: a map
  from fixture key to `StatifierBlocks.Document`, held in a process rather
  than in a LiveView's assigns.

  ## Why it exists at all

  `se-1cl` puts a second view - `StatifierExamplesWeb.PlanLive` - over the
  same documents `StatifierExamplesWeb.EditorLive` shows, which is D16's
  reference pattern: a host-native view over the package's public APIs
  rather than a second layout mode inside the package. The two views are
  two LiveViews, so they are two processes, and until this module existed
  each held its own `documents` map in its own assigns. An edit made in one
  was invisible to the other, and "Open in editor" opened the document as
  it was on disk rather than the one just edited.

  A document is not a property of a socket, so it does not belong in one.
  It is a property of the app, and this is the app's store.

  ## What it deliberately is not

  It is one Agent holding one map, and every viewer of this app shares it.
  That is the whole implementation, and it is stated here rather than
  hidden because a real host would replace it: a tenant's documents belong
  in that tenant's database, keyed by whatever identity that host already
  has, and none of this app's pages would change if they did. The seam is
  `get/2` and `put/2`, and swapping an Ecto-backed module in behind those
  two functions is the exercise.

  Two consequences follow from "one map, in a process", and both are the
  shape of the demo rather than an oversight:

    * an edit survives a reload and a document switch, because the map
      outlives the socket that wrote it;
    * an edit does not survive a restart, because the map is process state
      and nothing writes it to disk. What this app *stores* is runs.

  `reset/0` is the test seam, and it is here rather than in the test tree
  because the state it clears is this module's.
  """

  use Agent

  alias StatifierBlocks.Document

  @doc "Starts the store, empty."
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  The document stored under `key`, or `default` when nothing is stored.

  `default` is the fixture's own decoded document, so the first read of a
  key an author has not edited is the bytes on disk.
  """
  @spec get(String.t(), Document.t()) :: Document.t()
  def get(key, %Document{} = default) when is_binary(key) do
    Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  @doc "Stores `document` under `key`, replacing whatever was there."
  @spec put(String.t(), Document.t()) :: :ok
  def put(key, %Document{} = document) when is_binary(key) do
    Agent.update(__MODULE__, &Map.put(&1, key, document))
  end

  @doc """
  Forgets every stored document.

  One process holds every test's edits, so a test that edits a fixture
  would otherwise hand the next test a document it did not write. The
  `StatifierExamplesWeb.ConnCase` setup calls this.
  """
  @spec reset() :: :ok
  def reset do
    Agent.update(__MODULE__, fn _stored -> %{} end)
  end
end
