defmodule StatifierExamplesWeb.Icons do
  @moduledoc """
  This app's icon component, in the shape `StatifierBlocks.Editor`'s `icon`
  assign takes.

  The package ships its own small set and uses it when a host passes nothing.
  A host that passes one wins on every tile - the canvas cards and the palette
  rows alike - which is the seam this module fills: the block types this app
  registers name heroicons, the app already carries the `heroicons`
  dependency, and passing this component is how the two meet.

  The contract the package states, kept on both sides:

    * it is called with a **name**, never markup, and never with a `nil` name
      (a block type that declares no icon gets no tile at all);
    * the `class` it is handed is the tile's, and the tile sizes the `svg`
      inside it to 68% of itself, so the glyph carries no size of its own;
    * the glyph paints with `currentColor`, so the two tokens the tile reads -
      `--sb-block-accent` and `--sb-block-accent-tint` - are all a theme has
      to touch.
  """

  use StatifierExamplesWeb, :html

  alias StatifierExamples.Charts

  attr :name, :string, required: true, doc: "the icon name the palette entry declared"
  attr :class, :string, default: nil, doc: "the tile class the editor owns"

  @doc """
  One glyph, or nothing at all for a name this app cannot resolve.

  Rendering nothing is the same answer the package gives a block type that
  declared no icon: the chrome closes up around the label. A host that
  substituted a placeholder here would be inventing a tile for a declaration
  nobody made.
  """
  def icon(assigns) do
    assigns = Map.put_new(assigns, :class, nil)

    assigns = assign(assigns, :body, Charts.icon(assigns.name) && Charts.Icons.body(assigns.name))

    ~H"""
    <span :if={@body} class={@class} data-icon={@name} aria-hidden="true">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        focusable="false"
      >
        {Phoenix.HTML.raw(@body)}
      </svg>
    </span>
    """
  end
end
