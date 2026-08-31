defmodule StatifierExamples.CardAuth.BalanceCheck do
  @moduledoc """
  `myapp.balance_check`: reads the available balance on the funding source.

  A leaf step naming the `myapp:balance_check` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:balance_check",
    produces: "myapp.balance",
    palette: %{
      label: "Balance check",
      group: "Card processing",
      description: "Reads the available balance on the funding source.",
      icon: "scale",
      keywords: ["balance", "funds", "available"],
      order: 4,
      accent_token: Step.accent_token()
    }
end
