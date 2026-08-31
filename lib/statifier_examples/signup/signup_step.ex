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

  What comes back goes wherever the block's optional `assign_to` says, on
  the shape `StatifierBlocks.Core.Invoke` spells for the same key. That is
  how the wizard's plan branch gets something to guard on: the account
  step writes the answers to `signup`, and the branch downstream reads
  `signup.plan` and `signup.seats` out of them. A step that keeps nothing
  - the verification mail, the preferences - leaves the key empty and
  writes nothing.
  """

  alias StatifierBlocks.{Block, BlockType, InvokeStep}
  alias StatifierExamples.Charts.Step

  @steps ["account", "send_verification", "company_details", "preferences", "confirm"]

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:signup",
    produces: :unknown,
    fields: [
      %{
        key: "step",
        type: {:select, Enum.map(@steps, &{&1, String.replace(&1, "_", " ")})},
        label: "Wizard step",
        required?: true,
        default: "account"
      },
      %{
        key: "assign_to",
        type: :string,
        label: "Write the answers to",
        required?: false,
        default: "",
        datamodel_path?: true
      }
    ],
    palette: %{
      label: "Signup step",
      group: "Signup wizard",
      description: "Collects one step of the signup wizard.",
      icon: "user-plus",
      keywords: ["signup", "step", "wizard", "form"],
      order: 0,
      accent_token: Step.accent_token()
    }

  @doc "The wizard's steps, in the order an author meets them."
  @spec steps() :: [String.t()]
  def steps, do: @steps

  @doc """
  The base's `invoke_type` and `assign_to` checks, plus the one field this
  type adds.

  `produces` stays `:unknown` for the reason `core.invoke` declares it,
  even though `assign_to` now writes the answer somewhere: which keys a
  step comes back with is a fact about the handler the deployment
  registered, and a block type does not know it.
  """
  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> check_step(config)
    |> InvokeStep.check_assign_to(config)
    |> InvokeStep.verdict()
  end

  @spec check_step([BlockType.finding()], Block.config()) :: [BlockType.finding()]
  defp check_step(findings, config) do
    if Map.get(config, "step") in @steps do
      findings
    else
      [{"step", "pick one of #{Enum.join(@steps, ", ")}"} | findings]
    end
  end

  @doc """
  The base's emission with the step name sent as a literal `<param>`, so
  `myapp:signup` learns which form to put up without reading anything out
  of the datamodel.
  """
  @impl StatifierBlocks.BlockType
  def emit(%Block{config: config} = block, context) do
    InvokeStep.emit(block, context, invoke_type(), [
      InvokeStep.literal_param("step", Map.get(config, "step", "account"), "step")
    ])
  end
end
