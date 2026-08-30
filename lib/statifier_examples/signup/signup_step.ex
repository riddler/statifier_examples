defmodule StatifierExamples.Signup.SignupStep do
  @moduledoc """
  `myapp.signup_step`: collects one step of the signup wizard.

  Five steps in a fixed order - account, send_verification, company_details,
  preferences, confirm - and one handler behind all of them. Which step a
  block collects is config rather than five block types, because the shape
  of the work is identical and the palette is the poorer for five cards
  that differ by a word.

  The step name is sent to the handler as a literal `<param>`, so
  `myapp:signup` learns which form to put up without reading anything out of
  the datamodel.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierExamples.Signup.Step

  @invoke_type "myapp:signup"

  @steps ["account", "send_verification", "company_details", "preferences", "confirm"]

  @doc "The wizard's steps, in the order an author meets them."
  @spec steps() :: [String.t()]
  def steps, do: @steps

  @impl true
  def current_version, do: 1

  @doc "A leaf: the wizard's shape is the chart around this block, not inside it."
  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config),
    do:
      Step.config_schema(@invoke_type, [
        %{
          key: "step",
          type: {:select, Enum.map(@steps, &{&1, label(&1)})},
          label: "Wizard step",
          required?: true,
          default: "account"
        }
      ])

  @impl true
  def validate_config(config) do
    []
    |> Step.check_invoke_type(config)
    |> check_step(config)
    |> Step.verdict()
  end

  @spec check_step([Step.finding()], Block.config()) :: [Step.finding()]
  defp check_step(findings, config) do
    if Map.get(config, "step") in @steps do
      findings
    else
      [{"step", "pick one of #{Enum.join(@steps, ", ")}"} | findings]
    end
  end

  @doc """
  A step with two outcomes, so `produces` is `:unknown` for the reason
  `core.invoke` declares it. `consumes` is absent: what the wizard collects
  arrives from the person filling the form in, not from the type flow.
  """
  @impl true
  def io(_config), do: %{kinds: [:step], produces: :unknown}

  @impl true
  def outcomes(_config), do: Step.outcomes()

  @impl true
  def palette_entry,
    do: %{
      label: "Signup step",
      group: "Signup wizard",
      description: "Collects one step of the signup wizard.",
      icon: "user-plus",
      keywords: ["signup", "step", "wizard", "form"],
      order: 0,
      accent_token: Step.accent_token()
    }

  @impl true
  def emit(%Block{config: config} = block, context) do
    Step.emit(block, context, [
      Step.literal_param("step", Map.get(config, "step", "account"), "step")
    ])
  end

  # "send_verification" reads as "send verification" on a select control.
  @spec label(String.t()) :: String.t()
  defp label(step), do: String.replace(step, "_", " ")
end
