defmodule StatifierExamples.Library.Setups do
  @moduledoc """
  The three setups a branch library runs when it joins: a catalogue sync, a
  reading-list import and a card-reader setup.

  Each is a Path of its own, built the way
  `StatifierExamples.Library.RegistrationSteps` is: a block document of
  three `myapp.step` blocks (`StatifierExamples.Signup.ReturnableStep`) and
  the screens document they name, so each screen offers Back to the step
  before it. Each one runs alone as a durable Journey, started from
  `StatifierExamplesWeb.SettingsLive` and walked on the Journey page.

  ## The one list

  This module is the one place the three are listed. A setup is named by
  two things, and both are here:

    * its **key**, the file stem, which a page carries in `?path=`;
    * its **document id**, the block document's own `id`, which is what a
      parent document names when it runs a setup as a child and what a
      resolver of child documents looks up (`fetch_document/1`).

  ## How a setup finishes

  A setup whose root is a `core.sequence` declares one root outcome,
  `done`, and a document compiled for use as a child finishes with it
  (`outcomes/1`). The catalogue sync and the reading-list import are such
  setups. What happened inside one - which catalogue source, which term -
  is in its `responses`, where each step's press recorded it, and not in
  the outcome: a `myapp.step` finishes as `done` whichever button was
  pressed.

  A setup that should be able to tell its parent how it went has a
  `myapp.setup` root instead (`StatifierExamples.Library.Setup`), which
  declares `done` and the one ending its config names. The card-reader
  setup is one: a Finish on its test-card screen saying the reader read
  nothing ends it with `site_visit_needed`, which `outcomes/1` answers
  beside `done` and the onboarding reads
  (`StatifierExamples.Library.Onboarding`).

  ## What a librarian reads

  Each document's `metadata` description is written for whoever edits the
  document: it names block types and fixture files. The settings page
  draws `description/1` instead, one sentence per setup for the librarian
  choosing which to run. It is kept here, beside the one list, rather than
  in the documents, because which setups a page offers and how it words
  them is this list's, and the document's own description already has a
  reader: the person editing it.

  None of the three is among the fixtures `StatifierExamples.Charts.fixtures/0`
  lists. Like the patron registration steps, each is run as a supplied
  Path: `options/1` is what every `StatifierExamples.Signup.Journey` call
  over it takes.
  """

  alias StatifierBlocks.{Decode, Document}
  alias StatifierExamples.Charts.Subchart

  # `{key, path file, screens file, description}`, in the order a page
  # offers them. Listed rather than globbed, as `StatifierExamples.Library`
  # lists its documents: a stray file in `priv/` should not become a setup.
  @setups [
    {"catalogue_sync", "catalogue_sync.json", "catalogue_sync_screens.json",
     "Keep this branch's catalogue in step: choose where its records come from, how often they sync and who hears when a sync fails."},
    {"reading_list_import", "reading_list_import.json", "reading_list_import_screens.json",
     "Bring in the reading lists local schools send for a term, and choose whether their titles are held at the branch."},
    {"card_reader_setup", "card_reader_setup.json", "card_reader_setup_screens.json",
     "Set up the branch's library-card reader and check it reads a card; a reader that reads nothing is sent for a site visit."}
  ]

  @doc "The setups' keys, in the order a page offers them."
  @spec keys() :: [String.t()]
  def keys, do: Enum.map(@setups, &elem(&1, 0))

  @doc """
  The setup's block document, decoded: `{:ok, document}`, or `:error` for
  a key this module does not list.
  """
  @spec document(String.t()) :: {:ok, Document.t()} | :error
  def document(key) do
    with {:ok, {_key, path_file, _screens_file, _description}} <- setup(key) do
      case Decode.decode(File.read!(fixture(path_file))) do
        {:ok, document} -> {:ok, document}
        {:error, error} -> raise "#{path_file} is not a block document: #{inspect(error)}"
      end
    end
  end

  @doc """
  What the setup does, in one sentence for a librarian (the moduledoc's
  "What a librarian reads"), or `:error` for a key this module does not
  list.
  """
  @spec description(String.t()) :: {:ok, String.t()} | :error
  def description(key) do
    with {:ok, {_key, _path_file, _screens_file, description}} <- setup(key),
         do: {:ok, description}
  end

  @doc """
  The screens document the setup's steps name, decoded: `{:ok, screens}`,
  or `:error` for a key this module does not list.
  """
  @spec screens(String.t()) :: {:ok, map()} | :error
  def screens(key) do
    with {:ok, {_key, _path_file, screens_file, _description}} <- setup(key),
         do: {:ok, screens_file |> fixture() |> File.read!() |> Jason.decode!()}
  end

  @doc """
  The options every `StatifierExamples.Signup.Journey` call over the setup
  takes - its screens document and its Path - or `:error` for a key this
  module does not list.
  """
  @spec options(String.t()) :: {:ok, [screens: map(), path: Document.t()]} | :error
  def options(key) do
    with {:ok, document} <- document(key),
         {:ok, screens} <- screens(key),
         do: {:ok, [screens: screens, path: document]}
  end

  @doc """
  The setup whose block document carries `document_id`, decoded, or
  `:error` for an id none of the three carries. What a parent's child
  resolver answers from.
  """
  @spec fetch_document(String.t()) :: {:ok, Document.t()} | :error
  def fetch_document(document_id) when is_binary(document_id) do
    Enum.find_value(keys(), :error, fn key ->
      case document(key) do
        {:ok, %Document{id: ^document_id} = document} -> {:ok, document}
        _other -> nil
      end
    end)
  end

  @doc """
  The root outcomes the setup's document declares, as its compile for use
  as a child reads them (the moduledoc's "How a setup finishes"): the
  compile `StatifierExamples.Charts.Subchart.child_compile/1` makes, the
  one child recipe.
  """
  @spec outcomes(String.t()) :: {:ok, [String.t()]} | :error
  def outcomes(key) do
    with {:ok, document} <- document(key) do
      {:ok, compiled} = Subchart.child_compile(document)
      {:ok, compiled.interface.declared_outcomes}
    end
  end

  @spec setup(String.t()) ::
          {:ok, {String.t(), String.t(), String.t(), String.t()}} | :error
  defp setup(key) do
    case List.keyfind(@setups, key, 0) do
      nil -> :error
      setup -> {:ok, setup}
    end
  end

  @spec fixture(String.t()) :: Path.t()
  defp fixture(file),
    do: Path.join([Application.app_dir(:statifier_examples), "priv", "fixtures", file])
end
