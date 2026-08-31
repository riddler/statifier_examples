defmodule StatifierExamples.CardAuth.Park do
  @moduledoc """
  `myapp.park`: puts the work on a queue and waits for a human.

  A leaf step naming the `myapp:park` handler, with one field of its own -
  the `queue` a reviewer picks the work up from. It runs nothing itself:
  `StatifierExamples.CardAuth.Handlers` is what this app registers to
  answer the call.
  """

  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @queue_message "must be a bare lowercase identifier, like manual_review"

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:park",
    fields: [
      %{
        key: "queue",
        type: :string,
        label: "Queue",
        required?: true,
        default: "manual_review"
      }
    ],
    palette: %{
      label: "Park",
      group: "Card processing",
      description: "Puts the work on a queue and waits for a human.",
      icon: "pause",
      keywords: ["park", "queue", "hold", "wait"],
      order: 6,
      accent_token: Step.accent_token()
    }

  @doc """
  The base's `invoke_type` check, plus this type's own: a queue nobody can
  name is not a queue, so `queue` is required and has to be a bare
  lowercase identifier.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_identifier(config, "queue", @queue_message)
    |> InvokeStep.verdict()
  end
end
