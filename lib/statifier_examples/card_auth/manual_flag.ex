defmodule StatifierExamples.CardAuth.ManualFlag do
  @moduledoc """
  `myapp.manual_flag`: marks the transaction for a human to look at.

  A leaf step naming the `myapp:manual_flag` handler and waiting for it to
  answer. It runs nothing itself: `StatifierExamples.CardAuth.Handlers` is
  what this app registers to answer the call.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Charts.Step

  @invoke_type "myapp:manual_flag"

  @doc "The invoke type this step names when its config does not say otherwise."
  @spec invoke_type() :: String.t()
  def invoke_type, do: @invoke_type

  @impl true
  def current_version, do: 1

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
      label: "Manual flag",
      group: "Card processing",
      description: "Marks the transaction for a human to look at.",
      icon: "flag",
      keywords: ["manual", "flag", "review"],
      order: 3
    })
  end

  @impl true
  def emit(block, context), do: Step.emit(block, context, @invoke_type)
end
