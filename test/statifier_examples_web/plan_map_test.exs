defmodule StatifierExamplesWeb.PlanMapTest do
  @moduledoc """
  The map's graph, read without laying it out: it is the document, every
  empty slot is marked, and the options that keep the model order are
  where the moduledoc says they are.

  `StatifierExamplesWeb.PlanMapLayoutTest` lays the same graphs out through
  elkjs and reads the order that results.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.Block
  alias StatifierBlocks.Describe
  alias StatifierBlocks.Describe.Edge
  alias StatifierBlocks.Document
  alias StatifierBlocks.ViewModel
  alias StatifierBlocks.ViewModel.Node
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.PlanMap

  @force "org.eclipse.elk.layered.crossingMinimization.forceNodeModelOrder"
  @consider "org.eclipse.elk.layered.considerModelOrder.strategy"

  describe "the graph is the document" do
    # Sabotage: made slot_children/1 draw only ViewModel.flow_children/1,
    # dropping the shelf; this went red. Reverted from a copy.
    test "every fixture's graph holds the outline's blocks, once each, in reading order" do
      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)

        outline_ids =
          for {%Node{block_id: id}, _depth, _kind} <- ViewModel.outline(view_model), do: id

        assert PlanMap.nodes(PlanMap.graph(view_model)) == outline_ids, fixture.key
      end
    end

    # The library world's two branches, arm by arm: every arm a slot node of
    # its own, in the order the branch evaluates them, the empty one
    # included.
    #
    # Sabotage: made drawn_slots/1 drop a body slot with no children; the
    # empty arms vanished and this went red, with both marker cases below.
    # Reverted from a copy.
    test "a branch draws every arm it declares, in slot order" do
      assert slot_ids(graph("library_loan"), "blk_ll_due") == [
               "blk_ll_due/arm_returned",
               "blk_ll_due/arm_renew",
               "blk_ll_due/otherwise",
               "blk_ll_due/undecided"
             ]

      assert slot_ids(graph("patron_registration"), "blk_pr_age") == [
               "blk_pr_age/arm_child",
               "blk_pr_age/arm_adult",
               "blk_pr_age/otherwise",
               "blk_pr_age/undecided"
             ]
    end
  end

  describe "empty slots are marked, not hidden" do
    # Derived rather than listed: every slot in the view model with nothing
    # in it is one marker in the graph, and nothing else is.
    #
    # Sabotage: made slot/2 draw no marker for an empty slot
    # (`[] -> {[], []}`); this went red, with the case below. Reverted from
    # a copy.
    test "every empty slot of every fixture is exactly one marker" do
      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)

        expected =
          for {%Node{block_id: id, slots: slots}, _depth, _kind} <- ViewModel.outline(view_model),
              %{name: name, children: []} <- slots,
              do: "#{id}/#{name}/empty"

        assert Enum.sort(markers(PlanMap.graph(view_model))) == Enum.sort(expected), fixture.key
      end
    end

    test "each library fixture marks the one arm its author left empty" do
      assert markers(graph("library_loan")) == ["blk_ll_due/undecided/empty"]
      assert markers(graph("patron_registration")) == ["blk_pr_age/otherwise/empty"]

      assert %{"title" => title} = find(graph("library_loan"), "blk_ll_due/undecided/empty")
      assert title == PlanMap.empty_text()
    end
  end

  describe "what is and is not an edge" do
    # A group's interrupt rules each watch the whole body; joining them
    # would draw them as steps that run one after another.
    #
    # Sabotage: made flow_edges/1 answer sequence_edges/1 for every slot;
    # this went red on both library groups. Reverted from a copy.
    test "a rail's blocks are not joined" do
      for {key, rail} <- [
            {"library_loan", "blk_ll_on_loan/interrupts"},
            {"patron_registration", "blk_pr_verify/interrupts"}
          ] do
        assert %{"edges" => [], "children" => [_first, _second]} = find(graph(key), rail)
      end
    end

    # Sabotage: made under/2 always wrap; "Sequence" came back under
    # "Sequence" and this went red. Reverted from a copy.
    #
    # 2026-09-27: statifier_blocks 0.36.0 gives `core.sequence` and
    # `core.group` sentences of their own, so the library root now draws
    # its line and the words said once are a card fixture's `Invoke`, whose
    # type declares no sentence and falls back to its label.
    test "a sentence that only repeats the title is not drawn twice" do
      graph = graph("library_loan")

      assert %{"title" => "Sequence", "lines" => ["Run its steps in order"]} =
               find(graph, "blk_ll_root")

      assert %{"title" => "Wait", "lines" => ["Wait 21d"]} = find(graph, "blk_ll_loan_period")

      assert %{"title" => "Invoke", "lines" => []} =
               find(graph("card_processing"), "blk_cp_authorize")
    end
  end

  describe "sizes" do
    # A word longer than a line keeps its own line, whole, and widens its
    # box to fit rather than running out of it.
    #
    # Sabotage: capped leaf_width/1 at 260 again; this went red. Reverted
    # from a copy.
    test "a leaf is as wide as its longest word needs" do
      event = "patron.registration.second_reminder_after_the_first_week"

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{"body" => [Block.new("core.send", id: "long", config: %{"event" => event})]}
        )

      graph = root |> Document.new() |> ViewModel.build(Charts.palette(), []) |> PlanMap.graph()
      leaf = find(graph, "long")

      assert event in leaf["lines"]
      assert leaf["width"] >= String.length(event) * 7 + 24
    end

    # The title is sized too, not only the sentence under it.
    #
    # Sabotage: made the leaf clause call leaf_width(lines) without the
    # title; this went red. Reverted from a copy.
    test "a leaf is at least as wide as its title" do
      for fixture <- Charts.fixtures(),
          node <- walk(PlanMap.graph(view_model(fixture))),
          Map.has_key?(node, "width") do
        assert node["width"] >= String.length(node["title"]) * 7 + 24, node["id"]
      end
    end
  end

  describe "interrupt edges and timer marks" do
    # The map reads its interrupt edges off the view model; Describe reads
    # them off the document. The two are held equal, rule for rule, so the
    # map cannot draw an interrupt the description does not say.
    #
    # Sabotage: made leads_to/1 answer "body" for an abandon rule; this
    # went red, with the library case below. Reverted from a copy.
    test "every fixture's interrupt edges are Describe's" do
      for fixture <- Charts.fixtures() do
        described =
          for %Edge{kind: :interrupt, from: {:block, rule}, to: {to, group}} <-
                Describe.outline(fixture.document, Charts.palette(), []).edges do
            %{"from" => rule, "group" => group, "to" => Atom.to_string(to)}
          end

        assert PlanMap.interrupts(PlanMap.graph(view_model(fixture))) == described, fixture.key
      end
    end

    # Sabotage: made put_interrupts/2 take the group's last drawn child as
    # the head; this went red, with the resume case below. Reverted from a
    # copy.
    test "each library group's two rules leave it by its exit" do
      assert PlanMap.interrupts(graph("library_loan")) == [
               %{"from" => "blk_ll_returned_early", "group" => "blk_ll_on_loan", "to" => "exit"},
               %{"from" => "blk_ll_reported_lost", "group" => "blk_ll_on_loan", "to" => "exit"}
             ]

      assert PlanMap.interrupts(graph("patron_registration")) == [
               %{"from" => "blk_pr_abandoned", "group" => "blk_pr_verify", "to" => "exit"},
               %{"from" => "blk_pr_expired", "group" => "blk_pr_verify", "to" => "exit"}
             ]

      assert [%{"kind" => "interrupt", "head" => "blk_pr_deadline"} | _rest] =
               find(graph("patron_registration"), "blk_pr_verify")["interrupts"]
    end

    # A resume rule goes back to the head of the group's body. Neither
    # library fixture has one, so a signup group carries the case.
    #
    # Sabotage: the same head taken from the last drawn child; this went
    # red. Reverted from a copy.
    test "a resume rule leads to the head of its group's body" do
      resumes =
        for fixture <- Charts.fixtures(),
            edge <- PlanMap.interrupts(PlanMap.graph(view_model(fixture))),
            edge["to"] == "body",
            do: {fixture.key, edge}

      refute resumes == []

      for {key, %{"group" => group}} <- resumes do
        node = find(graph(key), group)
        [%{"id" => head} | _rest] = node["children"]

        for edge <- node["interrupts"], edge["to"] == "body" do
          assert edge["head"] == head, "#{key}: #{edge["id"]}"
        end
      end
    end

    # Sabotage: made mark/1 answer nil for core.await; this went red, with
    # the derived and drawn cases. Made delayed?/1 answer true for any
    # string delay, blank included; this went red. Each reverted from a copy.
    test "the library fixtures mark every await and the one delayed send, and no other" do
      assert marks(graph("library_loan")) == %{"blk_ll_late_return" => "wait"}

      assert marks(graph("patron_registration")) == %{
               "blk_pr_deadline" => "clock",
               "blk_pr_email" => "wait",
               "blk_pr_guardian" => "wait"
             }
    end

    # Derived rather than listed: every await in every fixture carries the
    # wait mark, every send carries the clock mark exactly when its delay
    # is set, and no other block carries a mark.
    #
    # Sabotage: the two mutations above; each turned this red. Reverted
    # from a copy.
    test "every fixture marks its awaits and its delayed sends, and nothing else" do
      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)

        expected =
          for {%Node{} = node, _depth, _kind} <- ViewModel.outline(view_model),
              mark = expected_mark(node),
              into: %{},
              do: {node.block_id, mark}

        assert marks(PlanMap.graph(view_model)) == expected, fixture.key
      end
    end

    # The mark sits level with the title, so the title leaves it room. No
    # core type's own label is long enough to need it, so the case is a
    # view model whose await carries a long title of its own.
    #
    # Sabotage: dropped the title-plus-mark term from put_mark/4's width;
    # this went red. Reverted from a copy.
    test "a marked leaf is wide enough for its title and its mark" do
      title = "Wait for the patron to collect the copy from the hold shelf"

      root =
        Block.new("core.sequence",
          id: "root",
          slots: %{
            "body" => [
              Block.new("core.await", id: "held", config: %{"event" => "hold.collected"})
            ]
          }
        )

      view_model = root |> Document.new() |> ViewModel.build(Charts.palette(), [])
      [%{children: [await]} = body] = view_model.root.slots
      titled = %{body | children: [%{await | title: title}]}
      view_model = %{view_model | root: %{view_model.root | slots: [titled]}}

      assert %{"mark" => "wait", "title" => ^title, "width" => width} =
               find(PlanMap.graph(view_model), "held")

      assert width >= String.length(title) * 7 + 24 + 22
    end
  end

  describe "the options that keep the model order" do
    # Sabotage: dropped @force_model_order from container_options/2; every
    # container lost it and this went red. Reverted from a copy.
    test "forceNodeModelOrder is on every container" do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(view_model(fixture))

        for container <- containers(graph) do
          assert container["layoutOptions"][@force] == "true",
                 "#{fixture.key}: #{container["id"]} does not force the model order"
        end
      end
    end

    # Sabotage: added `@consider_model_order => "NODES_AND_EDGES"` to
    # container_options/2; this went red on the first nested container.
    # Reverted from a copy.
    test "considerModelOrder is on the root and on nothing else" do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(view_model(fixture))

        assert graph["layoutOptions"][@consider] == "NODES_AND_EDGES"

        for container <- containers(graph), container["id"] != "plan-map" do
          refute Map.has_key?(container["layoutOptions"], @consider),
                 "#{fixture.key}: #{container["id"]} carries considerModelOrder"
        end
      end
    end

    # Sabotage: reversed ViewModel.flow_children/1 in slot_children/1; this
    # went red, with the outline case above. Reverted from a copy.
    test "a container lists its children in model order, and sequence edges follow it" do
      root = find(graph("patron_registration"), "blk_pr_root")

      assert Enum.map(root["children"], & &1["id"]) == [
               "blk_pr_verify",
               "blk_pr_age",
               "blk_pr_welcome"
             ]

      assert Enum.map(root["edges"], &{&1["sources"], &1["targets"]}) == [
               {["blk_pr_verify"], ["blk_pr_age"]},
               {["blk_pr_age"], ["blk_pr_welcome"]}
             ]
    end
  end

  describe "the Branch" do
    # The header is the map's own; the branch type's sentence, which the
    # list draws, is what it was.
    #
    # Sabotage: made arm_lines/1 drop the arms with no condition; this went
    # red. Made it reverse the arms; this went red. Each reverted from a
    # copy.
    test "a branch's header names every arm, and its sentence is unchanged" do
      for {key, id, sentence, arms} <- [
            {"library_loan", "blk_ll_due", ~s(Decide: When "returned", otherwise),
             [~s(When "returned"), ~s(When "renew"), "Otherwise", "Cannot be decided"]},
            {"patron_registration", "blk_pr_age", ~s(Decide: When "child", otherwise),
             [~s(When "child"), ~s(When "adult"), "Otherwise", "Cannot be decided"]}
          ] do
        {:ok, fixture} = Charts.fixture(key)
        node = ViewModel.find_node(view_model(fixture), id)
        assert ViewModel.sentence(node) == sentence

        assert %{"band" => true, "lines" => lines} = find(graph(key), id)
        header = Enum.join(lines, " ")

        positions =
          for {label, n} <- Enum.with_index(arms, 1) do
            assert {at, _len} = :binary.match(header, "#{n}. #{label}")
            at
          end

        assert positions == Enum.sort(positions), key
      end
    end

    # Only a branch carries a band, and only the edge out of a branch is a
    # rejoin.
    #
    # Sabotage: made put_band/2 band every container; this went red.
    # Reverted from a copy.
    test "every fixture bands only its branches and rejoins only out of them" do
      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)
        graph = PlanMap.graph(view_model)

        branches =
          for {%Node{type: "core.branch", block_id: id}, _depth, _kind} <-
                ViewModel.outline(view_model),
              do: id

        assert Enum.sort(for(%{"band" => true, "id" => id} <- walk(graph), do: id)) ==
                 Enum.sort(branches),
               fixture.key

        for %{"edges" => edges} <- walk(graph), %{"kind" => kind, "sources" => [from]} <- edges do
          assert kind == if(from in branches, do: "rejoin", else: "sequence"),
                 "#{fixture.key}: #{from}"
        end
      end
    end

    # The loan's branch ends its document, so it rejoins into an end mark;
    # the registration's is followed by a step and needs none.
    #
    # Sabotage: made put_end/2 add no end mark; this went red. Reverted
    # from a copy.
    test "an end mark follows a branch that ends the document, and nothing else" do
      root = find(graph("library_loan"), "blk_ll_root")

      assert Enum.map(root["children"], & &1["id"]) ==
               ["blk_ll_on_loan", "blk_ll_due", "blk_ll_root/end"]

      assert %{"kind" => "end", "title" => "End"} = List.last(root["children"])

      assert List.last(root["edges"]) == %{
               "id" => "blk_ll_due->blk_ll_root/end",
               "sources" => ["blk_ll_due"],
               "targets" => ["blk_ll_root/end"],
               "kind" => "rejoin"
             }

      refute Enum.any?(walk(graph("patron_registration")), &(&1["kind"] == "end"))
    end
  end

  # Sabotage: made sequence_edges/1 carry its source as a tuple; Jason
  # refused it and this went red. Reverted from a copy.
  test "the graph encodes to JSON for the hook" do
    for fixture <- Charts.fixtures() do
      assert {:ok, _json} = Jason.encode(PlanMap.graph(view_model(fixture)))
    end
  end

  # ------------------------------------------------------------------ helpers

  defp view_model(fixture), do: ViewModel.build(fixture.document, Charts.palette(), [])

  defp graph(key) do
    {:ok, fixture} = Charts.fixture(key)
    PlanMap.graph(view_model(fixture))
  end

  defp walk(%{} = node), do: [node | Enum.flat_map(Map.get(node, "children", []), &walk/1)]

  defp find(graph, id), do: Enum.find(walk(graph), &(&1["id"] == id))

  defp containers(graph), do: Enum.filter(walk(graph), &Map.has_key?(&1, "children"))

  defp markers(graph), do: for(%{"kind" => "empty", "id" => id} <- walk(graph), do: id)

  defp marks(graph),
    do: for(%{"mark" => mark, "id" => id} <- walk(graph), into: %{}, do: {id, mark})

  # The mark a block should carry, read off the fixture's own form values
  # rather than the map's code.
  defp expected_mark(%Node{type: "core.await"}), do: "wait"

  defp expected_mark(%Node{type: "core.send", form: %{fields: fields}}) do
    case Enum.find(fields, &(&1.key == "delay")) do
      %{value: delay} when is_binary(delay) and delay != "" -> "clock"
      _undelayed -> nil
    end
  end

  defp expected_mark(%Node{}), do: nil

  defp slot_ids(graph, block_id) do
    for %{"kind" => "slot", "id" => id} <- find(graph, block_id)["children"], do: id
  end
end
