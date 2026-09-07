defmodule StatifierExamples.CardAuth.Intake do
  @moduledoc """
  `myapp.intake`: accepts the incoming payment request and normalizes it.

  A leaf step naming the `myapp:intake` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.

  ## This type is where the card-processing documents start, so it names
  ## the subject

  `statifier_blocks` ADR-0011 gives a one-subject document one path
  everything in it is about, and the **entry block** - the first block of
  the root's `body` slot - is what names it, with `subject:` on its
  palette entry. Both card-processing documents this app ships start
  here, so this is the type that carries it: `cards.current_txn`.

  `produces` is then sugar over that path rather than a claim floating
  free of one: intake normalizes an incoming payment request into a
  transaction, and what it leaves at the subject is a
  `cards.credit_txn` - the record `priv/fixtures/card_processing.datamodel.json`
  declares. Every read further down the flow is checked against that,
  which is what makes the capture step's read satisfied and the receipt
  step's refused.

  The spelling moved from `myapp.payment_request` when the type became a
  write at a real path: an opaque name nothing declared could only ever
  be compared by identity, so it said nothing a reader or a check could
  use. A declared name reads as its label - "Credit card transaction" -
  in the editor's findings and its Datamodel tab.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:intake",
    produces: "cards.credit_txn",
    palette: %{
      label: "Intake",
      subject: "cards.current_txn",
      group: "Card processing",
      description: "Accepts the incoming payment request and normalizes it.",
      icon: "inbox",
      keywords: ["intake", "request", "normalize"],
      # First in the group, which is a decision rather than an accident:
      # intake is the step that seeds `cards.current_txn`, and every later
      # step in the domain reads it. The group's whole order and the
      # reasoning behind it are in `StatifierExamples.CardAuth`'s moduledoc,
      # and `StatifierExamples.ChartsTest` asserts the palette still spells
      # it.
      order: 0,
      accent_token: Step.accent_token()
    }
end
