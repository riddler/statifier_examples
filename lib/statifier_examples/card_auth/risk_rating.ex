defmodule StatifierExamples.CardAuth.RiskRating do
  @moduledoc """
  `myapp.risk_rating`: scores the transaction against the fraud model.

  A leaf step naming the `myapp:risk_rating` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:risk_rating",
    produces: "myapp.risk_rating",
    palette: %{
      label: "Risk rating",
      group: "Card processing",
      description: "Scores the transaction against the fraud model.",
      icon: "shield-exclamation",
      keywords: ["risk", "fraud", "rating"],
      order: 2,
      accent_token: Step.accent_token()
    }
end
