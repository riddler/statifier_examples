defmodule StatifierExamples.CardAuth.ManualFlag do
  @moduledoc """
  `myapp.manual_flag`: marks the transaction for a human to look at.

  A leaf step naming the `myapp:manual_flag` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:manual_flag",
    palette: %{
      label: "Manual flag",
      group: "Card processing",
      description: "Marks the transaction for a human to look at.",
      icon: "flag",
      keywords: ["manual", "flag", "review"],
      order: 3,
      accent_token: Step.accent_token()
    }
end
