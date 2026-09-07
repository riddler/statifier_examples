defmodule StatifierExamples.TwoStageDocument do
  @moduledoc """
  A test-only block document carrying one defect from each compiler stage,
  on two different blocks.

  `statifier_blocks` runs Config and Structure as a pair rather than in
  sequence: a block whose config the first stage refused is skipped by id,
  and the walk continues past it, so a mis-typed field on one card no
  longer hides an unsatisfied read on another. The refusal carries the
  union. This app is the reference embedder, so the property is asserted
  here on a document made of the types it registers - which means the
  document has to hold both defects at once, and neither of them can be
  produced through the editor's config form: a config the form refuses is
  parked as a draft rather than committed, so the compiler never sees it.

  The two defects are one per stage, and deliberately far apart in the
  tree:

    * `blk_cp_capture_retry_call` - a `myapp.capture` deep inside the
      retry arm - gets `retries: true`. `StatifierExamples.CardAuth.Capture`
      refuses a `retries` that is not a whole number, and `true` is the
      value that separates `is_integer/1` from a bounds check written with
      comparison operators.
    * `blk_cp_receipt` - the receipt in the tail - has its `settlement`
      read pointed at the subject path, where `myapp.intake` left a
      `cards.credit_txn`. A transaction is not a settlement, and there is
      no widening between two declared records, so the read is refused.

  Both edits go through `Document.to_json/1` and `Document.from_json/1`
  rather than reaching into the struct, for the reason
  `StatifierExamples.DivergentDocument` states: the result is a document
  the real decoder produced, and a decoder that stopped accepting this
  shape would say so here rather than leaving a hand-built struct nothing
  validates. Each replacement is asserted unique in the source before it
  is made, so a fixture edit that moved either value fails loudly instead
  of silently constructing a document with one defect.

  `fixture/0` is the shipped card-processing fixture unchanged, because
  the page compiles a document with the fixture's own datamodel and this
  has to be compiled the same way to be refused the same way.
  """

  alias StatifierBlocks.Document
  alias StatifierExamples.Charts

  @source_key "card_processing"

  @config_block "blk_cp_capture_retry_call"
  @read_block "blk_cp_receipt"

  @config_edit {~s("retries":3), ~s("retries":true)}
  @read_edit {~s("settlement":"cards.settlement"), ~s("settlement":"cards.current_txn")}

  @doc "The block whose config the Config stage refuses."
  @spec config_block() :: String.t()
  def config_block, do: @config_block

  @doc "The block whose declared read the Structure stage refuses."
  @spec read_block() :: String.t()
  def read_block, do: @read_block

  @doc """
  The shipped fixture the construction starts from, whose datamodel the
  refusals are measured against.
  """
  @spec fixture() :: Charts.Fixture.t()
  def fixture do
    {:ok, fixture} = Charts.fixture(@source_key)

    fixture
  end

  @doc "The constructed document: the shipped one with both defects in it."
  @spec document() :: Document.t()
  def document do
    {:ok, document} =
      fixture().document
      |> Document.to_json()
      |> replace_once(@config_edit)
      |> replace_once(@read_edit)
      |> Document.from_json()

    document
  end

  # A replacement that is refused unless the source says the thing it is
  # about to change exactly once. A fixture edit that renamed a field or
  # moved a value would otherwise leave this document with one defect and
  # the assertions measuring the wrong property.
  @spec replace_once(String.t(), {String.t(), String.t()}) :: String.t()
  defp replace_once(json, {from, to}) do
    case json |> String.split(from) |> length() do
      2 ->
        String.replace(json, from, to)

      n ->
        raise "#{inspect(from)} appears #{n - 1} times in the #{@source_key} document, expected once"
    end
  end
end
