defmodule StatifierExamplesWeb.PlanDescriptionTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Core.Await
  alias StatifierBlocks.Core.Wait
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.PlanDescription
  alias StatifierExamplesWeb.PlanMap
  alias StatifierExamplesWeb.TypeExplanation

  # The library fixtures are the two teaching documents the region is read
  # against; between them every kind the map draws is drawn at least once.
  @library ["library_loan", "patron_registration"]

  describe "elements/3" do
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
               "done: goes on to Wait for copy.returned, giving up after 14d"
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
               "On copy.returned, abandons Group (Run interruptible steps)",
               "On copy.reported_lost, abandons Group (Run interruptible steps)"
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
               "When registration.abandoned, abandon",
               "When registration.deadline, abandon"
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
               "Send registration.deadline",
               "Wait for email.verified",
               ~s(Decide: When "child", otherwise),
               "Send patron.welcomed"
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
      assert fact(renew, "Goes to") == "Send loan.renewed"
      assert fact(renew, "Place") =~ ~r/^Arm 2 of 4 of Branch/

      otherwise = loan["blk_ll_due/otherwise"]
      assert fact(otherwise, "Condition") == "None of the arms before it holds"
      assert fact(otherwise, "Goes to") == "Send loan.overdue"
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
      assert fact(wired, "Goes to") == "Send patron.asked_to_visit"

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
      assert edge.sentence == "On copy.returned, abandons Group (Run interruptible steps)"
      assert fact(edge, "Rule") =~ "copy.returned"
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
      assert fact(edge, "From") == "Send loan.overdue"
      assert fact(edge, "To") == "Wait for copy.returned, giving up after 14d"
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

      rejoin = loan["blk_ll_due->blk_ll_root/end"]
      assert %PlanDescription{kind: :edge, title: "Rejoin"} = rejoin
      assert fact(rejoin, "To") == "the document finishes"
      assert fact(rejoin, "Inside") =~ ~r/^Sequence/

      assert %PlanDescription{kind: :end, title: "End"} = loan["blk_ll_root/end"]

      patron = by_id("patron_registration")["blk_pr_age->blk_pr_welcome"]
      assert %PlanDescription{kind: :edge, title: "Rejoin"} = patron
      assert fact(patron, "To") == "Send patron.welcomed"
    end
  end

  describe "idle/4" do
    # Sabotage: counted the root among the steps; this went red. Reverted
    # from a copy. Sabotage: cut the dashed arrow from the how-to-read
    # line; this went red. Reverted from a copy.
    test "the document: its name, description, what starts it, and its counts" do
      {_graph, _descriptions, loan} = described("library_loan")

      assert loan.kind == :idle
      assert loan.id == nil
      assert loan.title == "Library loan"
      assert loan.sentence =~ "A patron borrows a copy"
      assert loan.explanation =~ PlanMap.empty_text()
      assert loan.explanation =~ "a dashed arrow runs from an interrupt rule"
      assert loan.explanation =~ "An hourglass marks a step that waits"
      assert loan.explanation =~ "a clock a message sent after a delay"
      assert loan.explanation =~ "or point at the map"
      assert fact(loan, "What starts it") == "Starts when told to"
      assert fact(loan, "Listens for") == ["copy.returned", "copy.reported_lost"]
      assert fact(loan, "Steps") == "9"
      assert fact(loan, "Open slots") == "1"

      {_graph, _descriptions, patron} = described("patron_registration")
      assert patron.title == "Patron registration"
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

  describe "TypeExplanation" do
    # The host's fixed text covers every core type the package ships.
    #
    # Sabotage: deleted the "core.await" entry; this went red. Reverted from
    # a copy.
    test "has its own text for every core type" do
      assert TypeExplanation.core_types() == Palette.core().types |> Map.keys() |> Enum.sort()
    end

    # Sabotage: made described/1 hand back a blank description as it is;
    # this went red. Reverted from a copy.
    test "falls back to the palette's description, then says so" do
      host = %ViewModel.Node{
        block_id: "x",
        type: "myapp.example",
        type_version: 1,
        status: :ok,
        entry: %{description: "Does a host thing."}
      }

      assert TypeExplanation.explain(host) == "Does a host thing."
      assert TypeExplanation.explain(%{host | entry: %{}}) =~ "no description"
      assert TypeExplanation.explain(%{host | entry: %{description: " "}}) =~ "no description"

      assert TypeExplanation.explain(%{host | status: {:unresolvable, :unknown_type}}) =~
               "does not know"
    end
  end

  # ---------------------------------------------------------------- helpers

  defp described(key) do
    {:ok, fixture} = Charts.fixture(key)
    document = fixture.document
    view_model = ViewModel.build(document, Charts.palette(), [])
    graph = PlanMap.graph(view_model)
    outline = Describe.outline(document, Charts.palette(), [])

    {graph, PlanDescription.elements(graph, view_model, outline),
     PlanDescription.idle(document, graph, view_model, outline)}
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

  # Every id the graph draws below its root: nodes, connectors and
  # interrupt edges alike.
  defp graph_ids(%{"children" => children}),
    do: children |> Enum.flat_map(&ids/1) |> Enum.sort()

  defp ids(node) do
    own = [node["id"]]
    inside = node |> Map.get("children", []) |> Enum.flat_map(&ids/1)
    edges = node |> Map.get("edges", []) |> Enum.map(& &1["id"])
    interrupts = node |> Map.get("interrupts", []) |> Enum.map(& &1["id"])
    own ++ inside ++ edges ++ interrupts
  end
end
