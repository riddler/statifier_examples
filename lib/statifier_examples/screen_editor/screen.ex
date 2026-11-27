defmodule StatifierExamples.ScreenEditor.Screen do
  @moduledoc """
  `myapp.screens.screen`: one screen of a screen document, as a block whose
  `elements` slot holds what the screen shows, in order.

  Its two fields are the screen's own, spelled as the document spells them:
  `key`, which a Journey names to say which screen is showing, and `title`.
  A patron registration screen keyed `patron_details` and titled "Your
  details" is one of these, with a heading, two text questions and a
  Continue button in its `elements`.

  It is not an element: a screen carries no `condition`, and it is never
  placed inside another screen's `elements`. It compiles to its elements
  in order (`StatifierExamples.ScreenEditor.Element`, "What an element
  compiles to").
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def slots(_config), do: [{"elements", :any, "Elements"}]

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    [
      Element.field("key", :string, "Key", true, ""),
      Element.field("title", :string, "Title", false, "")
    ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config), do: Element.validate(config, [])

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Screen",
      group: "Screens",
      description: "One screen, holding the elements it shows in order.",
      icon: "rectangle-stack",
      keywords: ["screen", "page", "form"],
      order: 1
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_elements(context)
end
