defmodule StatifierExamples.CardAuth do
  @moduledoc """
  The card-processing example domain: its block types, their invoke
  handlers, and the fixture document written against them.

  The vocabulary is one of the family's two canonical example domains. It
  models no real payment processor: every value that appears in a fixture
  or a seed here is fictional.

  ## Ten types, one shape

  Every type is a leaf step that **names** a `myapp:*` invoke type and
  compiles to a call the host answers - `StatifierExamples.Charts.Step`
  holds the shape they share, and `StatifierExamples.CardAuth.Handlers`
  holds the other half of the two-registry seam. Two of them carry
  something the others do not:
  `StatifierExamples.CardAuth.Authorize` is at version 2 and migrates a
  version 1 config, and `StatifierExamples.CardAuth.ThreeDsChallenge` is
  at version 2 with no migration, because the fixture stores it there
  already.

  `myapp.notify` is **not** here. It belongs to neither domain and lives
  under `StatifierExamples.Charts.Messaging`.

  ## One type is missing on purpose

  The fixture names `myapp.legacy_check` at depth 7 and this module does
  not register it. That is ADR-0005 decision 12's case - the block whose
  type does not resolve - and registering it would delete the test.
  """

  alias StatifierExamples.CardAuth.{
    Authorize,
    BalanceCheck,
    Capture,
    Intake,
    ManualFlag,
    Park,
    Receipt,
    ResolveReview,
    RiskRating,
    ThreeDsChallenge
  }

  alias StatifierExamples.Charts.Fixture

  # `{key, file}`. Listed rather than globbed: which documents this app ships
  # is a fact worth reading in the source, and a stray file in `priv/` should
  # not silently become an example.
  @documents [{"card_processing", "card_processing.json"}]

  @block_types %{
    "myapp.authorize" => Authorize,
    "myapp.balance_check" => BalanceCheck,
    "myapp.capture" => Capture,
    "myapp.intake" => Intake,
    "myapp.manual_flag" => ManualFlag,
    "myapp.park" => Park,
    "myapp.receipt" => Receipt,
    "myapp.resolve_review" => ResolveReview,
    "myapp.risk_rating" => RiskRating,
    "myapp.three_ds_challenge" => ThreeDsChallenge
  }

  @doc """
  The card-processing block types, as a `type_name => module` map suitable
  for `StatifierBlocks.Palette.new/2`.
  """
  @spec block_types() :: %{optional(String.t()) => module()}
  def block_types, do: @block_types

  @doc """
  The card-processing domain's example documents, decoded, in the order a
  page should offer them.
  """
  @spec fixtures() :: [Fixture.t()]
  def fixtures, do: Enum.map(@documents, fn {key, file} -> Fixture.load!(key, file) end)
end
