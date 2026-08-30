defmodule StatifierExamples.Signup.Provision do
  @moduledoc """
  `myapp.provision`: creates the account's workspace once signup completes.

  The wizard's last real step, and the one with nothing to configure beyond
  the handler it names: what a workspace is made of is the host's business,
  not the chart's.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierExamples.Signup.Step

  @invoke_type "myapp:provision"

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

  @doc "`StatifierExamples.Signup.SignupStep.io/1`'s reasoning, unchanged."
  @impl true
  def io(_config), do: %{kinds: [:step], produces: :unknown}

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry,
    do: %{
      label: "Provision",
      group: "Signup wizard",
      description: "Creates the account's workspace once signup completes.",
      icon: "sparkles",
      keywords: ["provision", "workspace", "create"],
      order: 1,
      accent_token: Step.accent_token()
    }

  @impl true
  def emit(block, context), do: Step.emit(block, context, [])
end
