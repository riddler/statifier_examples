defmodule StatifierExamples.CardAuth.Park do
  @moduledoc """
  `myapp.park`: puts the work on a queue and waits for a human.

  A leaf step naming the `myapp:park` handler, with one field of its own -
  the `queue` a reviewer picks the work up from. It runs nothing itself:
  `StatifierExamples.CardAuth.Handlers` is what this app registers to
  answer the call.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Charts.Step

  @invoke_type "myapp:park"

  @queue_message "must be a bare lowercase identifier, like manual_review"

  @doc "The invoke type this step names when its config does not say otherwise."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config) do
    Step.config_schema(@invoke_type, [
      %{
        key: "queue",
        type: :string,
        label: "Queue",
        required?: true,
        default: "manual_review"
      }
    ])
  end

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> Step.check_identifier(config, "queue", @queue_message)
    |> Step.verdict()
  end

  @impl true
  def io(_config), do: Step.io()

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry do
    Step.palette_entry(%{
      label: "Park",
      group: "Card processing",
      description: "Puts the work on a queue and waits for a human.",
      icon: "pause",
      keywords: ["park", "queue", "hold", "wait"],
      order: 6
    })
  end

  @impl true
  def emit(block, context), do: Step.emit(block, context, @invoke_type)
end
