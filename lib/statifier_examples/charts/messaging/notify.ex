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

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Charts.Step

  @invoke_type "myapp:notify"

  @template_message "must be a bare lowercase identifier, like receipt_ready"

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
        key: "template",
        type: :string,
        label: "Template",
        required?: true,
        default: ""
      }
    ])
  end

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> Step.check_identifier(config, "template", @template_message)
    |> Step.verdict()
  end

  @impl true
  def io(_config), do: Step.io()

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry do
    Step.palette_entry(%{
      label: "Notify",
      group: "Messaging",
      description: "Sends one templated message.",
      icon: "megaphone",
      keywords: ["notify", "message", "template", "email"],
      order: 0
    })
  end

  @impl true
  def emit(block, context), do: Step.emit(block, context, @invoke_type)
end
