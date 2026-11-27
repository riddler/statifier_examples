defmodule StatifierExamples.Library do
  @moduledoc """
  The library world's example documents: a library loan and a patron
  registration, which share one world - patron, copy, loan, hold, branch.

  They are the two teaching domains this app's Plan view is read against,
  and they are written from `core.*` blocks alone. That is deliberate: a
  reader learning the vocabulary sees the vocabulary, and the library world
  has no calls of its own for this app to register a handler for. Each one
  carries a branch with an empty outcome slot, because a projection that
  draws the document has to say where an author left a slot empty rather
  than leave it out.

  Listed here rather than in `StatifierExamples.Charts`, which appends
  them to the fixtures every page offers, for the reason the card and
  signup domains each keep their own list: which documents a domain ships
  is a fact about the domain.

  The one block type the library world registers, `myapp.setup`
  (`block_types/0`), is used by neither document: it is the root of a
  branch library setup that can end more than one way
  (`StatifierExamples.Library.Setups`).
  """

  alias StatifierExamples.Charts.Fixture
  alias StatifierExamples.Library.Setup

  # `{key, file}`. Listed rather than globbed, as `StatifierExamples.CardAuth`
  # lists its own: a stray file in `priv/` should not silently become an
  # example.
  @documents [
    {"library_loan", "library_loan.json"},
    {"patron_registration", "patron_registration.json"}
  ]

  @doc """
  The library world's example documents, decoded, in the order a page
  should offer them.
  """
  @spec fixtures() :: [Fixture.t()]
  def fixtures, do: Enum.map(@documents, fn {key, file} -> Fixture.load!(key, file) end)

  @doc """
  The library world's own block type, as a `type_name => module` map: the
  root a branch library setup that can end more than one way is built on
  (`StatifierExamples.Library.Setup`).
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types, do: %{"myapp.setup" => Setup}
end
