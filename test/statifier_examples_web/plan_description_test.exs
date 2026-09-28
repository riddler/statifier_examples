defmodule StatifierExamplesWeb.PlanDescriptionTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Core.Await
  alias StatifierBlocks.Core.Group
  alias StatifierBlocks.Core.Wait
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Document
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.PlanDescription
  alias StatifierExamplesWeb.PlanMap

  # The library fixtures are the two teaching documents the region is read
  # against; between them every kind the map draws is drawn at least once.
  @library ["library_loan", "patron_registration"]

  describe "elements/4" do
    # Every element the map draws has exactly one description, keyed by the
    # id the map draws it under - asked of every fixture, because a document
    # whose shape no other fixture has (a parallel, a composite, a drafts
    # shelf, a host type) is the one a single-fixture test misses.
    #
    # Sabotage: made walk/2 skip a graph node's "edges"; this went red on
    # the first fixture with a connector. Reverted from a copy.
    test "describes every element the map draws, once, under the map's id" do
      for fixture <- Charts.fixtures() do
        {graph, descriptions, _idle} = described(fixture.key)

        assert Enum.map(descriptions, & &1.id) |> Enum.sort() == graph_ids(graph),
               "#{fixture.key}: the descriptions are not the map's elements"

        for description <- descriptions do
          assert is_binary(description.title) and description.title != ""
          assert is_binary(description.explanation) and description.explanation != ""
        end
      end
    end

    # Sabotage: made describe/2 answer :block for a rail block; the :rule
    # kind went missing from both fixtures and this went red. Reverted from
    # a copy.
    test "the two library fixtures draw every kind between them" do
      kinds =
        @library
        |> Enum.flat_map(fn key -> key |> described() |> elem(1) |> Enum.map(& &1.kind) end)
        |> MapSet.new()

      for kind <- [
            :block,
            :rule,
            :arm,
            :undecided_arm,
            :rules,
            :body,
            :marker,
            :end,
            :start,
            :edge,
            :interrupt
          ] do
        assert kind in kinds, "no #{kind} described"
      end
    end

    # The settings are the type's `config_schema/1` fields, labelled as the
    # type labels them, with the block's values.
    #
    # Sabotage: made settings/1 read `&1.key` for the label; this went red
    # on "Wait for". Reverted from a copy.
    test "a block's settings are its config_schema fields and their values" do
      loan = by_id("library_loan")

      assert loan["blk_ll_loan_period"].settings == [
               {label(Wait, "duration"), "21d"}
             ]

      assert loan["blk_ll_late_return"].settings == [
               {label(Await, "event"), "copy.returned"},
               {label(Await, "timeout"), "14d"}
             ]

      # An optional field the author left empty says so rather than
      # drawing nothing.
      assert {label(Await, "timeout"), "Not set"} in by_id("patron_registration")["blk_pr_email"].settings
    end

    # Sabotage: dropped the `index + 1` in place/2 (counted from zero); this
    # went red. Reverted from a copy.
    test "a block's place counts from one and names its container" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_root"], "Place") == "The root: every other step sits inside it"

      assert fact(loan["blk_ll_loan_period"], "Place") ==
               "Step 1 of 1 in Steps of Group (Run interruptible steps)"

      assert fact(loan["blk_ll_late_return"], "Place") =~
               ~r/^Step 2 of 2 in Otherwise, arm 3 of 4 of Branch \(/

      assert fact(loan["blk_ll_reported_lost"], "Place") ==
               "Rule 2 of 2 in Interrupt rules of Group (Run interruptible steps)"
    end

    # Every outcome name the type declares, and where each one goes, off the
    # outline's own edges.
    #
    # Sabotage: made onward/2 answer the edge's source instead of its
    # target; this went red. Reverted from a copy.
    test "a block's outcomes say where each one goes" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_overdue_notice"], "Outcomes") == [
               "done: goes on to Wait until the copy is returned, giving up after 14d"
             ]

      assert [received, timed_out] = fact(loan["blk_ll_late_return"], "Outcomes")
      assert received =~ ~r/^received: finishes Branch/
      assert timed_out =~ ~r/^timed_out: finishes Branch/

      assert fact(loan["blk_ll_root"], "Outcomes") == ["done: the document finishes"]
    end

    # A step inside a group can be left by the group's rules; a step outside
    # it cannot, and a rule is not left by its own group's rules.
    #
    # Sabotage: left the block itself out of the groups leaving/2 asks, so
    # a group lost its own rules; this went red. Reverted from a copy.
    test "the interrupt rules that can leave a block" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_loan_period"], "Interrupt rules") == [
               "When the copy is returned, abandons Group (Run interruptible steps)",
               "When the copy is reported lost, abandons Group (Run interruptible steps)"
             ]

      assert fact(loan["blk_ll_on_loan"], "Interrupt rules") ==
               fact(loan["blk_ll_loan_period"], "Interrupt rules")

      assert fact(loan["blk_ll_close"], "Interrupt rules") == nil
      assert fact(loan["blk_ll_returned_early"], "Interrupt rules") == nil
    end

    # Sabotage: made does/1 answer "resumes" for every edge; this went red.
    # Reverted from a copy.
    test "a rule says what it listens for and what it does to its group" do
      rule = by_id("patron_registration")["blk_pr_expired"]

      assert rule.kind == :rule
      assert fact(rule, "Listens for") == "registration.deadline"
      assert fact(rule, "Then") == "abandons Group (Run interruptible steps)"
      assert fact(rule, "Outcomes") == nil

      rules = by_id("patron_registration")["blk_pr_verify/interrupts"]
      assert rules.kind == :rules

      assert fact(rules, "Rules") == [
               "When the registration is abandoned, abandon",
               "When the registration week is up, abandon"
             ]
    end

    # A group's body is a pane of its own on the map, and says which group
    # it is the body of and which steps it holds, in order.
    #
    # Sabotage: made slot/5 describe a "body" slot as an arm; the :body
    # kind went missing and this went red. Reverted from a copy.
    test "a group's body pane says whose body it is and what it holds" do
      body = by_id("patron_registration")["blk_pr_verify/body"]

      assert body.kind == :body
      assert body.title == "Steps"
      assert fact(body, "Group") == "Group (Run interruptible steps)"

      assert fact(body, "Steps") == [
               "In 7 days, send word that the registration week is up",
               "Wait until the email address is verified",
               ~s(Decide: When "child", otherwise),
               "Send word that the patron is welcomed"
             ]
    end

    # Sabotage: paired the branch edges with the wired slots in reverse
    # order; the loan's arms went to the wrong steps and this went red.
    # Reverted from a copy.
    test "an arm states its condition and where taking it goes" do
      loan = by_id("library_loan")

      renew = loan["blk_ll_due/arm_renew"]
      assert renew.kind == :arm
      assert fact(renew, "Condition") == "copy.holds == 0 AND loan.renewals < 2"
      assert fact(renew, "Goes to") == "Send word that the loan is renewed"
      assert fact(renew, "Place") =~ ~r/^Arm 2 of 4 of Branch/

      otherwise = loan["blk_ll_due/otherwise"]
      assert fact(otherwise, "Condition") == "None of the arms before it holds"
      assert fact(otherwise, "Goes to") == "Send word that the loan is overdue"
      assert fact(otherwise, "Steps") == "2"
    end

    # The undecided arm is described as itself on both fixtures: wired on the
    # patron registration, empty on the loan.
    #
    # Sabotage: dropped the "undecided" clause of slot/5; both went to :arm
    # and this went red. Reverted from a copy.
    test "the undecided arm, wired and unwired" do
      wired = by_id("patron_registration")["blk_pr_age/undecided"]
      assert wired.kind == :undecided_arm
      assert fact(wired, "Goes to") == "Send word that the patron is asked to visit"

      unwired = by_id("library_loan")["blk_ll_due/undecided"]
      assert unwired.kind == :undecided_arm

      assert fact(unwired, "Goes to") ==
               "Nowhere yet: an undecided condition counts as not holding"

      assert fact(unwired, "Steps") == "0"
    end

    # Sabotage: made endpoint/2 answer the sentence of an `{:exit, id}`
    # container rather than "the end of" it; this went red. Reverted from a
    # copy.
    test "an empty slot's marker names its slot and where it leads" do
      marker = by_id("patron_registration")["blk_pr_age/otherwise/empty"]

      assert marker.kind == :marker
      assert marker.title == PlanMap.empty_text()
      assert fact(marker, "Slot") =~ ~r/^Otherwise of Branch/
      assert fact(marker, "Goes to") =~ ~r/^the end of Branch/
    end

    # Each dashed interrupt edge the map draws is described under its own
    # map id, off the outline's interrupt edge from the same rule.
    #
    # Sabotage: made lands/3 answer the exit for a resume edge too; this
    # went red. Reverted from a copy.
    test "an interrupt edge says its rule, its event and where it lands" do
      loan = by_id("library_loan")
      edge = loan["blk_ll_returned_early->blk_ll_on_loan/exit"]

      assert edge.kind == :interrupt

      assert edge.sentence ==
               "When the copy is returned, abandons Group (Run interruptible steps)"

      assert fact(edge, "Rule") =~ "the copy is returned"
      assert fact(edge, "Listens for") == "copy.returned"
      assert fact(edge, "Goes to") == "the end of Group (Run interruptible steps)"

      resumes =
        for fixture <- Charts.fixtures(),
            {_id, %PlanDescription{kind: :interrupt} = edge} <- by_id(fixture.key),
            String.ends_with?(edge.id, "/body"),
            do: edge

      for edge <- resumes do
        assert fact(edge, "Goes to") =~ ~r/^the head of the body of /
        assert edge.sentence =~ "resumes"
      end
    end

    # Sabotage: made edge/2 look for an `:exit` edge instead of the
    # `:sequence` one; the connector carried nothing and this went red.
    # Reverted from a copy.
    test "a connector names both ends and what it carries" do
      edge = by_id("library_loan")["blk_ll_overdue_notice->blk_ll_late_return"]

      assert edge.kind == :edge
      assert fact(edge, "From") == "Send word that the loan is overdue"
      assert fact(edge, "To") == "Wait until the copy is returned, giving up after 14d"
      assert fact(edge, "Carries") == "done"
      assert fact(edge, "Inside") =~ ~r/^Branch \(/
    end

    # The map's Branch marks have their words here: a branch names its arms
    # in the order it tries them, a rejoin says where the arms come back
    # together, and the end mark says the document finishes there.
    #
    # Sabotage: made arms/1 answer [] for a branch; this went red. Made the
    # rejoin clause of edge/2 title itself "Connector"; this went red. Made
    # the end mark :marker; this went red. Each reverted from a copy.
    test "a branch's arms, its rejoin and the end mark are described" do
      loan = by_id("library_loan")

      assert fact(loan["blk_ll_due"], "Arms, in order") == [
               ~s(1. When "returned": loan.returned),
               ~s(2. When "renew": copy.holds == 0 AND loan.renewals < 2),
               "3. Otherwise",
               "4. Cannot be decided"
             ]

      assert fact(loan["blk_ll_close"], "Arms, in order") == nil

      rejoin = loan["blk_ll_due->blk_ll_root/end/done"]
      assert %PlanDescription{kind: :edge, title: "Rejoin"} = rejoin
      assert fact(rejoin, "To") == "the document finishes"
      assert fact(rejoin, "Outcome") == "done"
      assert fact(rejoin, "Inside") =~ ~r/^Sequence/

      assert %PlanDescription{kind: :end, title: "End"} = loan["blk_ll_root/end/done"]

      patron = by_id("patron_registration")["blk_pr_age->blk_pr_welcome"]
      assert %PlanDescription{kind: :edge, title: "Rejoin"} = patron
      assert fact(patron, "To") == "Send word that the patron is welcomed"
    end

    # Each end mark says the document finishes there and with which
    # outcome, the solid ring and the dashed one told apart in words; the
    # edge into an abandon end names the rules that abandon the last step.
    # No other edge carries an outcome.
    #
    # Sabotage: made end_explanation/1 answer the done text for every
    # outcome; this went red. Made the end clause of edge/2 leave out the
    # interrupt rules; this went red. Made outcome/1 answer an Outcome fact
    # for a rejoin into a step; this went red. Each reverted from a copy.
    test "every end mark and the edge into it name the outcome" do
      patron = by_id("patron_registration")

      done = patron["blk_pr_root/end/done"]

      assert %PlanDescription{kind: :end, title: "End", sentence: "The document finishes: done"} =
               done

      assert fact(done, "Outcome") == "done"
      assert done.explanation =~ "solid ring"

      abandon = patron["blk_pr_root/end/abandon"]
      assert %PlanDescription{kind: :end, sentence: "The document finishes: abandon"} = abandon
      assert fact(abandon, "Outcome") == "abandon"
      assert abandon.explanation =~ "dashed ring"

      into_done = patron["blk_pr_verify->blk_pr_root/end/done"]
      assert %PlanDescription{kind: :edge, title: "Finish"} = into_done

      assert into_done.sentence ==
               "When Run interruptible steps finishes, the document finishes: done"

      assert fact(into_done, "Outcome") == "done"
      assert fact(into_done, "Interrupt rules") == nil

      into_abandon = patron["blk_pr_verify->blk_pr_root/end/abandon"]
      assert %PlanDescription{kind: :edge, title: "Finish"} = into_abandon
      assert into_abandon.sentence =~ ~r/^When an interrupt rule abandons Group/
      assert fact(into_abandon, "Outcome") == "abandon"
      assert [_one, _two] = fact(into_abandon, "Interrupt rules")

      for key <- @library,
          {id, %PlanDescription{kind: :edge} = edge} <- by_id(key),
          not String.contains?(id, "/end/") do
        assert fact(edge, "Outcome") == nil, "#{key}: #{id}"
      end
    end

    # The start dot and its edge: where the document starts, in the map's
    # own sentence, and the step that runs first. The loan's events are not
    # the edge's: the idle description lists them as what it listens for.
    #
    # Sabotage: made describe/2 answer :end for the start dot; this went
    # red. Reverted from a copy.
    test "the start dot and its edge are described" do
      loan = by_id("library_loan")

      assert %PlanDescription{kind: :start, title: "Start", sentence: "Starts when told to"} =
               loan["blk_ll_root/start"]

      edge = loan["blk_ll_root/start->blk_ll_on_loan"]
      assert %PlanDescription{kind: :start, title: "Start"} = edge
      assert fact(edge, "What starts it") == "Starts when told to"
      assert fact(edge, "First step") == "Run interruptible steps"
      refute edge.sentence =~ "copy.returned"
    end

    # The two shapes no fixture has: a document with no step yet, whose
    # edge goes into the empty marker, and a root drawn with its flow in a
    # pane of its own, whose edge the graph itself carries.
    #
    # Sabotage: made the start edge read its first step with target/2,
    # which calls a marker "the document finishes"; this went red. Made
    # elements/3 drop the graph's own edges; this went red. Each reverted
    # from a copy.
    test "a start into an empty slot, and one the graph carries, are described" do
      empty = Block.new("core.sequence", id: "root", slots: %{"body" => []})

      assert %{"root/start->root/body/empty" => edge} = describe_root(empty)
      assert fact(edge, "First step") == "no step yet (#{PlanMap.empty_text()})"

      group =
        Block.new("core.group",
          id: "held",
          slots: %{
            "body" => [
              Block.new("core.await", id: "wait", config: %{"event" => "hold.collected"})
            ],
            "interrupts" => []
          }
        )

      assert %{"held/start->held" => edge, "held/start" => %{kind: :start}} = describe_root(group)
      assert fact(edge, "First step") == "Run interruptible steps"
    end
  end

  describe "idle/4" do
    # Sabotage: counted the root among the steps; this went red. Reverted
    # from a copy. Sabotage: cut the dotted timer arrow from the how-to-read
    # line; this went red. Reverted from a copy. Sabotage: cut the dashed arrow from the how-to-read
    # line; this went red. Reverted from a copy. Sabotage: cut the ring
    # from the how-to-read line; this went red. Reverted from a copy.
    test "the document: its name, description, what starts it, and its counts" do
      {_graph, _descriptions, loan} = described("library_loan")

      assert loan.kind == :idle
      assert loan.id == nil
      assert loan.title == "Riverbend Public Library loan"
      assert loan.sentence =~ "A patron borrows a copy"
      assert loan.explanation =~ PlanMap.empty_text()
      assert loan.explanation =~ "a dashed arrow runs from an interrupt rule"
      assert loan.explanation =~ "a dot inside a ring where it finishes"
      assert loan.explanation =~ "An hourglass marks a step that waits"
      assert loan.explanation =~ "a clock a message sent after a delay"
      assert loan.explanation =~ "a dotted arrow, labelled with the delay"
      assert loan.explanation =~ "or point at the map"
      assert fact(loan, "What starts it") == "Starts when told to"
      assert fact(loan, "Listens for") == ["copy.returned", "copy.reported_lost"]
      assert fact(loan, "Steps") == "9"
      assert fact(loan, "Open slots") == "1"

      {_graph, _descriptions, patron} = described("patron_registration")
      assert patron.title == "Riverbend Public Library patron registration"
      assert fact(patron, "Steps") == "10"
      assert fact(patron, "Open slots") == "1"
    end

    # Sabotage: made starts/1 answer an empty list for a document that
    # accepts nothing; this went red. Reverted from a copy.
    test "a document with no name, description or accepted events" do
      {:ok, fixture} = Charts.fixture("library_loan")
      document = %{fixture.document | metadata: %{}, accepts: []}
      view_model = ViewModel.build(document, Charts.palette(), [])
      outline = Describe.outline(document, Charts.palette(), [])

      idle = PlanDescription.idle(document, PlanMap.graph(view_model), view_model, outline)

      assert idle.title == document.id
      assert idle.sentence == nil
      assert fact(idle, "Listens for") == "No events"
    end
  end

  describe "a block's explanation" do
    # What a block's type does is the type's own paragraph, asked of
    # `BlockType.explain/1` through the page's palette, for every block of
    # every fixture: a core type's `explain/0`, a host type's palette
    # description. No text of the host's own stands in for either.
    #
    # Sabotage: made explain/2 answer the undescribed line for every
    # resolved block; this went red. Reverted from a copy.
    test "is the type's own explanation, through the palette, for every block" do
      for fixture <- Charts.fixtures() do
        view_model = ViewModel.build(fixture.document, Charts.palette(), [])
        {_graph, descriptions, _idle} = described(fixture.key)

        for %PlanDescription{kind: kind, id: id, explanation: explanation} <- descriptions,
            kind in [:block, :rule] do
          node = ViewModel.find_node(view_model, id)
          {:ok, ref} = Palette.fetch(Charts.palette(), node.type)

          assert explanation == BlockType.explain(ref), "#{fixture.key}: #{id}"
        end
      end
    end

    # The registration's group reads the paragraph `core.group` declares,
    # and a host type that declares none reads its palette description.
    #
    # Sabotage: made explain/2 look the type up in `Palette.core()` rather
    # than the palette it is handed; the host type's line went missing and
    # this went red. Reverted from a copy.
    test "a core type reads its callback, a host type its palette description" do
      assert by_id("patron_registration")["blk_pr_verify"].explanation == Group.explain()

      {:ok, fixture} = Charts.fixture("card_processing")
      view_model = ViewModel.build(fixture.document, Charts.palette(), [])
      node = ViewModel.find_node(view_model, "blk_cp_intake")
      {:ok, ref} = Palette.fetch(Charts.palette(), node.type)

      refute Palette.declares?(ref, :explain, 0)
      assert is_binary(node.entry.description) and node.entry.description != ""
      assert by_id("card_processing")["blk_cp_intake"].explanation == node.entry.description
    end

    # A block the palette cannot resolve says so: the package has nothing
    # to explain it with.
    #
    # Sabotage: dropped the unresolvable clause of explain/2; this went
    # red. Reverted from a copy.
    test "a block of a type the palette does not know says so" do
      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [Block.new("nowhere.unknown", id: "lost")]}
        )

      assert describe_root(root)["lost"].explanation =~ "does not know"
    end
  end

  describe "timer edges" do
    # The registration's deadline send arms the rule that abandons the
    # registration: its dotted edge is described in the package's own line
    # for it, with the event read as words, and names both ends, the event
    # and the delay.
    #
    # Sabotage: made elements/4 leave the graph's timers out; this went
    # red here and in the every-element test. Reverted from a copy.
    test "the registration's deadline edge says which rule hears it, and when" do
      id = "blk_pr_deadline->blk_pr_expired/timer"
      assert %PlanDescription{kind: :timer} = timer = by_id("patron_registration")[id]
      assert timer.title == "Timer"

      assert timer.sentence ==
               "In 7 days, the registration week is up reaches " <>
                 "When the registration week is up, abandon"

      assert timer.explanation =~ "dotted arrow"
      assert fact(timer, "Sent by") == "In 7 days, send word that the registration week is up"
      assert fact(timer, "Heard by") == "When the registration week is up, abandon"
      assert fact(timer, "Event") == "registration.deadline"
      assert fact(timer, "Delay") == "7d"
    end

    # The dotted edge's twin in words, for a reader who selects a row
    # rather than points at the map: the send says what hears it, the rule
    # which send arms it, and a block at neither end of a timer edge says
    # neither.
    #
    # Sabotage: made timed/2 answer nothing; this went red. Reverted from
    # a copy.
    test "the send names what hears it, and the rule what arms it" do
      described = by_id("patron_registration")

      assert fact(described["blk_pr_deadline"], "Heard by") == [
               "When the registration week is up, abandon"
             ]

      assert fact(described["blk_pr_expired"], "Armed by") == [
               "In 7 days, send word that the registration week is up"
             ]

      assert fact(described["blk_pr_email"], "Heard by") == nil
      assert fact(described["blk_pr_email"], "Armed by") == nil
    end
  end

  # ---------------------------------------------------------------- helpers

  defp described(key) do
    {:ok, fixture} = Charts.fixture(key)
    document = fixture.document
    view_model = ViewModel.build(document, Charts.palette(), [])
    graph = PlanMap.graph(view_model)
    outline = Describe.outline(document, Charts.palette(), [])

    {graph, PlanDescription.elements(graph, view_model, outline, Charts.palette()),
     PlanDescription.idle(document, graph, view_model, outline)}
  end

  defp describe_root(root) do
    document = Document.new(root)
    view_model = ViewModel.build(document, Charts.palette(), [])
    graph = PlanMap.graph(view_model)
    outline = Describe.outline(document, Charts.palette(), [])

    graph
    |> PlanDescription.elements(view_model, outline, Charts.palette())
    |> Map.new(&{&1.id, &1})
  end

  defp by_id(key) do
    {_graph, descriptions, _idle} = described(key)
    Map.new(descriptions, &{&1.id, &1})
  end

  defp fact(%PlanDescription{facts: facts}, label) do
    Enum.find_value(facts, fn {name, value} -> if name == label, do: value end)
  end

  defp label(module, key) do
    %{} |> module.config_schema() |> Enum.find(&(&1.key == key)) |> Map.fetch!(:label)
  end

  # Every id the graph draws below its root: nodes, connectors, interrupt
  # edges and timer edges alike, and an edge the root itself carries.
  defp graph_ids(%{"children" => children} = graph) do
    edges = graph |> Map.get("edges", []) |> Enum.map(& &1["id"])
    timers = graph |> Map.get("timers", []) |> Enum.map(& &1["id"])
    (Enum.flat_map(children, &ids/1) ++ edges ++ timers) |> Enum.sort()
  end

  defp ids(node) do
    own = [node["id"]]
    inside = node |> Map.get("children", []) |> Enum.flat_map(&ids/1)
    edges = node |> Map.get("edges", []) |> Enum.map(& &1["id"])
    interrupts = node |> Map.get("interrupts", []) |> Enum.map(& &1["id"])
    own ++ inside ++ edges ++ interrupts
  end
end
