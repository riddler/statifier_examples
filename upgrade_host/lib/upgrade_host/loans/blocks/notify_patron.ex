defmodule UpgradeHost.Loans.Blocks.NotifyPatron do
  @moduledoc """
  `myapp.notify_patron`: the step that sends the patron the overdue
  notice, by naming the `myapp:notify_patron` invoke type and waiting for
  its answer.

  It is declared through `StatifierBlocks.InvokeStep`. Its own fields say
  what the handler reads: `patron` and `fine`, the datamodel roots sent as
  the `patron` and `fine` params. It keeps no answer, so it declares no
  `assign_to`. The handler that answers the call is
  `UpgradeHost.Loans.NotifyPatron`, registered separately.
  """

  alias StatifierBlocks.InvokeStep
  alias UpgradeHost.Loans.Blocks

  use StatifierBlocks.InvokeStep,
    invoke_type: "myapp:notify_patron",
    fields: [
      %{
        key: "patron",
        type: :string,
        label: "Read the patron from",
        required?: true,
        default: "patron"
      },
      %{
        key: "fine",
        type: :string,
        label: "Read the fine from",
        required?: true,
        default: "fine"
      }
    ],
    palette: %{
      label: "Notify patron",
      group: "Library loan",
      description: "Sends the patron the overdue notice.",
      icon: "envelope",
      keywords: ["notice", "patron", "overdue"],
      order: 2
    }

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    []
    |> InvokeStep.check_invoke_type(config)
    |> InvokeStep.check_assign_to(config)
    |> Blocks.check_root(config, "patron")
    |> Blocks.check_root(config, "fine")
    |> InvokeStep.verdict()
  end

  @impl StatifierBlocks.BlockType
  def emit(block, context) do
    params = [Blocks.param(block, "patron", "patron"), Blocks.param(block, "fine", "fine")]
    InvokeStep.emit(block, context, invoke_type(), params)
  end
end
