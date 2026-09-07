defmodule StatifierExamples.CardAuth.BalanceCheck do
  @moduledoc """
  `myapp.balance_check`: reads the available balance on the funding source.

  A leaf step naming the `myapp:balance_check` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.

  ## Why this type declares no `produces`

  It used to declare one, back when `produces` was a claim about the block
  after this one (`statifier_blocks` ADR-0003). ADR-0011 supersedes that:
  a `produces` is now sugar for a write at the document's **subject path**,
  and this step does not put its answer there - it leaves the transaction
  where it is and the chart reads what came back from its own root. A
  declaration kept out of habit would have said that everything after this
  step is looking at a balance rather than at a card, and in the
  card-processing document two lanes said it at once about two different
  things, which is how the subject dropped to `unknown` halfway down
  the flow.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:balance_check",
    palette: %{
      label: "Balance check",
      group: "Card processing",
      description: "Reads the available balance on the funding source.",
      icon: "scale",
      keywords: ["balance", "funds", "available"],
      order: 5,
      accent_token: Step.accent_token()
    }
end
