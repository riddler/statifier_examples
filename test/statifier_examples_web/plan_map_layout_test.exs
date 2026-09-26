defmodule StatifierExamplesWeb.PlanMapLayoutTest do
  @moduledoc """
  The map laid out through the real elkjs, and drawn by the hook's own
  `drawMap`: the order a reader sees, and what a failed layout draws.

  The layout runs in the browser, so the only honest test of it runs the
  same JavaScript. `test/support/js/plan_map_layout.mjs` imports
  `assets/js/plan_map.mjs` - the file the page bundles - lays a graph out
  and prints what it drew. That needs Node on the path, the one tool this
  suite asks for beyond Elixir; a machine without it fails here with that
  sentence rather than skipping, because a skipped order test is an
  unpinned order.
  """

  use ExUnit.Case, async: true

  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.PlanMap

  @driver Path.expand("../support/js/plan_map_layout.mjs", __DIR__)

  @moduletag :tmp_dir

  describe "the order test" do
    # Arms side by side, left to right in the order the branch evaluates
    # them; steps top to bottom in the order they run. Read off the boxes
    # elkjs placed, for every container in every fixture.
    #
    # Sabotage: dropped @force_model_order from both the root options and
    # container_options/2; elkjs laid a branch's arms out of order and this
    # went red. Reverted from a copy.
    test "every fixture lays out in model order", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "boxes" => boxes} = run(dir, fixture.key, graph)

        for container <- containers(graph) do
          assert_arms_in_order(fixture.key, container, boxes)
          assert_steps_in_order(fixture.key, container, boxes)
        end
      end
    end

    # Every connector starts on its source's bottom edge and ends on its
    # target's top edge, inside each box's width: an edge drawn from the
    # wrong offset would join the right ids and point at the wrong boxes.
    #
    # Sabotage: made edgesOf double the offsets it adds; this went red.
    # Reverted from a copy.
    test "every edge leaves its source's bottom and enters its target's top", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "boxes" => boxes, "edges" => edges} = run(dir, fixture.key, graph)

        assert length(edges) == length(Enum.flat_map(containers(graph), & &1["edges"]))

        for %{"source" => from, "target" => to, "start" => start, "end" => stop} <- edges do
          source = boxes[from]
          target = boxes[to]

          assert_in_delta start["y"],
                          source["y"] + source["height"],
                          0.5,
                          "#{fixture.key}: #{from}"

          assert_in_delta stop["y"], target["y"], 0.5, "#{fixture.key}: #{to}"
          assert start["x"] >= source["x"] and start["x"] <= source["x"] + source["width"]
          assert stop["x"] >= target["x"] and stop["x"] <= target["x"] + target["width"]
        end
      end
    end

    # No box is narrower than the widest line it carries, title included,
    # at the map's own per-character estimate - so no text runs out of its
    # box. Containers are the case the estimate alone would not hold: their
    # width is ELK's, and only the minimum size on them keeps it.
    #
    # Sabotage: dropped the nodeSize.minimum option from
    # container_options/2; this went red on a container whose header is
    # wider than its children. Reverted from a copy.
    test "every box is at least as wide as its text", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "boxes" => boxes} = run(dir, fixture.key, graph)

        for node <- walk(graph), node["id"] != "plan-map" do
          texts =
            if node["kind"] == "slot", do: node["lines"], else: [node["title"] | node["lines"]]

          needed = text_width(texts)

          assert boxes[node["id"]]["width"] >= needed,
                 "#{fixture.key}: #{node["id"]} is #{boxes[node["id"]]["width"]} wide, its text needs #{needed}"
        end
      end
    end

    # Sabotage: made drawNode draw nothing for an empty marker; this went
    # red. Reverted from a copy.
    test "both library fixtures draw every arm, the empty one marked", %{tmp_dir: dir} do
      for {key, empty} <- [
            {"library_loan", "blk_ll_due/undecided/empty"},
            {"patron_registration", "blk_pr_age/otherwise/empty"}
          ] do
        {:ok, fixture} = Charts.fixture(key)
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "html" => html, "boxes" => boxes} = run(dir, key, graph)

        for id <- PlanMap.nodes(graph), do: assert(Map.has_key?(boxes, id), "#{key}: #{id}")
        assert html =~ ~s(data-map-node="#{empty}" data-map-kind="empty")
        assert html =~ PlanMap.empty_text()
      end
    end
  end

  describe "the error-pane test" do
    # An edge to a node the graph does not hold is a graph elkjs refuses
    # outright, which is the failure the pane is for.
    #
    # Sabotage: made drawMap rethrow in its catch instead of drawing
    # renderError; the driver exited non-zero and this went red, with the
    # empty-layout case below. Reverted from a copy.
    test "a layout that throws draws the error pane and no map", %{tmp_dir: dir} do
      graph =
        put_in(sample_graph(), ["children", Access.at(0), "edges"], [
          %{"id" => "dangling", "sources" => ["blk_pr_deadline"], "targets" => ["no_such_block"]}
        ])

      assert %{"drawn" => "error", "html" => html} = run(dir, "throws", graph)
      assert html =~ ~s(data-map-error="true")
      assert html =~ "The map could not be drawn."
      assert html =~ "The list has every step of this document."
      refute html =~ "<svg"
    end

    # Sabotage: dropped the throw from layout()'s emptiness check; this
    # went red. Reverted from a copy.
    test "a layout that comes back empty draws the error pane, not a blank map",
         %{tmp_dir: dir} do
      graph = Map.put(sample_graph(), "children", [])

      assert %{"drawn" => "error", "html" => html} = run(dir, "empty", graph)
      assert html =~ "the layout came back empty"
      refute html =~ "<svg"
    end
  end

  describe "what a click on the map sends" do
    # Every clickable element the hook draws, and what its own mapGesture
    # turns a click there into, for every fixture: a block selects itself;
    # every block but the root has a "+" arming the gap after it; every
    # empty slot's marker arms the head of the slot it stands for. The
    # payloads are the ones the list's own controls send.
    #
    # Sabotage: made drawGap draw for the root too; this went red on the
    # gap count. Made the empty marker omit data-map-slot; this went red.
    # Each reverted from a copy.
    test "an editable map arms the list's own gestures", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "gestures" => gestures} = run(dir, fixture.key, graph, "editable")
        by_element = Map.new(gestures, &{&1["element"], &1["gesture"]})
        [root | blocks] = PlanMap.nodes(graph)

        assert by_element["block:#{root}"] == %{
                 "event" => "select-row",
                 "payload" => %{"block-id" => root}
               }

        refute Map.has_key?(by_element, "gap:#{root}")

        for id <- blocks do
          assert by_element["block:#{id}"] == %{
                   "event" => "select-row",
                   "payload" => %{"block-id" => id}
                 }

          assert by_element["gap:#{id}"] == %{
                   "event" => "insert-open",
                   "payload" => %{"block-id" => id}
                 }
        end

        for %{"kind" => "empty", "id" => id, "parent" => parent, "slot" => slot} <- walk(graph) do
          assert by_element["empty:#{id}"] == %{
                   "event" => "insert-open",
                   "payload" => %{"block-id" => parent, "slot" => slot}
                 }
        end

        assert Enum.count(gestures, &String.starts_with?(&1["element"], "gap:")) == length(blocks)
      end
    end

    # Sabotage: made renderSvg draw the gaps whatever `editable` said; this
    # went red. Reverted from a copy.
    test "a read-only map only selects", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "html" => html, "gestures" => gestures} = run(dir, fixture.key, graph)

        refute html =~ "data-map-gap"

        for %{"gesture" => gesture} <- gestures, gesture != nil do
          assert gesture["event"] == "select-row"
        end
      end
    end
  end

  # A document's words reach the SVG as text, never as markup.
  #
  # Sabotage: made escapeText return its argument unchanged; the title
  # arrived as a live element and this went red. Reverted from a copy.
  test "a title is escaped into the drawing", %{tmp_dir: dir} do
    graph =
      update_in(sample_graph(), ["children", Access.at(0), "title"], fn _title ->
        ~s|<img src=x onerror="alert(1)">|
      end)

    assert %{"drawn" => "map", "html" => html} = run(dir, "escaped", graph)
    refute html =~ "<img"
    assert html =~ "&lt;img src=x onerror=&quot;alert(1)&quot;&gt;"
  end

  # ------------------------------------------------------------------ helpers

  defp sample_graph do
    {:ok, fixture} = Charts.fixture("patron_registration")
    PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
  end

  defp run(dir, name, graph, mode \\ nil) do
    node = System.find_executable("node") || flunk("the map's layout tests need Node on the PATH")
    path = Path.join(dir, "#{name}.json")
    File.write!(path, Jason.encode!(graph))

    args = if mode, do: [@driver, path, mode], else: [@driver, path]
    {out, status} = System.cmd(node, args, stderr_to_stdout: true)
    assert status == 0, "the layout driver exited #{status}: #{out}"
    Jason.decode!(out)
  end

  # The map's per-character estimate, padding included (7 and 24 in
  # `StatifierExamplesWeb.PlanMap`).
  defp text_width(texts),
    do: (texts |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)) * 7 + 24

  defp walk(%{} = node), do: [node | Enum.flat_map(Map.get(node, "children", []), &walk/1)]

  defp containers(graph), do: Enum.filter(walk(graph), &(Map.get(&1, "children", []) != []))

  # A block's slot nodes that are arms sit side by side, in slot order.
  defp assert_arms_in_order(key, container, boxes) do
    arms = for %{"kind" => "slot", "style" => "arm", "id" => id} <- container["children"], do: id
    xs = Enum.map(arms, &boxes[&1]["x"])

    assert xs == Enum.sort(xs) and xs == Enum.uniq(xs),
           "#{key}: #{container["id"]}'s arms #{inspect(arms)} are out of order at #{inspect(xs)}"
  end

  # Every sequence edge runs downwards: the later step sits lower.
  defp assert_steps_in_order(key, container, boxes) do
    for %{"sources" => [from], "targets" => [to]} <- container["edges"] do
      assert boxes[to]["y"] > boxes[from]["y"],
             "#{key}: #{to} is not below #{from} (#{boxes[from]["y"]} -> #{boxes[to]["y"]})"
    end
  end
end
