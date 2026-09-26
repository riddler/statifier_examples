defmodule StatifierExamplesWeb.PlanMap do
  @moduledoc """
  The Plan view's map: the block document drawn as boxes in boxes, laid
  out by ELK in the browser. This module builds the graph the `PlanMap`
  hook in `assets/js/plan_map.mjs` lays out and draws; it computes no
  position itself.

  ## A projection, never a second model

  The graph is derived from the view model on every change and is never
  stored: no coordinate, no connector and no hand-placed position reaches
  the document or any table. What an author edits is the block tree, and
  the map is one more way of reading it, beside the indented list
  `StatifierExamplesWeb.PlanLive` draws from the same
  `StatifierBlocks.ViewModel.outline/1`. The two cannot disagree about what
  is in the document, because `nodes/1` below is the outline's own block
  list and the test beside this module holds them equal.

  ## The shape

  | Graph node | What it is | Where its children come from |
  |---|---|---|
  | a block | one `ViewModel.Node`, keyed by its block id | its slots, below |
  | a slot | one of a block's slots, keyed `<block id>/<slot name>` | the slot's blocks, in slot order |
  | an empty marker | a slot with nothing in it, keyed `<slot id>/empty`, carrying `parent` and `slot` | nothing |

  Every block but the root carries `gap: true`: it sits in a slot, so there
  is a place right after it an insert can target, the same place the list's
  "+" under its row targets. The root sits in no slot. An empty marker is
  the other kind of gap: the head of the slot it stands for.

  A block whose only body slot stacks (`ViewModel.arrangement/1` is
  `:stack`) holds that slot's blocks directly, because a sequence drawn
  inside a box inside a box says nothing the one box does not. Every other
  slot is a node of its own: a branch's arms side by side, a parallel's
  lanes, a group's interrupt rules and a drafts shelf. An empty slot is
  drawn as a marker rather than left out - an outcome nobody has written a
  step for yet is exactly what a reader of the map has to be able to see.

  Consecutive blocks in one body slot are joined by a `sequence` edge, in
  `ViewModel.flow_children/1` order; nothing else is an edge. A rail's
  blocks are not joined - a group's interrupt rules are alternatives that
  each watch the whole body, not steps that run one after another - and
  neither is a tray's. Connectors are drawn, never authored.

  A box's title is its type's name and the line under it is the block's
  sentence; where the two are the same words ("Sequence", "Group") the
  line is left off rather than said twice.

  ## Order is semantic, so it is forced

  A branch evaluates its arms in slot order and a sequence runs its steps
  in order, so a layout that swapped two arms to save a crossing would draw
  a different chart. Two ELK options keep the model order, and the two are
  set differently on purpose:

  - `crossingMinimization.forceNodeModelOrder` is set on EVERY container,
    because under `hierarchyHandling: INCLUDE_CHILDREN` a value set on the
    root does not reach a nested graph;
  - `considerModelOrder.strategy` is set on the ROOT ONLY. The root value
    is all the order this map needs, and a per-container value has been
    seen to throw inside elkjs on a differently shaped graph, so it is kept
    off the containers rather than found out again.

  The test beside this module pins both, and a test that lays the fixtures
  out through the real elkjs pins the order that results.

  ## Sizes

  Text is measured by estimate, a fixed width per character, rather than
  by the browser: the graph is built on the server, and a node sized after
  the page measured it would be a layout that depends on which fonts
  loaded. The estimate errs wide, and no box is narrower than the widest
  line it carries, its title included: a single word longer than a line
  widens its box rather than running out of it, and a container is held
  at least that wide whatever its children need.
  """

  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node
  alias StatifierBlocks.ViewModel.Slot

  @char_width 7
  @line_height 16
  @leaf_min_width 150
  @leaf_max_width 260
  @leaf_padding 24
  @header_base 12
  @empty_text "Nothing here yet"

  @force_model_order "org.eclipse.elk.layered.crossingMinimization.forceNodeModelOrder"
  @consider_model_order "org.eclipse.elk.layered.considerModelOrder.strategy"
  @layer_constraint "org.eclipse.elk.layered.layering.layerConstraint"

  @root_options %{
    "org.eclipse.elk.algorithm" => "layered",
    "org.eclipse.elk.direction" => "DOWN",
    "org.eclipse.elk.hierarchyHandling" => "INCLUDE_CHILDREN",
    "org.eclipse.elk.spacing.nodeNode" => "24",
    "org.eclipse.elk.layered.spacing.nodeNodeBetweenLayers" => "28",
    "org.eclipse.elk.edgeRouting" => "ORTHOGONAL",
    @force_model_order => "true",
    @consider_model_order => "NODES_AND_EDGES"
  }

  @typedoc """
  One graph node, in elkjs's JSON shape plus the fields the hook draws
  from: `kind`, `title` and `lines`, and on a slot `style`.
  """
  @type graph_node :: %{required(String.t()) => term()}

  @typedoc "The whole graph: the ELK root, with the document's root block as its one child."
  @type t :: %{required(String.t()) => term()}

  @doc """
  The graph for `view_model`, ready to be JSON-encoded onto the hook.

  The root carries the layout options every container inherits and the two
  it alone may carry; see the moduledoc on why `considerModelOrder` is one
  of them.
  """
  @spec graph(ViewModel.t()) :: t()
  def graph(%ViewModel{root: %Node{} = root}) do
    %{
      "id" => "plan-map",
      "layoutOptions" => @root_options,
      "children" => [root |> block() |> Map.put("gap", false)],
      "edges" => []
    }
  end

  @doc """
  The block ids in `graph`, in the order a pre-order walk of it meets them.

  The map's claim to be the document is that this list is the outline's:
  every block exactly once, in reading order. Slot nodes and empty markers
  are not blocks and are not in it.
  """
  @spec nodes(t() | graph_node()) :: [String.t()]
  def nodes(%{"children" => children} = node) do
    own = if node["kind"] == "block", do: [node["id"]], else: []
    own ++ Enum.flat_map(children, &nodes/1)
  end

  def nodes(%{"kind" => "block", "id" => id}), do: [id]
  def nodes(%{}), do: []

  @doc "The text an empty slot's marker carries."
  @spec empty_text() :: String.t()
  def empty_text, do: @empty_text

  # ------------------------------------------------------------------ blocks

  @spec block(Node.t()) :: graph_node()
  defp block(%Node{slots: []} = node) do
    lines = node |> ViewModel.sentence() |> under(ViewModel.title(node))
    title = ViewModel.title(node)

    %{
      "id" => node.block_id,
      "kind" => "block",
      "gap" => true,
      "title" => title,
      "lines" => lines,
      "width" => leaf_width([title | lines]),
      "height" => @header_base + (length(lines) + 1) * @line_height
    }
  end

  defp block(%Node{} = node) do
    lines = node |> header() |> under(ViewModel.title(node))
    title = ViewModel.title(node)

    {children, edges} =
      node
      |> drawn_slots()
      |> Enum.map(&slot_part(node, &1))
      |> Enum.unzip()

    %{
      "id" => node.block_id,
      "kind" => "block",
      "gap" => true,
      "title" => title,
      "lines" => lines,
      "layoutOptions" => container_options([title | lines], lines),
      "children" => List.flatten(children),
      "edges" => List.flatten(edges)
    }
  end

  # What one slot adds to its block: the slot's blocks drawn straight into
  # the block when the slot is inlined, or one slot node otherwise.
  @spec slot_part(Node.t(), Slot.t()) :: {[graph_node()], [map()]}
  defp slot_part(%Node{} = node, %Slot{} = slot) do
    cond do
      not inline?(node, slot) -> {[slot(node, slot)], []}
      slot.children == [] -> {[empty(node.block_id, slot.name)], []}
      true -> {slot_children(slot), sequence_edges(slot)}
    end
  end

  # The words at the top of a container: its sentence, and for a fan or a
  # parallel the package's own "one of" / "all of", which is the only
  # place the exclusive/concurrent distinction is stated.
  @spec header(Node.t()) :: String.t()
  defp header(%Node{} = node) do
    case ViewModel.fan_label(node) do
      nil -> ViewModel.sentence(node)
      label -> "#{ViewModel.sentence(node)} (#{label})"
    end
  end

  # The slots a container draws, in the outline's order: body, then rails,
  # then trays.
  @spec drawn_slots(Node.t()) :: [Slot.t()]
  defp drawn_slots(%Node{slots: slots} = node) do
    ViewModel.body_slots(node) ++
      Enum.filter(slots, &ViewModel.rail?/1) ++ Enum.filter(slots, &ViewModel.tray?/1)
  end

  # A stacking block's one body slot is drawn inside the block itself.
  @spec inline?(Node.t(), Slot.t()) :: boolean()
  defp inline?(%Node{} = node, %Slot{name: name}) do
    match?(
      {:stack, [%Slot{name: ^name}]},
      {ViewModel.arrangement(node), ViewModel.body_slots(node)}
    )
  end

  # ------------------------------------------------------------------- slots

  @spec slot(Node.t(), Slot.t()) :: graph_node()
  defp slot(%Node{block_id: block_id}, %Slot{} = slot) do
    id = "#{block_id}/#{slot.name}"
    lines = slot |> slot_header() |> wrap()

    {children, edges} =
      case slot.children do
        [] -> {[empty(block_id, slot.name)], []}
        _blocks -> {slot_children(slot), flow_edges(slot)}
      end

    %{
      "id" => id,
      "kind" => "slot",
      "style" => style(slot),
      "title" => slot.label,
      "lines" => lines,
      "layoutOptions" => slot_options(slot, lines),
      "children" => children,
      "edges" => edges
    }
  end

  # A rail or a tray is not a step in the flow: it watches the whole of it,
  # or holds what is kept to one side. ELK's last layer puts it beside the
  # flow's last step, rather than beside its first as if it came next.
  @spec slot_options(Slot.t(), [String.t()]) :: %{String.t() => String.t()}
  defp slot_options(%Slot{} = slot, lines) do
    if ViewModel.rail?(slot) or ViewModel.tray?(slot),
      do: Map.put(container_options(lines, lines), @layer_constraint, "LAST"),
      else: container_options(lines, lines)
  end

  @spec slot_header(Slot.t()) :: String.t()
  defp slot_header(%Slot{label: label, condition: condition}) when is_binary(condition),
    do: "#{label}: #{condition}"

  defp slot_header(%Slot{label: label}), do: label

  @spec style(Slot.t()) :: String.t()
  defp style(%Slot{} = slot) do
    cond do
      ViewModel.rail?(slot) -> "rail"
      ViewModel.tray?(slot) -> "tray"
      true -> "arm"
    end
  end

  # A slot's blocks: the flow in order, then the shelf at its foot, the
  # order `ViewModel.outline/1` visits them in.
  @spec slot_children(Slot.t()) :: [graph_node()]
  defp slot_children(%Slot{} = slot) do
    Enum.map(ViewModel.flow_children(slot) ++ ViewModel.shelf_children(slot), &block/1)
  end

  # A rail's or a tray's blocks are not a sequence; see the moduledoc.
  @spec flow_edges(Slot.t()) :: [map()]
  defp flow_edges(%Slot{} = slot) do
    if ViewModel.rail?(slot) or ViewModel.tray?(slot), do: [], else: sequence_edges(slot)
  end

  @spec sequence_edges(Slot.t()) :: [map()]
  defp sequence_edges(%Slot{} = slot) do
    slot
    |> ViewModel.flow_children()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [%Node{block_id: from}, %Node{block_id: to}] ->
      %{"id" => "#{from}->#{to}", "sources" => [from], "targets" => [to], "kind" => "sequence"}
    end)
  end

  # An empty slot's marker carries the block and the slot it stands for,
  # which is the gap an insert into it targets.
  @spec empty(String.t(), String.t()) :: graph_node()
  defp empty(block_id, slot_name) do
    %{
      "id" => "#{block_id}/#{slot_name}/empty",
      "kind" => "empty",
      "parent" => block_id,
      "slot" => slot_name,
      "title" => @empty_text,
      "lines" => [],
      "width" => leaf_width([@empty_text]),
      "height" => @header_base + @line_height
    }
  end

  # ------------------------------------------------------------------ sizing

  # Every container orders its own children; see the moduledoc on why this
  # is set per container and `considerModelOrder` is not. `texts` is every
  # line the container draws, title included, and holds its width; `lines`
  # is what sits under the title, and sets the header's height.
  #
  # The minimum is written HEIGHT first. Under `direction: DOWN` with
  # `hierarchyHandling: INCLUDE_CHILDREN`, elkjs 0.9.3 applies a nested
  # container's `nodeSize.minimum` transposed - `(w,h)` comes back `w` tall
  # and `h` wide - so the pair is handed over in the order it is read back
  # in. Written the documented way round, a container whose header is
  # wider than its children stays narrow and grows a tall empty band.
  # `StatifierExamplesWeb.PlanMapLayoutTest` lays every fixture out and
  # holds every box at least as wide as its text, so an elkjs that stops
  # transposing turns that test red rather than quietly narrowing a box.
  @spec container_options([String.t()], [String.t()]) :: %{String.t() => String.t()}
  defp container_options(texts, lines) do
    top = @header_base + (length(lines) + 1) * @line_height

    %{
      @force_model_order => "true",
      "org.eclipse.elk.padding" => "[top=#{top},left=12,bottom=12,right=12]",
      "org.eclipse.elk.nodeSize.constraints" => "MINIMUM_SIZE",
      "org.eclipse.elk.nodeSize.minimum" => "(#{top + 12},#{text_width(texts)})"
    }
  end

  @spec leaf_width([String.t()]) :: pos_integer()
  defp leaf_width(texts), do: max(text_width(texts), @leaf_min_width)

  # The width the widest of `texts` needs at the estimate, padding included.
  @spec text_width([String.t()]) :: pos_integer()
  defp text_width(texts) do
    widest = texts |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    widest * @char_width + @leaf_padding
  end

  # The lines under a box's title: `text` wrapped, or none when it only
  # repeats the title.
  @spec under(String.t(), String.t()) :: [String.t()]
  defp under(title, title), do: []
  defp under(text, _title), do: wrap(text)

  # Words onto lines no wider than a leaf holds. A single word longer than a
  # line keeps its own line rather than being cut: nothing on the map
  # truncates.
  @spec wrap(String.t()) :: [String.t()]
  defp wrap(text) do
    per_line = div(@leaf_max_width - @leaf_padding, @char_width)

    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce([], fn
      word, [] -> [word]
      word, [line | rest] -> join(word, line, rest, per_line)
    end)
    |> Enum.reverse()
  end

  @spec join(String.t(), String.t(), [String.t()], pos_integer()) :: [String.t()]
  defp join(word, line, rest, per_line) do
    if String.length(line) + 1 + String.length(word) <= per_line,
      do: ["#{line} #{word}" | rest],
      else: [word, line | rest]
  end
end
