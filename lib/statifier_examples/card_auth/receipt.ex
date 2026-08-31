defmodule StatifierExamples.CardAuth.Receipt do
  @moduledoc """
  `myapp.receipt`: renders the receipt for the completed transaction.

  A leaf step naming the `myapp:receipt` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:receipt",
    palette: %{
      label: "Receipt",
      group: "Card processing",
      description: "Renders the receipt for the completed transaction.",
      icon: "document-text",
      keywords: ["receipt", "summary", "document"],
      order: 8,
      accent_token: Step.accent_token()
    }
end
