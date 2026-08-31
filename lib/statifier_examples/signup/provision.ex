defmodule StatifierExamples.Signup.Provision do
  @moduledoc """
  `myapp.provision`: creates the account's workspace once signup completes.

  The wizard's last real step, and the one with nothing to configure beyond
  the handler it names: what a workspace is made of is the host's business,
  not the chart's.
  """

  alias StatifierExamples.Charts.Step

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:provision",
    produces: :unknown,
    palette: %{
      label: "Provision",
      group: "Signup wizard",
      description: "Creates the account's workspace once signup completes.",
      icon: "sparkles",
      keywords: ["provision", "workspace", "create"],
      order: 1,
      accent_token: Step.accent_token()
    }
end
