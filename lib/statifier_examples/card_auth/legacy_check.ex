defmodule StatifierExamples.CardAuth.LegacyCheck do
  @moduledoc """
  `myapp.legacy_check`: runs the older velocity ruleset over the
  transaction.

  A leaf step naming the `myapp:legacy_check` handler and waiting for it to
  answer, the same shape the other ten card-processing types have. The name
  is the ruleset's age, not this type's: a host that has carried a rule
  engine for a while has one of these, and the low-risk arm of the fraud
  branch is where the card-processing document runs it.

  ## It used to be the type nobody registered

  Through campaign 032 this type was deliberately absent from
  `StatifierExamples.CardAuth.block_types/0` while `card_processing` named
  it at depth 7, so that the editor's unavailable-block chrome and the
  compiler's `unknown_block_type` finding were exercised on a document a
  reader could open. What that cost was larger than what it bought: the
  compiler reports findings from the FIRST FAILING STAGE only, so an
  unresolvable type at depth 7 masked every later stage of the shipped
  document - the type refusals the card-processing domain is authored to
  demonstrate could be asserted in the suite but never seen in the editor
  the app exists to show off (se-bv9, ruled 2026-09-06).

  So the reference embedder registers what its own document names, and the
  document compiles clean. The unavailable-block case belongs to
  `statifier_blocks`, whose chrome it is, and is covered there.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:legacy_check",
    palette: %{
      label: "Legacy velocity check",
      group: "Card processing",
      description: "Runs the older velocity ruleset over the transaction.",
      icon: "archive-box",
      keywords: ["legacy", "velocity", "ruleset"],
      order: 9,
      accent_token: Step.accent_token()
    }
end
