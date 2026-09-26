defmodule StatifierExamplesWeb.PlanMapTest do
  @moduledoc """
  The map's graph, read without laying it out: it is the document, every
  empty slot is marked, and the options that keep the model order are
  where the moduledoc says they are.

  `StatifierExamplesWeb.PlanMapLayoutTest` lays the same graphs out through
  elkjs and reads the order that results.
  """

  use ExUnit.Case, async: true

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

  describe "the options that keep the model order" do
    # Sabotage: dropped @force_model_order from container_options/1; every
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
    # container_options/1; this went red on the first nested container.
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

  defp slot_ids(graph, block_id) do
    for %{"kind" => "slot", "id" => id} <- find(graph, block_id)["children"], do: id
  end
end
