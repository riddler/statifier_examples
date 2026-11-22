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

  Each document's root is a `core.sequence`, so it declares one root
  outcome, `done`, and a document compiled for use as a child finishes
  with it (`outcomes/1`). What happened inside a setup - which catalogue
  source, whether the reader read a test card - is in its `responses`,
  where each step's press recorded it, and not in the outcome: a
  `myapp.step` finishes as `done` whichever button was pressed.

  None of the three is among the fixtures `StatifierExamples.Charts.fixtures/0`
  lists. Like the patron registration steps, each is run as a supplied
  Path: `options/1` is what every `StatifierExamples.Signup.Journey` call
  over it takes.
  """

  alias StatifierBlocks.{Compiler, Decode, Document}
  alias StatifierExamples.Charts

  # `{key, path file, screens file}`, in the order a page offers them.
  # Listed rather than globbed, as `StatifierExamples.Library` lists its
  # documents: a stray file in `priv/` should not become a setup.
  @setups [
    {"catalogue_sync", "catalogue_sync.json", "catalogue_sync_screens.json"},
    {"reading_list_import", "reading_list_import.json", "reading_list_import_screens.json"},
    {"card_reader_setup", "card_reader_setup.json", "card_reader_setup_screens.json"}
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
    with {:ok, {_key, path_file, _screens_file}} <- setup(key) do
      case Decode.decode(File.read!(fixture(path_file))) do
        {:ok, document} -> {:ok, document}
        {:error, error} -> raise "#{path_file} is not a block document: #{inspect(error)}"
      end
    end
  end

  @doc """
  The screens document the setup's steps name, decoded: `{:ok, screens}`,
  or `:error` for a key this module does not list.
  """
  @spec screens(String.t()) :: {:ok, map()} | :error
  def screens(key) do
    with {:ok, {_key, _path_file, screens_file}} <- setup(key),
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
  as a child reads them (the moduledoc's "How a setup finishes").
  """
  @spec outcomes(String.t()) :: {:ok, [String.t()]} | :error
  def outcomes(key) do
    with {:ok, document} <- document(key) do
      {:ok, compiled} =
        Compiler.compile(document, Charts.palette(),
          known_invoke_types: Charts.invoke_types(),
          child_use: true
        )

      {:ok, compiled.interface.declared_outcomes}
    end
  end

  @spec setup(String.t()) :: {:ok, {String.t(), String.t(), String.t()}} | :error
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
