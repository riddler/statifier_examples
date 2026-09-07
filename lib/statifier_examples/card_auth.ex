defmodule StatifierExamples.CardAuth do
  @moduledoc """
  The card-processing example domain: its block types, their invoke
  handlers, and the fixture documents written against them.

  Two documents, and the second is the first one caught mid-authoring:
  `card_processing_sketch` parks the tail the author already knows in a
  `core.drafts` shelf and marks the middle they have not decided with a
  `core.placeholder`, which is the surface `docs/demo-script.md`'s
  sink-backwards beat is read off (se-ihm).

  The vocabulary is one of the family's two canonical example domains. It
  models no real payment processor: every value that appears in a fixture
  or a seed here is fictional.

  ## Eleven leaf types, one shape - and one composite

  Every type is a leaf step that **names** a `myapp:*` invoke type and
  compiles to a call the host answers - `StatifierBlocks.InvokeStep`, over
  the `use StatifierBlocks.BlockType` defaults layer, holds the shape they
  share, and `StatifierExamples.CardAuth.Handlers` holds the other half of
  the two-registry seam. Two of them carry something the others do not:
  `StatifierExamples.CardAuth.Authorize` is at version 2 and migrates a
  version 1 config, and `StatifierExamples.CardAuth.ThreeDsChallenge` is
  at version 2 with no migration, because the fixture stores it there
  already.

  `myapp.notify` is **not** here. It belongs to neither domain and lives
  under `StatifierExamples.Charts.Messaging`.

  ## The twelfth type is a composite

  `myapp.authorize_with_deadline` is declared the other way -
  `use StatifierBlocks.Composite`, params plus a pure subtree - and it stands
  for the three-lane authorization arrangement `card_processing.json` spells
  out by hand. `StatifierExamples.CardAuth.AuthorizeWithDeadline` carries the
  reasoning, and `card_processing_composite` is the document that reads it.
  The hand-written arrangement stays exactly as it was: two documents over
  one arrangement is the comparison, and rewriting the first would destroy
  it.

  ## The order the drawer lists them in

  A palette entry's `order` is a position inside its group, and
  `statifier_blocks` refuses two entries in one group claiming the same
  number - so the twelve numbers below are a list somebody has to write
  down, and this is where it is written. It was an accident until
  2026-09-07: `myapp.intake` claimed 0 alongside `myapp.authorize`, and
  `se-2ox` moved it to 10 - the next free number - to make the palette
  legal, which left the domain's first step listed last. `se-0u1` replaced
  that with a decision.

  The run is four passages, and each is in the order it happens:

  | Order | Type | Why here |
  |---|---|---|
  | 0 | `myapp.intake` | The step that seeds `cards.current_txn`; every later step reads it, so it is the one an author reaches for first |
  | 1 | `myapp.authorize` | The happy path, in the order it runs |
  | 2 | `myapp.capture` | " |
  | 3 | `myapp.receipt` | " - the terminal step |
  | 4 | `myapp.risk_rating` | The checks that inform the authorization decision |
  | 5 | `myapp.balance_check` | " |
  | 6 | `myapp.three_ds_challenge` | " |
  | 7 | `myapp.manual_flag` | The human-review path, in the order it runs |
  | 8 | `myapp.park` | " |
  | 9 | `myapp.resolve_review` | " |
  | 10 | `myapp.legacy_check` | The older ruleset, last of the leaves because it is what a flow is being moved off |
  | 11 | `myapp.authorize_with_deadline` | The composite, last: it stands for an arrangement of the types above it, so it reads as a summary of the group rather than a member of it |

  The numbers are contiguous from 0 on purpose - a gap is a place a later
  entry lands in silently - so adding a type means renumbering its
  passage's tail, and saying in this table where it belongs.
  `StatifierExamples.ChartsTest` asserts the palette spells exactly this
  order, so a renumbering that does not come back here goes red.

  ## Every type the documents name is registered here

  Through campaign 032 `myapp.legacy_check` was left out on purpose, so
  that ADR-0005 decision 12's case - the block whose type does not
  resolve - was exercised at depth 7 of `card_processing`. It is
  registered as of 2026-09-06 (se-bv9): the compiler reports findings
  from the first failing stage only, so an unresolvable type in the
  shipped document masked every later stage of it in the editor, and the
  domain's type refusals could be asserted in the suite but never seen.
  The unavailable-block chrome is `statifier_blocks`' and is covered
  there. `StatifierExamples.CardAuth.LegacyCheck` carries the longer
  version.
  """

  alias StatifierExamples.CardAuth.{
    Authorize,
    AuthorizeWithDeadline,
    BalanceCheck,
    Capture,
    Intake,
    LegacyCheck,
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
  @documents [
    {"card_processing", "card_processing.json"},
    {"card_processing_sketch", "card_processing_sketch.json"},
    {"card_processing_composite", "card_processing_composite.json"}
  ]

  @block_types %{
    "myapp.authorize" => Authorize,
    "myapp.authorize_with_deadline" => AuthorizeWithDeadline,
    "myapp.balance_check" => BalanceCheck,
    "myapp.capture" => Capture,
    "myapp.intake" => Intake,
    "myapp.legacy_check" => LegacyCheck,
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
