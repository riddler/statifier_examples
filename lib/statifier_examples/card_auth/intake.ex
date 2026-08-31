defmodule StatifierExamples.CardAuth.Intake do
  @moduledoc """
  `myapp.intake`: accepts the incoming payment request and normalizes it.

  A leaf step naming the `myapp:intake` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:intake",
    produces: "myapp.payment_request",
    palette: %{
      label: "Intake",
      group: "Card processing",
      description: "Accepts the incoming payment request and normalizes it.",
      icon: "inbox",
      keywords: ["intake", "request", "normalize"],
      order: 0,
      accent_token: Step.accent_token()
    }
end
