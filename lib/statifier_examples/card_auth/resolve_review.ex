defmodule StatifierExamples.CardAuth.ResolveReview do
  @moduledoc """
  `myapp.resolve_review`: applies the reviewer's decision and continues.

  A leaf step naming the `myapp:resolve_review` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:resolve_review",
    palette: %{
      label: "Resolve review",
      group: "Card processing",
      description: "Applies the reviewer's decision and continues.",
      icon: "check",
      keywords: ["resolve", "review", "decision"],
      order: 7,
      accent_token: Step.accent_token()
    }
end
