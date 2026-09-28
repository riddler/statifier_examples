defmodule StatifierExamplesWeb.PlanDescription do
  @moduledoc """
  The Plan view's description region, as data: one structured description
  for every element the map draws, and one for the document itself when
  nothing is selected.

  The region sits at the top of the Plan panel and is always there. It
  shows the selected block's description, or this module's `idle/4`
  answer when no block is selected. It is the screen-reader twin of the
  map: the map region is `aria-hidden`, so anything a sighted reader
  learns by looking at a box has to be sayable in words here, and every
  row of the list points at the region with `aria-describedby`.

  ## Where every fact comes from

  Nothing here is a second reading of the document. Every fact is asked of
  something the page already builds:

  | Fact | Asked of |
  |---|---|
  | which elements there are, and their ids | `StatifierExamplesWeb.PlanMap.graph/1` |
  | a block's title and sentence | `ViewModel.title/1`, and `ViewModel.sentence/1` with its event names in words (`StatifierExamplesWeb.EventPhrasing.sentence/1`) |
  | a block's settings | `ViewModel.shown_fields/1`: the fields the type's `config_schema/1` declares, with their values |
  | where a block sits | `ViewModel.positions/1` |
  | its outcomes and where each goes | `StatifierBlocks.Describe.outline/3`'s `:sequence` and `:exit` edges |
  | the interrupt rules that can leave it | the outline's `:interrupt` edges |
  | what an arm goes to | the outline's `:branch` edges |
  | what a connector carries | the outline's `:sequence` edge between the same two blocks |
  | what a type is for | `StatifierExamplesWeb.TypeExplanation` |

  The settings are values, never controls: this is a description, and the
  one place a value is changed stays the panel's form.

  ## The kinds

  An element's `kind` says what it is on the map. `:block` and `:rule` are
  boxes for blocks - a rule is a block in a group's interrupt rules;
  `:arm`, `:undecided_arm`, `:rules`, `:body` and `:tray` are a block's
  slots drawn as boxes of their own, `:body` being a group's body, drawn as
  a pane beside its rules; `:marker` is an empty slot's "Nothing here yet";
  `:end` is a final mark where the document finishes, one per outcome it
  finishes with (`done`, and `abandon` where an interrupt rule abandons its
  last step), and the edge into it is an `:edge` that names the outcome;
  `:start` is the filled dot the document starts at, and its edge into the
  first step is a `:start` too;
  `:edge` is a connector, a branch's rejoin among them; `:interrupt` is
  the dashed edge an interrupt rule draws to where it takes its group;
  and `:idle` is the document, described when nothing is selected. A
  branch's description names its arms in order, which is what the band
  over them on the map says. Each description is keyed by the id the map
  draws it under, so the page's `PlanInfo` hook
  (`assets/js/plan_info.mjs`) looks one up by the element under the
  pointer without asking the server.
  """

  alias StatifierBlocks.Describe
  alias StatifierBlocks.Document
  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node
  alias StatifierBlocks.ViewModel.Slot
  alias StatifierExamplesWeb.EventPhrasing
  alias StatifierExamplesWeb.PlanMap
  alias StatifierExamplesWeb.TypeExplanation

  @typedoc "What an element is on the map; see the moduledoc."
  @type kind ::
          :block
          | :rule
          | :arm
          | :undecided_arm
          | :rules
          | :body
          | :tray
          | :marker
          | :end
          | :start
          | :edge
          | :interrupt
          | :idle

  @typedoc "One labelled fact: a single value, or a list of them."
  @type fact :: {String.t(), String.t() | [String.t()]}

  @typedoc """
  One element described. `id` is the map's id for it (`nil` for the idle
  description); `sentence` is left `nil` where it would only repeat
  `title`; `settings` are a block's configured values and `facts`
  everything else a reader needs, both in reading order.
  """
  @type t :: %__MODULE__{
          id: String.t() | nil,
          kind: kind(),
          title: String.t(),
          sentence: String.t() | nil,
          explanation: String.t(),
          settings: [fact()],
          facts: [fact()]
        }

  @enforce_keys [:kind, :title, :explanation]
  defstruct [:id, :kind, :title, :explanation, sentence: nil, settings: [], facts: []]

  @how_to_read "Every box on the map is a step, drawn inside the step that holds it. " <>
                 "The filled dot is where the document starts, and a dot inside a ring " <>
                 "where it finishes: a solid ring when its last step finishes, a dashed " <>
                 "ring when an interrupt rule abandons that step, the outcome named on " <>
                 "the arrow into it. " <>
                 "An arrow runs from a step to the one after it; a dashed arrow runs " <>
                 "from an interrupt rule to where it takes its group, out of it or " <>
                 "back to the head of its body. An hourglass marks a step that waits, " <>
                 "and a clock a message sent after a delay. A box saying " <>
                 "\"#{PlanMap.empty_text()}\" is a slot no step fills yet. " <>
                 "Select a step in the list, or point at the map, to read about it here."

  @undecided "The arm taken when an arm's condition cannot be decided either way - " <>
               "it reads a value the execution does not have, say. Left empty, such a " <>
               "condition counts as not holding, and the execution raises an error event."

  @doc """
  Every element `graph` draws, described, in the order a walk of the graph
  meets them: a box, then what is inside it, then its connectors.

  `graph` is `PlanMap.graph/1` of `view_model`, and `outline` is
  `Describe.outline/3` of the same document.
  """
  @spec elements(PlanMap.t(), ViewModel.t(), Describe.t()) :: [t()]
  def elements(
        %{"children" => children} = graph,
        %ViewModel{} = view_model,
        %Describe{} = outline
      ) do
    context = context(view_model, outline)
    edges = graph |> Map.get("edges", []) |> Enum.map(&edge(&1, context))
    Enum.flat_map(children, &walk(&1, context)) ++ edges
  end

  @doc """
  The document described, for when nothing is selected: its name and
  description, what starts it, how to read the map, and how many steps
  and open slots it has.
  """
  @spec idle(Document.t(), PlanMap.t(), ViewModel.t(), Describe.t()) :: t()
  def idle(%Document{} = document, graph, %ViewModel{}, %Describe{nodes: nodes}) do
    metadata = document.metadata || %{}

    %__MODULE__{
      kind: :idle,
      title: text(metadata["name"]) || document.id,
      sentence: text(metadata["description"]),
      explanation: @how_to_read,
      facts:
        starts(document) ++
          [
            {"Steps", Integer.to_string(max(length(nodes) - 1, 0))},
            {"Open slots", graph |> markers() |> length() |> Integer.to_string()}
          ]
    }
  end

  # What starts the document, in the words the map's start edge carries
  # (`PlanMap.start_text/0`, so the wording changes in one place): a
  # document starts when its host starts an execution of it, and `accepts`
  # names the events it listens for while it runs.
  @spec starts(Document.t()) :: [fact()]
  defp starts(%Document{accepts: accepts}) do
    listens =
      case accepts do
        [_first | _rest] -> accepts
        _none -> "No events"
      end

    [{"What starts it", PlanMap.start_text()}, {"Listens for", listens}]
  end

  # ------------------------------------------------------------------- walk

  @typep context :: %{
           view_model: ViewModel.t(),
           nodes: %{optional(String.t()) => Describe.Node.t()},
           edges: [Describe.Edge.t()],
           positions: %{optional(String.t()) => {String.t(), String.t(), non_neg_integer()}},
           slots: %{optional(String.t()) => {Node.t(), Slot.t()}}
         }

  @spec context(ViewModel.t(), Describe.t()) :: context()
  defp context(view_model, outline) do
    %{
      view_model: view_model,
      nodes: Map.new(outline.nodes, &{&1.id, &1}),
      edges: outline.edges,
      positions: ViewModel.positions(view_model),
      slots: slots(view_model.root, %{})
    }
  end

  # Every slot in the tree, under the id the map gives its box.
  @spec slots(Node.t(), map()) :: map()
  defp slots(%Node{slots: slots} = node, acc) do
    Enum.reduce(slots, acc, fn %Slot{} = slot, acc ->
      acc = Map.put(acc, "#{node.block_id}/#{slot.name}", {node, slot})
      Enum.reduce(slot.children, acc, &slots/2)
    end)
  end

  @spec walk(map(), context()) :: [t()]
  defp walk(graph_node, context) do
    own = describe(graph_node, context)
    inside = graph_node |> Map.get("children", []) |> Enum.flat_map(&walk(&1, context))
    edges = graph_node |> Map.get("edges", []) |> Enum.map(&edge(&1, context))
    interrupts = graph_node |> Map.get("interrupts", []) |> Enum.map(&interrupt(&1, context))
    [own | inside] ++ edges ++ interrupts
  end

  @spec describe(map(), context()) :: t()
  defp describe(%{"kind" => "block", "id" => id}, context), do: block(id, context)

  defp describe(%{"kind" => "empty", "id" => id, "parent" => parent, "slot" => name}, context) do
    {node, slot} = Map.fetch!(context.slots, "#{parent}/#{name}")
    marker(id, node, slot, context)
  end

  defp describe(%{"kind" => "slot", "id" => id, "style" => style}, context) do
    {node, slot} = Map.fetch!(context.slots, id)
    slot(style, id, node, slot, context)
  end

  defp describe(%{"kind" => "end", "id" => id, "outcome" => outcome}, _context) do
    %__MODULE__{
      id: id,
      kind: :end,
      title: "End",
      sentence: "The document finishes: #{outcome}",
      explanation: end_explanation(outcome),
      facts: [{"Outcome", outcome}]
    }
  end

  defp describe(%{"kind" => "start", "id" => id}, _context) do
    %__MODULE__{
      id: id,
      kind: :start,
      title: "Start",
      sentence: PlanMap.start_text(),
      explanation:
        "Where the document starts. An execution of it begins here when its host " <>
          "starts one, and runs the step the arrow from this dot points at first."
    }
  end

  # The solid ring and the dashed one; see `StatifierExamplesWeb.PlanMap`'s
  # "The end".
  @spec end_explanation(String.t()) :: String.t()
  defp end_explanation("abandon"),
    do:
      "Where the document finishes when an interrupt rule abandons its last step, drawn " <>
        "as a dashed ring: the rule leaves the group, and nothing comes after the group."

  defp end_explanation(_done),
    do:
      "Where the document finishes when its last step does, drawn as a solid ring: " <>
        "whichever way that step finishes, nothing comes after it."

  # ----------------------------------------------------------------- blocks

  @spec block(String.t(), context()) :: t()
  defp block(id, context) do
    node = ViewModel.find_node(context.view_model, id)
    rule? = match?(%Describe.Node{kind: :rail}, Map.get(context.nodes, id))

    facts =
      if rule?,
        do: [{"Place", place(id, context)} | rule_facts(id, context)],
        else: [
          {"Place", place(id, context)},
          {"Outcomes", outcomes(id, context)}
          | leaving(id, context)
        ]

    %__MODULE__{
      id: id,
      kind: if(rule?, do: :rule, else: :block),
      title: ViewModel.title(node),
      sentence: second(EventPhrasing.sentence(node), ViewModel.title(node)),
      explanation: TypeExplanation.explain(node),
      settings: settings(node),
      facts: arms(node) ++ facts ++ findings(node)
    }
  end

  # A branch's arms, in the order it tries them, each with its condition:
  # what the map's band over the arms, and the branch's header, say.
  @spec arms(Node.t()) :: [fact()]
  defp arms(%Node{type: "core.branch"} = node) do
    arms =
      for {slot, n} <- Enum.with_index(ViewModel.body_slots(node), 1) do
        case slot.condition do
          condition when is_binary(condition) -> "#{n}. #{slot.label}: #{condition}"
          _none -> "#{n}. #{slot.label}"
        end
      end

    [{"Arms, in order", arms}]
  end

  defp arms(%Node{}), do: []

  # The block's configured values, labelled as its type labels them: the
  # fields `config_schema/1` declares and the type does not hide.
  @spec settings(Node.t()) :: [fact()]
  defp settings(%Node{} = node) do
    node |> ViewModel.shown_fields() |> Enum.map(&{&1.label, value(&1.value)})
  end

  @spec value(term()) :: String.t()
  defp value(nil), do: "Not set"
  defp value(value) when is_binary(value), do: text(value) || "Not set"
  defp value(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp value(value), do: Jason.encode!(value)

  @spec findings(Node.t()) :: [fact()]
  defp findings(%Node{findings: []}), do: []
  defp findings(%Node{findings: findings}), do: [{"Findings", Enum.map(findings, & &1.message)}]

  # Where the block sits, counted the way a reader counts: from one.
  @spec place(String.t(), context()) :: String.t()
  defp place(id, context) do
    case Map.fetch(context.positions, id) do
      :error ->
        "The root: every other step sits inside it"

      {:ok, {parent_id, name, index}} ->
        parent = ViewModel.find_node(context.view_model, parent_id)
        slot = Enum.find(parent.slots, &(&1.name == name))
        of = "#{index + 1} of #{length(slot.children)}"
        placed(parent, slot, of)
    end
  end

  @spec placed(Node.t(), Slot.t(), String.t()) :: String.t()
  defp placed(parent, slot, of) do
    body = ViewModel.body_slots(parent)

    cond do
      ViewModel.rail?(slot) ->
        "Rule #{of} in #{slot.label} of #{named(parent)}"

      ViewModel.tray?(slot) ->
        "Item #{of}, kept to one side in #{named(parent)}"

      length(body) > 1 ->
        arm = Enum.find_index(body, &(&1.name == slot.name)) + 1

        "Step #{of} in #{slot.label}, #{part(parent)} #{arm} of #{length(body)} of " <>
          named(parent)

      true ->
        "Step #{of} in #{slot.label} of #{named(parent)}"
    end
  end

  # Each outcome the block can finish with, and what happens next. The
  # outline's `:sequence` and `:exit` edges carry the outcome names; a block
  # the outline draws no edge from says only that it finishes where it is.
  @spec outcomes(String.t(), context()) :: [String.t()]
  defp outcomes(id, context) do
    case Enum.filter(context.edges, &(&1.from == {:block, id} and &1.kind in [:sequence, :exit])) do
      [] ->
        names = context.nodes |> Map.get(id, %{outcomes: []}) |> Map.get(:outcomes)
        where = finishes(id, context)
        Enum.map(names, &"#{&1}: #{where}")

      edges ->
        for edge <- edges, name <- edge.outcomes, do: "#{name}: #{onward(edge, context)}"
    end
  end

  @spec finishes(String.t(), context()) :: String.t()
  defp finishes(id, context) do
    case Map.fetch(context.positions, id) do
      :error -> "the document finishes"
      {:ok, {parent_id, _slot, _index}} -> "hands back to #{named(parent_id, context)}"
    end
  end

  @spec onward(Describe.Edge.t(), context()) :: String.t()
  defp onward(%Describe.Edge{kind: :sequence, to: {:block, to}}, context),
    do: "goes on to #{sentence_of(to, context)}"

  defp onward(%Describe.Edge{kind: :exit, container: container}, context),
    do: "finishes #{named(container, context)}"

  # The interrupt rules that can take control away from this block: every
  # rule of every group it sits inside, or is. A rule itself is described
  # by `rule_facts/2` instead, so a group's rules are never listed as
  # leaving one of themselves.
  @spec leaving(String.t(), context()) :: [fact()]
  defp leaving(id, context) do
    groups = [id | enclosing(id, context)]

    case Enum.flat_map(groups, &interrupts(&1, context)) do
      [] -> []
      rules -> [{"Interrupt rules", rules}]
    end
  end

  # The blocks above `id`, nearest first.
  @spec enclosing(String.t(), context()) :: [String.t()]
  defp enclosing(id, context) do
    case Map.get(context.nodes, id) do
      %Describe.Node{parent: nil} ->
        []

      %Describe.Node{parent: parent} ->
        [parent | enclosing(parent, context)]

      nil ->
        []
    end
  end

  @spec interrupts(String.t(), context()) :: [String.t()]
  defp interrupts(group, context) do
    for %Describe.Edge{kind: :interrupt, container: ^group} = edge <- context.edges,
        do: interrupt_line(edge, context)
  end

  @spec interrupt_line(Describe.Edge.t(), context()) :: String.t()
  defp interrupt_line(%Describe.Edge{} = edge, context) do
    "#{on(edge.event)}, #{does(edge)} #{named(edge.container, context)}" <> history(edge)
  end

  # What sets a rule off: its event in words where the library world has
  # them (`StatifierExamplesWeb.EventPhrasing`), its name where not.
  @spec on(String.t() | nil) :: String.t()
  defp on(event) do
    case EventPhrasing.phrase(event) do
      nil -> "On #{event || "its event"}"
      words -> "When #{words}"
    end
  end

  @spec does(Describe.Edge.t()) :: String.t()
  defp does(%Describe.Edge{to: {:body, _group}}), do: "resumes"
  defp does(%Describe.Edge{}), do: "abandons"

  @spec history(Describe.Edge.t()) :: String.t()
  defp history(%Describe.Edge{history: nil}), do: ""
  defp history(%Describe.Edge{history: history}), do: " at #{history} history"

  # A rule's own facts: the event it listens for and what it does to its
  # group, off the outline's `:interrupt` edge from it.
  @spec rule_facts(String.t(), context()) :: [fact()]
  defp rule_facts(id, context) do
    case Enum.find(context.edges, &(&1.kind == :interrupt and &1.from == {:block, id})) do
      nil ->
        []

      edge ->
        [
          {"Listens for", edge.event || "An event not named yet"},
          {"Then", "#{does(edge)} #{named(edge.container, context)}#{history(edge)}"}
        ]
    end
  end

  # ------------------------------------------------------------------ slots

  @spec slot(String.t(), String.t(), Node.t(), Slot.t(), context()) :: t()
  defp slot("rail", id, node, slot, context) do
    %__MODULE__{
      id: id,
      kind: :rules,
      title: slot.label,
      explanation:
        "The interrupt rules of #{named(node)}: each one waits for its event whichever " <>
          "step of the group is running.",
      facts: [{"Group", named(node)}, {"Rules", sentences(slot, context)}]
    }
  end

  defp slot("body", id, node, slot, context) do
    %__MODULE__{
      id: id,
      kind: :body,
      title: slot.label,
      explanation:
        "The body of #{named(node)}: its steps, run in order, which the group's " <>
          "interrupt rules watch from beside it.",
      facts: [{"Group", named(node)}, {"Steps", sentences(slot, context)}]
    }
  end

  defp slot("tray", id, node, slot, context) do
    %__MODULE__{
      id: id,
      kind: :tray,
      title: slot.label,
      explanation: "Kept to one side: the steps here are not part of the flow and do not run.",
      facts: [{"Of", named(node)}, {"Holds", sentences(slot, context)}]
    }
  end

  defp slot(_arm, id, node, %Slot{name: "undecided"} = slot, context) do
    %__MODULE__{
      id: id,
      kind: :undecided_arm,
      title: slot.label,
      explanation: @undecided,
      facts: arm_facts(node, slot, context)
    }
  end

  defp slot(_arm, id, node, slot, context) do
    %__MODULE__{
      id: id,
      kind: :arm,
      title: slot.label,
      explanation: arm_explanation(node, slot),
      facts: arm_facts(node, slot, context)
    }
  end

  @spec arm_explanation(Node.t(), Slot.t()) :: String.t()
  defp arm_explanation(node, %Slot{name: "otherwise"}) do
    "The arm #{ViewModel.title(node)} takes when no arm before it holds."
  end

  defp arm_explanation(node, slot) do
    case ViewModel.fan_label(node) do
      "one of" ->
        "One arm of #{ViewModel.title(node)}: its steps run when this is the first arm, " <>
          "in the order drawn, whose condition holds."

      "all of" ->
        "One lane of #{ViewModel.title(node)}: it runs at the same time as the others."

      nil ->
        "#{slot.label}, one part of #{ViewModel.title(node)}, drawn as a box of its own."
    end
  end

  @spec arm_facts(Node.t(), Slot.t(), context()) :: [fact()]
  defp arm_facts(node, slot, context) do
    body = ViewModel.body_slots(node)
    arm = Enum.find_index(body, &(&1.name == slot.name)) + 1

    [
      condition(node, slot),
      {"Place", "#{String.capitalize(part(node))} #{arm} of #{length(body)} of #{named(node)}"},
      goes_to(node, slot, context),
      {"Steps", slot |> ViewModel.flow_children() |> length() |> Integer.to_string()}
    ]
    |> Enum.reject(&is_nil/1)
  end

  # What one of a block's body slots is called: an arm of a block that takes
  # one of them, a lane of one that runs all of them, else a part.
  @spec part(Node.t()) :: String.t()
  defp part(node) do
    case ViewModel.fan_label(node) do
      "one of" -> "arm"
      "all of" -> "lane"
      nil -> "part"
    end
  end

  # An arm's condition as the author wrote it. `otherwise` and `undecided`
  # have none of their own; a slot of a block that does not choose between
  # its slots has no condition to state.
  @spec condition(Node.t(), Slot.t()) :: fact() | nil
  defp condition(_node, %Slot{condition: condition}) when is_binary(condition),
    do: {"Condition", condition}

  defp condition(_node, %Slot{name: "otherwise"}),
    do: {"Condition", "None of the arms before it holds"}

  defp condition(_node, %Slot{name: "undecided"}),
    do: {"Condition", "An arm's condition cannot be decided"}

  defp condition(node, _slot) do
    if ViewModel.fan_label(node) == "one of", do: {"Condition", "None written yet"}, else: nil
  end

  # Where taking this arm leads, off the outline's `:branch` edge for it.
  # The outline gives one such edge per wired arm, in slot order, and an
  # empty `undecided` is not wired - so the edges pair with the wired slots
  # one for one.
  @spec goes_to(Node.t(), Slot.t(), context()) :: fact() | nil
  defp goes_to(node, slot, context) do
    id = node.block_id

    picks = Enum.filter(context.edges, &(&1.kind == :branch and &1.container == id))

    wired =
      node
      |> ViewModel.body_slots()
      |> Enum.reject(&(&1.name == "undecided" and ViewModel.flow_children(&1) == []))

    case Enum.find(Enum.zip(wired, picks), fn {wired_slot, _edge} -> wired_slot == slot end) do
      {_slot, edge} when length(wired) == length(picks) ->
        {"Goes to", endpoint(edge.to, context)}

      _unwired ->
        unwired(slot, picks)
    end
  end

  @spec unwired(Slot.t(), [Describe.Edge.t()]) :: fact() | nil
  defp unwired(%Slot{name: "undecided"}, [_pick | _rest]),
    do: {"Goes to", "Nowhere yet: an undecided condition counts as not holding"}

  defp unwired(_slot, _picks), do: nil

  @spec endpoint(Describe.Edge.endpoint(), context()) :: String.t()
  defp endpoint({:exit, id}, context), do: "the end of #{named(id, context)}"
  defp endpoint({_block_or_body, id}, context), do: sentence_of(id, context)

  @spec sentences(Slot.t(), context()) :: [String.t()] | String.t()
  defp sentences(%Slot{children: []}, _context), do: "None yet"

  defp sentences(%Slot{children: children}, context),
    do: Enum.map(children, &sentence_of(&1.block_id, context))

  # ---------------------------------------------------------------- markers

  @spec marker(String.t(), Node.t(), Slot.t(), context()) :: t()
  defp marker(id, node, slot, context) do
    facts =
      [
        {"Slot", "#{slot.label} of #{named(node)}"},
        condition(node, slot),
        goes_to(node, slot, context)
      ]
      |> Enum.reject(&is_nil/1)

    %__MODULE__{
      id: id,
      kind: :marker,
      title: PlanMap.empty_text(),
      explanation: "An empty slot: no step is written here yet.",
      facts: facts
    }
  end

  # ------------------------------------------------------------------ edges

  @spec edge(map(), context()) :: t()
  defp edge(%{"id" => id, "kind" => "start", "targets" => [to]}, context) do
    first = first_step(to, context)

    %__MODULE__{
      id: id,
      kind: :start,
      title: "Start",
      sentence: "#{PlanMap.start_text()}, #{first}",
      explanation:
        "The arrow from the start dot: when the host starts an execution of the " <>
          "document, the step it points at runs first.",
      facts: [{"What starts it", PlanMap.start_text()}, {"First step", first}]
    }
  end

  defp edge(%{"id" => id, "kind" => "end", "sources" => [from], "outcome" => outcome}, context) do
    rules =
      case {outcome, interrupts(from, context)} do
        {"abandon", [_first | _rest] = lines} -> [{"Interrupt rules", lines}]
        _none -> []
      end

    %__MODULE__{
      id: id,
      kind: :edge,
      title: "Finish",
      sentence: "#{finishing(outcome, from, context)}, the document finishes: #{outcome}",
      explanation:
        "The arrow into a final mark: the document's last step is behind it, so when " <>
          "control leaves that step this way, the document finishes with the outcome " <>
          "it names.",
      facts: [{"From", sentence_of(from, context)}, {"Outcome", outcome}] ++ rules
    }
  end

  defp edge(
         %{"id" => id, "kind" => "rejoin", "sources" => [from], "targets" => [to]} = e,
         context
       ) do
    onto = target(to, context)

    %__MODULE__{
      id: id,
      kind: :edge,
      title: "Rejoin",
      sentence: "After whichever arm of #{sentence_of(from, context)} runs, #{onto}",
      explanation:
        "Where the arms of a branch come back together: whichever arm runs, when it " <>
          "finishes, what this points at comes next.",
      facts:
        [{"From", sentence_of(from, context)}, {"To", onto}] ++
          outcome(e) ++
          carries(from, to, context) ++ [{"Inside", finishes_inside(from, context)}]
    }
  end

  defp edge(%{"id" => id, "sources" => [from], "targets" => [to]}, context) do
    %__MODULE__{
      id: id,
      kind: :edge,
      title: "Connector",
      sentence: "After #{sentence_of(from, context)}, #{sentence_of(to, context)}",
      explanation:
        "When the step it leaves finishes, the step it points at starts. Connectors " <>
          "follow the order of the steps; nobody draws them by hand.",
      facts:
        [{"From", sentence_of(from, context)}, {"To", sentence_of(to, context)}] ++
          carries(from, to, context) ++ [{"Inside", finishes_inside(from, context)}]
    }
  end

  # How the last step hands control to an end: by finishing, or by one of
  # its interrupt rules abandoning it.
  @spec finishing(String.t(), String.t(), context()) :: String.t()
  defp finishing("abandon", from, context),
    do: "When an interrupt rule abandons #{named(from, context)}"

  defp finishing(_done, from, context), do: "When #{sentence_of(from, context)} finishes"

  # The outcome an edge into an end mark names; none for any other edge.
  @spec outcome(map()) :: [fact()]
  defp outcome(%{"outcome" => outcome}), do: [{"Outcome", outcome}]
  defp outcome(%{}), do: []

  # A dashed interrupt edge, off the outline's `:interrupt` edge from the
  # same rule: the event it waits for, what it does to its group, and where
  # the edge lands.
  @spec interrupt(map(), context()) :: t()
  defp interrupt(%{"id" => id, "sources" => [rule], "targets" => [group], "to" => to}, context) do
    described =
      Enum.find(
        context.edges,
        &(&1.kind == :interrupt and &1.from == {:block, rule} and &1.container == group)
      )

    %__MODULE__{
      id: id,
      kind: :interrupt,
      title: "Interrupt",
      sentence: described && interrupt_line(described, context),
      explanation:
        "A dashed arrow: not a step that follows the one before it, but a way out of " <>
          "the group, or back to the head of its body, taken whenever the rule's event " <>
          "arrives, whichever step of the group is running.",
      facts:
        Enum.reject(
          [
            {"Rule", sentence_of(rule, context)},
            described && {"Listens for", described.event || "An event not named yet"},
            {"Goes to", lands(to, group, context)}
          ],
          &is_nil/1
        )
    }
  end

  @spec lands(String.t(), String.t(), context()) :: String.t()
  defp lands("exit", group, context), do: "the end of #{named(group, context)}"
  defp lands(_body, group, context), do: "the head of the body of #{named(group, context)}"

  # The outcomes the outline's `:sequence` edge between the same two blocks
  # carries; none for an edge into the end mark, which is not a block.
  @spec carries(String.t(), String.t(), context()) :: [fact()]
  defp carries(from, to, context) do
    described =
      Enum.find(
        context.edges,
        &(&1.kind == :sequence and &1.from == {:block, from} and &1.to == {:block, to})
      )

    case described do
      %Describe.Edge{outcomes: [_first | _rest] = names} -> [{"Carries", Enum.join(names, ", ")}]
      _none -> []
    end
  end

  # A rejoin's target: the next step, or the end mark, which is no block.
  @spec target(String.t(), context()) :: String.t()
  defp target(id, context) do
    case ViewModel.find_node(context.view_model, id) do
      nil -> "the document finishes"
      node -> EventPhrasing.sentence(node)
    end
  end

  # What the start edge points at: the first step, or, in a document with
  # none yet, its root's empty marker, which is no block.
  @spec first_step(String.t(), context()) :: String.t()
  defp first_step(id, context) do
    case ViewModel.find_node(context.view_model, id) do
      nil -> "no step yet (#{PlanMap.empty_text()})"
      node -> EventPhrasing.sentence(node)
    end
  end

  @spec finishes_inside(String.t(), context()) :: String.t()
  defp finishes_inside(id, context) do
    {parent_id, _slot, _index} = Map.fetch!(context.positions, id)
    named(parent_id, context)
  end

  # ---------------------------------------------------------------- helpers

  @spec markers(map()) :: [map()]
  defp markers(%{"kind" => "empty"} = marker), do: [marker]
  defp markers(%{} = node), do: node |> Map.get("children", []) |> Enum.flat_map(&markers/1)

  @spec sentence_of(String.t(), context()) :: String.t()
  defp sentence_of(id, context),
    do: context.view_model |> ViewModel.find_node(id) |> EventPhrasing.sentence()

  @spec named(String.t(), context()) :: String.t()
  defp named(id, context) when is_binary(id),
    do: context.view_model |> ViewModel.find_node(id) |> named()

  # A container named for a reader: its title, and its sentence where that
  # says more than the title does.
  @spec named(Node.t()) :: String.t()
  defp named(%Node{} = node) do
    case second(EventPhrasing.sentence(node), ViewModel.title(node)) do
      nil -> ViewModel.title(node)
      sentence -> "#{ViewModel.title(node)} (#{sentence})"
    end
  end

  @spec second(String.t(), String.t()) :: String.t() | nil
  defp second(same, same), do: nil
  defp second(sentence, _title), do: sentence

  @spec text(term()) :: String.t() | nil
  defp text(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp text(_other), do: nil
end
