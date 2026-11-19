defmodule StatifierExamples.ScreenEditor.SecretQuestion do
  @moduledoc """
  `myapp.screens.secret_question`: a question a patron answers with a
  secret they type - the PIN they choose for their library card.

  `label` is what the patron is asked, `help` a line of guidance shown
  beside it, and `required` says an empty response will not do. That is
  the whole of it: a secret question carries no `placeholder`, no
  `format`, and neither `default` nor `prefill`, because riddler's
  `secret_question` names none of them and refuses the last two - a secret
  is a value only the patron supplies.

  What a host does with the response is
  `StatifierExamples.Signup.Journey.submit/4`'s: it is validated as the
  patron typed it, then sealed before the chart is told anything, so what
  the execution holds is the sealed form and never the text.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Node.common_fields() ++
      [
        Node.field("label", :string, "Label", true, ""),
        Node.field("help", :string, "Help", false, ""),
        Node.field("required", :boolean, "Required", false, false)
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Node.validate(
      config,
      Node.present(config, "label", "a question needs the label a patron is asked")
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Secret question",
      group: "Screens",
      description: "A question answered with a secret, such as a PIN, sealed before it is kept.",
      icon: "lock-closed",
      keywords: ["question", "secret", "pin", "password"],
      order: 7
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_leaf(context)
end
