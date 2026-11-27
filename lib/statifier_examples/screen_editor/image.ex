defmodule StatifierExamples.ScreenEditor.Image do
  @moduledoc """
  `myapp.screens.image`: a picture on a screen - the branch library's logo
  at the top of a registration form, say - and the `alt` text a patron who
  cannot see it is told.

  `src` and `alt` are required. `src` is the picture's URL: an `https:`
  URL, a host-relative path such as `/images/logo.png`, or a `data:` image,
  and which of those riddler admits is riddler's to say when the walked
  document is admitted, so the editor holds `src` to being there and leaves
  the URL rule to riddler. `alt` is held to being there and not blank: an
  image the editor offers always says what it shows. `size` and `fit` are
  hints a renderer reads, offered as open lists
  (`StatifierExamples.ScreenEditor.field_candidates/0`).
  """

  use StatifierBlocks.BlockType

  alias StatifierExamples.ScreenEditor.Element

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    Element.common_fields() ++
      [
        Element.field("src", :string, "Source URL", true, ""),
        Element.field("alt", :string, "Alt text", true, ""),
        Element.field("size", :string, "Size", false, ""),
        Element.field("fit", :string, "Fit", false, "")
      ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    Element.validate(
      config,
      Element.present(config, "src", "an image needs the URL of its picture") ++
        Element.present(
          config,
          "alt",
          "an image needs the alt text a patron who cannot see it is told"
        )
    )
  end

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Image",
      group: "Screens",
      description: "A picture, and the alt text read in its place.",
      icon: "photo",
      keywords: ["image", "picture", "logo", "photo"],
      order: 10
    }
  end

  @impl StatifierBlocks.BlockType
  def emit(_block, context), do: Element.emit_leaf(context)
end
