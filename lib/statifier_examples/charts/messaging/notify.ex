defmodule StatifierExamples.Charts.Messaging.Notify do
  @moduledoc """
  `myapp.notify`: sends one templated message.

  A leaf step naming the `myapp:notify` handler, with the `template` the
  message is rendered from. It runs nothing itself:
  `StatifierExamples.Charts.Messaging.Handlers` is what this app registers
  to answer the call.

  It files under its own palette heading rather than under either example
  domain, because both of them notify: the card-processing fixture uses it
  six times and the signup wizard will use it too.
  """

  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @template_message "must be a bare lowercase identifier, like receipt_ready"

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:notify",
    fields: [
      %{
        key: "template",
        type: :string,
        label: "Template",
        required?: true,
        default: ""
      }
    ],
    palette: %{
      label: "Notify",
      group: "Messaging",
      description: "Sends one templated message.",
      icon: "megaphone",
      keywords: ["notify", "message", "template", "email"],
      order: 0,
      accent_token: Step.accent_token()
    }

  @doc """
  The base's `invoke_type` check, plus the template this type renders
  from: a message with no template is not a message.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_identifier(config, "template", @template_message)
    |> InvokeStep.verdict()
  end
end
