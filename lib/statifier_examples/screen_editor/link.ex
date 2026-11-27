defmodule StatifierExamples.ScreenEditor.Link do
  @moduledoc """
  `myapp.screens.link`: a place a patron may go from the screen - the
  library's lending rules, say - and the `label` that names it.

  `label` and `href` are required. `href` is an `https:` URL or a
  host-relative path such as `/lending-rules`, and, as with an image's
  `src`, which of those riddler admits is riddler's to say when the walked
  document is admitted. `style` is a hint a renderer reads, offered as an
  open list (`StatifierExamples.ScreenEditor.field_candidates/0`). A link
  raises no outcome and writes nothing: following one is the browser's
  navigation, not a press the Journey hears.
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Element.common_fields() ++
      [
        Element.field("label", :string, "Label", true, ""),
        Element.field("href", :string, "URL", true, ""),
        Element.field("style", :string, "Style", false, "")
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      Element.present(config, "label", "a link needs the label a patron reads") ++
        Element.present(config, "href", "a link needs the URL it goes to")
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Link",
      group: "Screens",
      description: "A place a patron may go from the screen.",
      icon: "link",
      keywords: ["link", "url", "href", "rules"],
      order: 12
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)
end
