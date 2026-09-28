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
  lanes, a group's interrupt rules and a drafts shelf. A group is the one
  exception the other way: its body stacks, but it is drawn as a slot node
  of its own all the same (see "The Group" below). An empty slot is
  drawn as a marker rather than left out - an outcome nobody has written a
  step for yet is exactly what a reader of the map has to be able to see.

  Consecutive blocks in one body slot are joined by a `sequence` edge, in
  `ViewModel.flow_children/1` order (a `rejoin` edge where the first is a
  branch; see "The Branch" below); nothing else is an edge the layout
  sees (a group's interrupt edges are drawn after it, below). A rail's
  blocks are not joined - a group's interrupt rules are alternatives that
  each watch the whole body, not steps that run one after another - and
  neither is a tray's. Connectors are drawn, never authored.

  A box's title is its type's name and the line under it is the block's
  sentence; where the two are the same words ("Invoke", "Raise") the
  line is left off rather than said twice.

  ## The Branch

  A branch is one decision, and its box says so in three ways.

  - **The header names every arm, in order.** Where every other container
    carries its sentence, a `core.branch` carries the package's own "one
    of" and then one numbered entry per arm, in slot order, each the arm's
    label and its condition as authored (`When "renew": copy.holds == 0
    AND loan.renewals < 2`), the arms with no condition ("Otherwise",
    "Cannot be decided") by their label alone.
    This header is the map's own: the branch type's sentence, which the
    list draws, is not changed by it.
  - **The arms sit under one band.** The branch's node carries `band: true`
    and room above its arms; the hook draws one band spanning every arm,
    with a small fork mark at its left, from the boxes the layout placed.
    The band and the mark are drawn inside the branch's own box, so a click
    on either is a click on the branch.
  - **The arms rejoin at its bottom edge.** The edge from a branch to the
    step after it carries `kind: "rejoin"`, and the hook draws it with a
    join dot where it leaves the branch. A branch that is the last step of
    the document's own flow rejoins into an end mark (`kind: "end"`, keyed
    `<root id>/end`), because nothing else comes next; a branch that ends a
    nested flow needs none, since the flow it ends is itself joined to what
    follows it. An end mark is not a block: it is in no outline, selects
    nothing and arms no insert.
  - **The band carries a caption.** The branch's node carries `caption`,
    `StatifierExamplesWeb.TypeExplanation.caption/1` of its type, and
    `caption_width`, the room the caption and the fork mark need; the hook
    writes the caption inside the band, after the fork mark, and never
    draws the band narrower than that room.

  ## The Group

  A group's body is what it is for, and its interrupt rules watch that
  body from beside it, so the map draws the body first and larger.

  - **The body is a pane.** A `core.group` or `core.resumable_group`
    draws its body slot as a slot node with `style: "body"`, first among
    its children, rather than holding the body's blocks directly. The pane
    is held wider than the rules column and at least as tall, at the same
    per-character estimate as every other size here, so the body is the
    larger of the two whatever the rules say.
  - **The rules are a side column.** The interrupt rules' slot node is
    laid out on its own, in one column, rules top to bottom in rail order,
    and ELK places it beside the pane. It is laid out apart from the rest
    of the graph (`hierarchyHandling: SEPARATE_CHILDREN`) because nothing
    joins a rule to anything ELK sees: the interrupt edges are the hook's
    (below), so no edge crosses into the column. It is laid out left to
    right, where rules nothing joins share one layer, and a layer runs top
    to bottom. Its minimum size is written width first, the documented
    way round: a layout of its own is not transposed (see "Sizes").
  - **The column carries a caption.** The rules' slot node carries
    `caption`, `TypeExplanation.caption/1` of the group's type, which the
    hook draws under the column's label. The caption is the host's fixed
    text and lives in that one module, so it changes in one place.

  ## Interrupt edges

  A group's interrupt rules are not joined to each other, but each one does
  lead somewhere: an `abandon` rule leaves the group by its exit and a
  `resume` rule goes back to the head of its body. The group's node carries
  those as `interrupts`, one per rule, in rail order, and the hook draws
  each one dashed from the rule's box to where it leads; the head of the
  body is the first node drawn in the body's pane. They are handed to
  the hook beside the graph's `edges`, not among them, and drawn after the
  layout from the boxes it placed, so an interrupt edge never moves a box.
  They are the edges `StatifierBlocks.Describe.outline/3` answers with
  `kind: :interrupt`, read here off the same view model - a rule's
  `outcome`, on the `interrupts` rail of a `core.group` or a
  `core.resumable_group` - because the map is built from the view model
  alone; the test beside this module holds the two equal for every fixture.

  ## Timer marks

  Two blocks wait on a clock in different ways, and a box says which with a
  small mark at its top right: a `core.await` carries the wait mark (it
  waits, in its own step, for an event or its timeout), and a `core.send`
  with a delay carries the clock mark (the event it arms fires later, after
  the step has moved on). A send with no delay carries neither. A mark is
  drawn inside its block's box, so a click on it is a click on the box.

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

  A group's rules column is laid out on its own, and there
  `forceNodeModelOrder` alone does not hold the order: rules that nothing
  joins are each a connected component, and ELK packs separate components
  by size, not in model order. The column keeps its components together
  (`separateConnectedComponents: false`), so its rules share one layer and
  that layer keeps model order.

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
  alias StatifierExamplesWeb.TypeExplanation

  @char_width 7
  @line_height 16
  @leaf_min_width 150
  @leaf_max_width 260
  @leaf_padding 24
  @header_base 12
  @empty_text "Nothing here yet"
  @mark_room 22
  @group_types ["core.group", "core.resumable_group"]
  @branch_type "core.branch"
  @band_room 24
  @end_text "End"
  @end_height 28
  @rule_spacing 24
  @body_lead 48
  @fork_room 26
  @pad 12

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
  from: `kind`, `title` and `lines`, on a slot `style`, on a timer block
  `mark`, on a group with interrupt rules `interrupts`, on a branch `band`,
  `caption` and `caption_width`, and on a group's rules column `caption`.
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
      "children" => [root |> block() |> Map.put("gap", false) |> put_end(root)],
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

  @doc """
  Every interrupt edge in `graph`, groups in the order a pre-order walk
  meets them and each group's rules in rail order, as
  `%{"from" => rule, "group" => group, "to" => "exit" | "body"}`.
  """
  @spec interrupts(t() | graph_node()) :: [%{String.t() => String.t()}]
  def interrupts(%{} = node) do
    own =
      for %{"sources" => [from], "targets" => [group], "to" => to} <-
            Map.get(node, "interrupts", []),
          do: %{"from" => from, "group" => group, "to" => to}

    own ++ Enum.flat_map(Map.get(node, "children", []), &interrupts/1)
  end

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
    |> put_mark(mark(node), title, lines)
  end

  defp block(%Node{} = node) do
    title = ViewModel.title(node)

    {lines, extra, least} =
      if branch?(node),
        do: {arm_lines(node), @band_room, band_width(node)},
        else: {node |> header() |> under(title), 0, 0}

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
      "layoutOptions" =>
        container_options([title | lines], lines, extra, least: least + 2 * @pad),
      "children" => List.flatten(children),
      "edges" => List.flatten(edges)
    }
    |> put_band(node)
    |> put_interrupts(node)
  end

  # ------------------------------------------------------------ the Branch

  @spec branch?(Node.t()) :: boolean()
  defp branch?(%Node{type: type}), do: type == @branch_type

  # A branch's header: the package's "one of", then one numbered entry per
  # arm, in slot order, each the arm's label and its condition as authored;
  # see the moduledoc's "The Branch". An entry wider than a line wraps onto
  # the next.
  @spec arm_lines(Node.t()) :: [String.t()]
  defp arm_lines(%Node{} = node) do
    arms =
      node
      |> ViewModel.body_slots()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {slot, n} -> wrap("#{n}. #{slot_header(slot)}") end)

    case ViewModel.fan_label(node) do
      nil -> arms
      label -> ["#{String.capitalize(label)}, in order:" | arms]
    end
  end

  @spec put_band(graph_node(), Node.t()) :: graph_node()
  defp put_band(graph_node, %Node{} = node) do
    if branch?(node),
      do:
        Map.merge(graph_node, %{
          "band" => true,
          "caption" => TypeExplanation.caption(node.type),
          "caption_width" => band_width(node)
        }),
      else: graph_node
  end

  # The least width a branch's band is drawn at: its fork mark and its
  # caption, at the map's estimate.
  @spec band_width(Node.t()) :: non_neg_integer()
  defp band_width(%Node{} = node) do
    case TypeExplanation.caption(node.type) do
      nil -> 0
      caption -> @fork_room + text_width([caption])
    end
  end

  # ------------------------------------------------------------- the Group

  @spec group?(Node.t()) :: boolean()
  defp group?(%Node{type: type}), do: type in @group_types

  # The rules column of a group, as `{width, height}` at the map's estimate:
  # the slot node `slot/2` builds for it, its rules stacked one above the
  # next. The body's pane is held larger than this; see the moduledoc's
  # "The Group".
  @spec column_size(Node.t()) :: {pos_integer(), pos_integer()}
  defp column_size(%Node{block_id: block_id, slots: slots} = node) do
    case Enum.find(slots, &ViewModel.rail?/1) do
      nil ->
        {0, 0}

      %Slot{} = rail ->
        lines = column_lines(node, rail)

        parts =
          case rail.children do
            [] -> [empty(block_id, rail.name)]
            _blocks -> slot_children(rail)
          end

        top = header_height(lines)
        heights = Enum.map(parts, &part_height/1)
        widths = Enum.map(parts, &part_width/1)
        height = top + Enum.sum(heights) + @rule_spacing * (length(parts) - 1) + @pad
        width = Enum.max([Enum.max(widths) + 2 * @pad, text_width(lines)])
        {width, height}
    end
  end

  # What a rules column says under its title: its label, then the caption.
  @spec column_lines(Node.t(), Slot.t()) :: [String.t()]
  defp column_lines(%Node{} = node, %Slot{} = slot) do
    case TypeExplanation.caption(node.type) do
      nil -> wrap(slot_header(slot))
      caption -> wrap(slot_header(slot)) ++ [caption]
    end
  end

  # A rule's size at the estimate. A rule is an interrupt handler, a leaf
  # in the core vocabulary, so it carries its own; a host handler drawn as a
  # container counts at a leaf's least, and the layout tests hold the pane
  # larger for every fixture.
  @spec part_width(graph_node()) :: pos_integer()
  defp part_width(part), do: Map.get(part, "width", @leaf_min_width)

  @spec part_height(graph_node()) :: pos_integer()
  defp part_height(part), do: Map.get(part, "height", @header_base + 2 * @line_height)

  # The end mark after a branch that is the last step of the root's own
  # flow, joined to it by a rejoin edge; every other root is left as it is.
  @spec put_end(graph_node(), Node.t()) :: graph_node()
  defp put_end(%{"children" => children} = graph_node, %Node{} = root) do
    with [%Slot{} = body] <- ViewModel.body_slots(root),
         true <- inline?(root, body),
         %Node{block_id: last} = branch <- List.last(ViewModel.flow_children(body)),
         true <- branch?(branch) do
      id = "#{root.block_id}/end"
      {before, [drawn | rest]} = Enum.split_while(children, &(&1["id"] != last))

      mark = %{
        "id" => id,
        "kind" => "end",
        "title" => @end_text,
        "lines" => [],
        "width" => text_width([@end_text]),
        "height" => @end_height
      }

      edge = %{
        "id" => "#{last}->#{id}",
        "sources" => [last],
        "targets" => [id],
        "kind" => "rejoin"
      }

      graph_node
      |> Map.put("children", before ++ [drawn, mark | rest])
      |> Map.update!("edges", &(&1 ++ [edge]))
    else
      _no_end -> graph_node
    end
  end

  defp put_end(graph_node, %Node{}), do: graph_node

  # ------------------------------------------------------------ timer marks

  # The mark a leaf carries, and the room for it beside the title: the mark
  # sits at the box's top right, level with the title, so the title line is
  # the one that has to leave it space.
  @spec put_mark(graph_node(), String.t() | nil, String.t(), [String.t()]) :: graph_node()
  defp put_mark(graph_node, nil, _title, _lines), do: graph_node

  defp put_mark(graph_node, mark, title, lines) do
    width = Enum.max([graph_node["width"], text_width([title]) + @mark_room, leaf_width(lines)])
    Map.merge(graph_node, %{"mark" => mark, "width" => width})
  end

  # See the moduledoc's "Timer marks".
  @spec mark(Node.t()) :: String.t() | nil
  defp mark(%Node{type: "core.await"}), do: "wait"
  defp mark(%Node{type: "core.send"} = node), do: if(delayed?(node), do: "clock")
  defp mark(%Node{}), do: nil

  # Whether a send's `delay` holds anything but blank, as its form reads it.
  @spec delayed?(Node.t()) :: boolean()
  defp delayed?(%Node{form: %{fields: fields}}) do
    case Enum.find(fields, &(&1.key == "delay")) do
      %{value: value} when is_binary(value) -> String.trim(value) != ""
      %{value: value} -> not is_nil(value)
      nil -> false
    end
  end

  defp delayed?(%Node{}), do: false

  # -------------------------------------------------------- interrupt edges

  # One edge per interrupt rule on a group's rail: `abandon` to the group's
  # exit, `resume` to the head of its body, which is the first node drawn
  # in the body's pane, the group's first child. A rule with neither
  # outcome leads nowhere and has no edge, as in `StatifierBlocks.Describe`.
  @spec put_interrupts(graph_node(), Node.t()) :: graph_node()
  defp put_interrupts(graph_node, %Node{type: type, block_id: group, slots: slots})
       when type in @group_types do
    head =
      graph_node["children"]
      |> List.first(%{})
      |> Map.get("children", [])
      |> List.first(%{})
      |> Map.get("id")

    edges =
      for %Slot{name: "interrupts"} = slot <- slots,
          %Node{outcome: outcome, block_id: rule} <- ViewModel.flow_children(slot),
          to = leads_to(outcome),
          to != nil do
        %{
          "id" => "#{rule}->#{group}/#{to}",
          "sources" => [rule],
          "targets" => [group],
          "kind" => "interrupt",
          "to" => to,
          "head" => head
        }
      end

    if edges == [], do: graph_node, else: Map.put(graph_node, "interrupts", edges)
  end

  defp put_interrupts(graph_node, %Node{}), do: graph_node

  @spec leads_to(term()) :: String.t() | nil
  defp leads_to("abandon"), do: "exit"
  defp leads_to("resume"), do: "body"
  defp leads_to(_other), do: nil

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

  # A stacking block's one body slot is drawn inside the block itself, but
  # for a group's, which is a pane of its own; see the moduledoc.
  @spec inline?(Node.t(), Slot.t()) :: boolean()
  defp inline?(%Node{} = node, %Slot{name: name}) do
    not group?(node) and
      match?(
        {:stack, [%Slot{name: ^name}]},
        {ViewModel.arrangement(node), ViewModel.body_slots(node)}
      )
  end

  # ------------------------------------------------------------------- slots

  @spec slot(Node.t(), Slot.t()) :: graph_node()
  defp slot(%Node{block_id: block_id} = node, %Slot{} = slot) do
    id = "#{block_id}/#{slot.name}"
    style = style(node, slot)
    lines = slot |> slot_header() |> wrap()

    {children, edges} =
      case slot.children do
        [] -> {[empty(block_id, slot.name)], []}
        _blocks -> {slot_children(slot), flow_edges(slot)}
      end

    %{
      "id" => id,
      "kind" => "slot",
      "style" => style,
      "title" => slot.label,
      "lines" => lines,
      "layoutOptions" => slot_options(style, node, slot, lines),
      "children" => children,
      "edges" => edges
    }
    |> put_caption(style, node)
  end

  # A group's rules column carries its caption; see the moduledoc.
  @spec put_caption(graph_node(), String.t(), Node.t()) :: graph_node()
  defp put_caption(graph_node, "rail", %Node{type: type}) when type in @group_types do
    case TypeExplanation.caption(type) do
      nil -> graph_node
      caption -> Map.put(graph_node, "caption", caption)
    end
  end

  defp put_caption(graph_node, _style, %Node{}), do: graph_node

  # A rail or a tray is not a step in the flow: it watches the whole of it,
  # or holds what is kept to one side. ELK's last layer puts it beside the
  # flow's last step, rather than beside its first as if it came next. A
  # group's rules column is laid out on its own and its body's pane is held
  # larger than it; see the moduledoc's "The Group".
  @spec slot_options(String.t(), Node.t(), Slot.t(), [String.t()]) ::
          %{String.t() => String.t()}
  defp slot_options("rail", %Node{type: type} = node, %Slot{} = slot, _lines)
       when type in @group_types do
    lines = column_lines(node, slot)

    %{
      @force_model_order => "true",
      @layer_constraint => "LAST",
      "org.eclipse.elk.hierarchyHandling" => "SEPARATE_CHILDREN",
      "org.eclipse.elk.algorithm" => "layered",
      "org.eclipse.elk.direction" => "RIGHT",
      "org.eclipse.elk.separateConnectedComponents" => "false",
      "org.eclipse.elk.spacing.nodeNode" => "#{@rule_spacing}",
      "org.eclipse.elk.padding" =>
        "[top=#{header_height(lines)},left=#{@pad},bottom=#{@pad},right=#{@pad}]",
      "org.eclipse.elk.nodeSize.constraints" => "MINIMUM_SIZE",
      "org.eclipse.elk.nodeSize.minimum" =>
        "(#{text_width(lines)},#{header_height(lines) + @pad})"
    }
  end

  defp slot_options("body", %Node{} = node, %Slot{}, lines) do
    {width, height} = column_size(node)
    container_options(lines, lines, 0, least: width + @body_lead, tall: height)
  end

  defp slot_options(style, %Node{}, %Slot{}, lines) when style in ["rail", "tray"],
    do: Map.put(container_options(lines, lines), @layer_constraint, "LAST")

  defp slot_options(_arm, %Node{}, %Slot{}, lines), do: container_options(lines, lines)

  @spec slot_header(Slot.t()) :: String.t()
  defp slot_header(%Slot{label: label, condition: condition}) when is_binary(condition),
    do: "#{label}: #{condition}"

  defp slot_header(%Slot{label: label}), do: label

  # A group's body is its pane; every other slot is an arm, a rail (a
  # group's rules column among them) or a tray.
  @spec style(Node.t(), Slot.t()) :: String.t()
  defp style(%Node{} = node, %Slot{} = slot) do
    cond do
      group?(node) and not ViewModel.rail?(slot) and not ViewModel.tray?(slot) -> "body"
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
    |> Enum.map(fn [%Node{block_id: from} = source, %Node{block_id: to}] ->
      %{"id" => "#{from}->#{to}", "sources" => [from], "targets" => [to], "kind" => kind(source)}
    end)
  end

  # The edge out of a branch is where its arms rejoin; see the moduledoc.
  @spec kind(Node.t()) :: String.t()
  defp kind(%Node{} = node), do: if(branch?(node), do: "rejoin", else: "sequence")

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
  #
  # `extra` is room under the header and above the children: a branch's
  # band. `least` and `tall` raise the minimum width and height past what
  # the text needs: a branch's band caption, a group body's pane.
  @spec container_options([String.t()], [String.t()], non_neg_integer(), keyword()) ::
          %{String.t() => String.t()}
  defp container_options(texts, lines, extra \\ 0, opts \\ []) do
    top = header_height(lines) + extra
    width = max(text_width(texts), Keyword.get(opts, :least, 0))
    height = max(top + @pad, Keyword.get(opts, :tall, 0))

    %{
      @force_model_order => "true",
      "org.eclipse.elk.padding" => "[top=#{top},left=#{@pad},bottom=#{@pad},right=#{@pad}]",
      "org.eclipse.elk.nodeSize.constraints" => "MINIMUM_SIZE",
      "org.eclipse.elk.nodeSize.minimum" => "(#{height},#{width})"
    }
  end

  # The height of a container's header: its title and `lines` under it.
  @spec header_height([String.t()]) :: pos_integer()
  defp header_height(lines), do: @header_base + (length(lines) + 1) * @line_height

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
