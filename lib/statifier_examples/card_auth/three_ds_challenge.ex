defmodule StatifierExamples.CardAuth.ThreeDsChallenge do
  @moduledoc """
  `myapp.three_ds_challenge`: sends the cardholder a step-up authentication challenge.

  Stored at `type_version` 2 in this app's card-processing fixture, so
  the block resolves without migrating.

  A leaf step naming the `myapp:three_ds` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Charts.Step

  @invoke_type "myapp:three_ds"

  @doc "The invoke type this step names when its config does not say otherwise."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl true
  def current_version, do: 2

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config), do: Step.config_schema(@invoke_type)

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> Step.verdict()
  end

  @impl true
  def io(_config), do: Step.io()

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry do
    Step.palette_entry(%{
      label: "3-D Secure",
      group: "Card processing",
      description: "Sends the cardholder a step-up authentication challenge.",
      icon: "device-phone-mobile",
      keywords: ["3ds", "challenge", "step-up"],
      order: 5
    })
  end

  @impl true
  def emit(block, context), do: Step.emit(block, context, @invoke_type)
end
