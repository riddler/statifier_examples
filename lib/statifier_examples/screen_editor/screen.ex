defmodule StatifierExamples.ScreenEditor.Screen do
  @moduledoc """
  `myapp.screens.screen`: one screen of a screen document, as a block whose
  `nodes` slot holds what the screen shows, in order.

  Its two fields are the screen's own, spelled as the document spells them:
  `key`, which a Journey names to say which screen is showing, and `title`.
  A patron registration screen keyed `patron_details` and titled "Your
  details" is one of these, with a heading, two text questions and a
  Continue button in its `nodes`.

  It is not a node: a screen carries no `condition`, and it is never placed
  inside another screen's `nodes`. It compiles to its nodes in order
  (`StatifierExamples.ScreenEditor.Node`, "What a node compiles to").
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Node

  @impl StatifierBlocks.BlockType
  def slots(_config), do: [{"nodes", :any, "Nodes"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    [
      Node.field("key", :string, "Key", true, ""),
      Node.field("title", :string, "Title", false, "")
    ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config), do: Node.validate(config, [])

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Screen",
      group: "Screens",
      description: "One screen, holding the nodes it shows in order.",
      icon: "rectangle-stack",
      keywords: ["screen", "page", "form"],
      order: 1
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Node.emit_nodes(context)
end
