defmodule StatifierExamples.DivergentDocument do
  @moduledoc """
  A test-only block document whose editor findings count EXCEEDS the
  number the compiler reports for it.

  The two numbers are derived by different things - the compiler reports
  what its stages found, and `StatifierBlocks.Editor`'s view model derives
  findings of its own on top of whatever the host hands in - so a document
  where they disagree is what proves the header reads the seam rather than
  the compiler. Every document this app SHIPS is authored to compile, and
  since `se-bv9` registered `myapp.legacy_check` every one of them measures
  the same number from both sources. The gap has to be constructed.

  It is constructed by retiring a block type: the shipped card-processing
  document is re-typed at one block to a name no palette entry answers.
  That is the same shape the gap used to have - the compiler stops at the
  resolution stage and reports what it found there, while the view model
  derives a resolution finding of its own for the block it cannot resolve -
  and it is deliberately not a shipped document, so registering the type
  cannot close it again.

  The re-typing goes through `Document.to_json/1` and `Document.from_json/1`
  rather than reaching into the struct: the result is a document the real
  decoder produced, and a decoder that stopped accepting this shape would
  say so here rather than leaving a hand-built struct nothing validates.

  `declare/0` and `datamodel/0` come from the source fixture unchanged,
  because the host compiles a document with the fixture's environment and
  this has to be compiled the same way to measure the same thing.
  """

  alias StatifierBlocks.Document
  alias StatifierExamples.Charts

  @source_key "card_processing"
  @registered_type "myapp.legacy_check"
  @retired_type "myapp.retired_velocity_check"

  @doc """
  The block type the constructed document names and no palette entry
  answers.
  """
  @spec retired_type() :: String.t()
  def retired_type, do: @retired_type

  @doc """
  The shipped fixture the construction starts from.
  """
  @spec fixture() :: Charts.Fixture.t()
  def fixture do
    {:ok, fixture} = Charts.fixture(@source_key)

    fixture
  end

  @doc """
  The constructed document: the source fixture's, with its one
  `myapp.legacy_check` block re-typed to a name the palette does not carry.
  """
  @spec document() :: Document.t()
  def document do
    {:ok, document} =
      fixture().document
      |> Document.to_json()
      |> String.replace(~s("#{@registered_type}"), ~s("#{@retired_type}"))
      |> Document.from_json()

    document
  end
end
