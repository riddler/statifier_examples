defmodule UpgradeHost.Loans.Blocks.AssessFine do
  @moduledoc """
  `myapp.assess_fine`: the step that has the fine on an overdue copy
  assessed, by naming the `myapp:assess_fine` invoke type and waiting for
  its answer.

  It is declared through `StatifierBlocks.InvokeStep`. Its own fields say
  what the handler reads (`copy`, the datamodel root the copy is read
  from, sent as the `copy` param) and where the answer goes (`assign_to`,
  the root the fine is written to). The handler that answers the call is
  `UpgradeHost.Loans.AssessFine`, registered separately: this module names
  the invoke type and runs nothing.
  """

  alias StatifierBlocks.InvokeStep
  alias UpgradeHost.Loans.Blocks

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:assess_fine",
    fields: [
      %{
        key: "copy",
        type: :string,
        label: "Read the copy from",
        required?: true,
        default: "copy"
      },
      %{
        key: "assign_to",
        type: :string,
        label: "Write the fine to",
        required?: false,
        default: "fine"
      }
    ],
    palette: %{
      label: "Assess fine",
      group: "Library loan",
      description: "Has the fine on an overdue copy assessed.",
      icon: "banknotes",
      keywords: ["fine", "overdue", "loan"],
      order: 1
    }

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_assign_to(config)
    |> Blocks.check_root(config, "copy")
    |> InvokeStep.verdict()
  end

  @impl StatifierBlocks.BlockType
  def emit(block, context),
    do: InvokeStep.emit(block, context, invoke_type(), [Blocks.param(block, "copy", "copy")])
end
