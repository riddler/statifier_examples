defmodule StatifierExamples.Charts.Icons do
  @moduledoc """
  The heroicon outline set this app resolves block-type icon names against.

  `statifier_blocks` block types declare an icon **name** and never markup
  (ADR-0005 decision 10k), and the names the shipped core types use are
  heroicon outline names. This app already carries the `heroicons` dependency
  the Phoenix generator installs, so the host seam's whole job is to turn one
  of those names into an SVG body.

  The whole `24/outline` set is read at compile time rather than a
  hand-written subset of it, and that is the point: a subset is a list that
  drifts the first time a block type declares a name nobody remembered to add,
  and the failure would be a missing tile rather than an error. Reading the
  set makes `StatifierExamples.Charts.icon/1` total over every name heroicons
  ships, so a new block type needs no change here at all.

  What is stored is the SVG **body** - the children of the `<svg>` element,
  without the element itself - because the wrapper's attributes belong to the
  component that renders it: `StatifierExamplesWeb.Icons` sizes and paints the
  glyph, and the editor's tile sizes that. Storing the whole file would mean
  re-writing its attributes at render time, which is string surgery on every
  render for a value that never changes.
  """

  @outline_dir Path.expand("../../../deps/heroicons/optimized/24/outline", __DIR__)

  @body_pattern ~r|<svg[^>]*>(?<body>.*)</svg>|s

  @glyphs @outline_dir
          |> Path.join("*.svg")
          |> Path.wildcard()
          |> Map.new(fn path ->
            name = Path.basename(path, ".svg")

            body =
              case Regex.named_captures(@body_pattern, File.read!(path)) do
                %{"body" => body} -> String.trim(body)
                nil -> raise "#{path} is not an svg document"
              end

            {name, body}
          end)

  # Every file the map was built from, so editing the dependency's icons - or
  # moving to a heroicons release with a different set - recompiles this
  # module rather than serving a stale map.
  for path <- Path.wildcard(Path.join(@outline_dir, "*.svg")) do
    @external_resource path
  end

  if map_size(@glyphs) == 0 do
    raise "no heroicon outline svgs under #{@outline_dir}"
  end

  @doc """
  Every icon name this module can render, sorted.

  Public so the property that matters - every name the palette declares
  resolves - is asserted against the module rather than against a list copied
  into a test.
  """
  @spec known_names() :: [String.t()]
  def known_names, do: @glyphs |> Map.keys() |> Enum.sort()

  @doc """
  Whether `name` resolves to a glyph.
  """
  @spec known?(term()) :: boolean()
  def known?(name) when is_binary(name), do: Map.has_key?(@glyphs, name)
  def known?(_name), do: false

  @doc """
  The SVG body for `name`, or `nil`.

  `nil` rather than a raise: a name is a value a block type declared, and a
  host that does not have the glyph renders no tile rather than taking the
  canvas down over a missing icon.
  """
  @spec body(term()) :: String.t() | nil
  def body(name) when is_binary(name), do: Map.get(@glyphs, name)
  def body(_name), do: nil
end
