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
  alias StatifierExamplesWeb.TypeExplanation

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
            if node["kind"] == "slot",
              do: node["lines"] ++ List.wrap(node["caption"]),
              else: [node["title"] | node["lines"]]

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

  describe "interrupt edges and timer marks, as drawn" do
    # Every interrupt edge of both library fixtures is a dashed path from
    # the bottom of its rule's box straight down to the bottom edge of the
    # group it abandons, read off the markup's own path data; and the
    # layout's own edges are not dashed.
    #
    # Sabotage: made interruptsOf end an exit edge on the group's top
    # edge; this went red. Dropped the dash from drawInterrupt; this went
    # red. Left interruptsOf out of renderSvg; this went red. Each
    # reverted from a copy.
    test "both library fixtures draw their interrupt edges dashed from the rule to its target",
         %{tmp_dir: dir} do
      for key <- ["library_loan", "patron_registration"] do
        {:ok, fixture} = Charts.fixture(key)
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))

        %{"drawn" => "map", "html" => html, "boxes" => boxes, "interrupts" => drawn} =
          run(dir, key, graph)

        expected = PlanMap.interrupts(graph)
        refute expected == []
        assert length(drawn) == length(expected), key

        for %{"from" => rule, "group" => group, "to" => "exit"} <- expected do
          id = "#{rule}->#{group}/exit"
          edge = Enum.find(drawn, &(&1["id"] == id)) || flunk("#{key}: #{id} is not drawn")

          assert %{"source" => ^rule, "target" => ^group, "to" => "exit", "dashed" => true} =
                   edge

          [start | _rest] = points = path_points(edge["d"])
          stop = List.last(points)
          from = boxes[rule]
          to = boxes[group]

          assert_in_delta start.y, from["y"] + from["height"], 0.5, "#{key}: #{id} start"
          assert start.x > from["x"] and start.x < from["x"] + from["width"]
          assert_in_delta stop.y, to["y"] + to["height"], 0.5, "#{key}: #{id} end"
          assert stop.x > to["x"] and stop.x < to["x"] + to["width"]
        end

        for [path] <- Regex.scan(~r/<path [^>]*class="plan-map__edge"[^>]*>/, html) do
          refute path =~ "stroke-dasharray", "#{key}: #{path}"
        end
      end
    end

    # Every await box of both library fixtures carries the wait mark, the
    # one delayed send the clock mark, and every other box - an undelayed
    # send included - neither, as the markup carries them.
    #
    # Sabotage: made drawMark draw nothing; this went red. Reverted from a
    # copy.
    test "both library fixtures mark their awaits and their delayed send, and nothing else",
         %{tmp_dir: dir} do
      for {key, expected} <- [
            {"library_loan", %{"blk_ll_late_return" => ["wait"]}},
            {"patron_registration",
             %{
               "blk_pr_deadline" => ["clock"],
               "blk_pr_email" => ["wait"],
               "blk_pr_guardian" => ["wait"]
             }}
          ] do
        {:ok, fixture} = Charts.fixture(key)
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
        %{"drawn" => "map", "marks" => marks} = run(dir, key, graph)

        assert marks == expected, key
      end
    end
  end

  describe "the Branch, as drawn" do
    # The two library branches and the step each rejoins into: the loan's
    # branch is the last step of its document, so it rejoins into the end
    # mark; the registration's rejoins into the welcome.
    @branches [
      {"library_loan", "blk_ll_due", "blk_ll_root/end",
       [
         "One of, in order:",
         "1. When \"returned\": loan.returned",
         "2. When \"renew\": copy.holds == 0",
         "AND loan.renewals < 2",
         "3. Otherwise",
         "4. Cannot be decided"
       ]},
      {"patron_registration", "blk_pr_age", "blk_pr_welcome",
       [
         "One of, in order:",
         "1. When \"child\": patron.age < 13",
         "2. When \"adult\": patron.age >= 13",
         "3. Otherwise",
         "4. Cannot be decided"
       ]}
    ]

    # The header under the branch's title names every arm with its
    # condition, in slot order, as the markup draws it.
    #
    # Sabotage: made arm_lines/1 reverse the arms; this went red. Made
    # arm_lines/1 drop the arms with no condition; this went red. Each
    # reverted from a copy.
    test "both library branches draw a header naming every arm in slot order",
         %{tmp_dir: dir} do
      for {key, branch, _next, header} <- @branches do
        %{"drawn" => "map", "headers" => headers} = run(dir, key, library_graph(key))

        assert headers[branch] == header, key
      end
    end

    # One band per branch, drawn in the branch's own box, spanning every arm
    # from the leftmost's left edge to the rightmost's right edge, above
    # all of them and below the header; the fork mark inside it.
    #
    # Sabotage: made bandOf span the first arm only; this went red. Made
    # drawBand leave the fork mark out; this went red. Made the server leave
    # no band room (@band_room 0); the band overlapped the header and this
    # went red. Each reverted from a copy.
    test "both library branches draw their arms under one band with a fork mark",
         %{tmp_dir: dir} do
      for {key, branch, _next, header} <- @branches do
        graph = library_graph(key)
        %{"drawn" => "map", "boxes" => boxes, "bands" => bands} = run(dir, key, graph)

        assert Map.keys(bands) == [branch], key
        assert [%{"in" => ^branch, "fork" => %{} = fork} = band] = bands[branch]

        arms =
          for %{"kind" => "slot", "style" => "arm", "id" => id} <-
                find(graph, branch)["children"],
              do: boxes[id]

        assert length(arms) == 4
        left = arms |> Enum.map(& &1["x"]) |> Enum.min()
        right = arms |> Enum.map(&(&1["x"] + &1["width"])) |> Enum.max()
        top = arms |> Enum.map(& &1["y"]) |> Enum.min()
        box = boxes[branch]
        header_bottom = box["y"] + 12 + (length(header) + 1) * 16

        assert_in_delta band["x"], left, 0.5, key
        assert_in_delta band["x"] + band["width"], right, 0.5, key
        assert band["y"] + band["height"] <= top, key
        assert band["y"] >= header_bottom - 4, key

        assert fork["x"] >= band["x"] and fork["x"] <= band["x"] + band["width"], key
        assert fork["y"] >= band["y"] and fork["y"] <= band["y"] + band["height"], key
      end
    end

    # The branch's rejoin is the edge out of it: drawn from the branch's
    # bottom edge, with its join dot there, into the top of the next node.
    #
    # Sabotage: made the server mark the edge out of a branch "sequence";
    # this went red. Made put_end/2 add no end mark; the loan's rejoin went
    # missing and this went red. Made drawEdge draw no join dot; this went
    # red. Dropped the dot's data-map-edge; this went red. Each reverted
    # from a copy.
    test "both library branches rejoin from their bottom edge into the next node",
         %{tmp_dir: dir} do
      for {key, branch, next, _header} <- @branches do
        %{
          "drawn" => "map",
          "html" => html,
          "boxes" => boxes,
          "rejoins" => rejoins,
          "edges" => edges
        } =
          run(dir, key, library_graph(key))

        id = "#{branch}->#{next}"
        assert [%{"id" => ^id, "d" => d, "dot" => dot}] = rejoins

        assert [%{"kind" => "rejoin", "source" => ^branch, "target" => ^next}] =
                 Enum.filter(edges, &(&1["kind"] == "rejoin"))

        [start | _rest] = points = path_points(d)
        stop = List.last(points)
        from = boxes[branch]
        to = boxes[next]

        assert_in_delta start.y, from["y"] + from["height"], 0.5, "#{key}: start"
        assert start.x > from["x"] and start.x < from["x"] + from["width"]
        assert_in_delta stop.y, to["y"], 0.5, "#{key}: end"
        assert stop.x >= to["x"] and stop.x <= to["x"] + to["width"]
        assert %{"x" => dot_x, "y" => dot_y} = dot
        assert_in_delta dot_x, start.x, 0.5
        assert_in_delta dot_y, start.y, 0.5

        # The dot carries its rejoin's id, so pointing at it names the rejoin.
        escaped = String.replace(id, ">", "&gt;")
        assert html =~ ~s(data-map-join="#{escaped}" data-map-edge="#{escaped}")
      end
    end

    # The band, the fork mark, the join dot and the end mark select nothing
    # new: a click on the band or its fork answers what a click on the
    # branch answers, and the end mark is not clickable at all.
    #
    # Sabotage: gave the end mark data-map-kind="block"; it became a
    # clickable box and this went red. Dropped its data-map-node; this went
    # red. Each reverted from a copy.
    test "the band, the rejoin and the end mark arm no new gesture", %{tmp_dir: dir} do
      for {key, branch, _next, _header} <- @branches do
        %{"html" => html, "gestures" => gestures, "childGestures" => children} =
          run(dir, key, library_graph(key), "editable")

        refute Enum.any?(gestures, &String.contains?(&1["element"], "/end"))

        for %{"element" => element, "gesture" => gesture} <- children,
            element == "block:#{branch}" do
          assert gesture == %{"event" => "select-row", "payload" => %{"block-id" => branch}}
        end

        [end_tag] = Regex.run(~r/<g [^>]*data-map-end=[^>]*>/, html) || [""]
        refute end_tag =~ "data-map-kind"

        # It still carries its id, so the description region can name it.
        if key == "library_loan", do: assert(end_tag =~ ~s(data-map-node="blk_ll_root/end"))
      end
    end
  end

  describe "the Group, as drawn" do
    # The two library groups, their body's pane and their rules column, the
    # rules in rail order.
    @groups [
      {"library_loan", "blk_ll_on_loan", ["blk_ll_returned_early", "blk_ll_reported_lost"]},
      {"patron_registration", "blk_pr_verify", ["blk_pr_abandoned", "blk_pr_expired"]}
    ]

    # The body is the group's first child and is drawn first; it sits to the
    # left of the rules column, wider than it and at least as tall; every
    # step of the body is inside it.
    #
    # Sabotage: made inline?/2 inline a group's body again; the pane went
    # missing and this went red. Dropped the column's size from the pane's
    # minimum (slot_options/4 "body"); the pane came out narrower than the
    # column and this went red. Each reverted from a copy.
    test "both library groups draw their body first and larger than their rules column",
         %{tmp_dir: dir} do
      for {key, group, _rules} <- @groups do
        graph = library_graph(key)
        %{"drawn" => "map", "html" => html, "boxes" => boxes} = run(dir, key, graph)
        body_id = "#{group}/body"
        rules_id = "#{group}/interrupts"

        assert [%{"id" => ^body_id, "style" => "body"} = pane, %{"id" => ^rules_id}] =
                 find(graph, group)["children"]

        body = boxes[body_id]
        rules = boxes[rules_id]

        assert body["x"] + body["width"] <= rules["x"],
               "#{key}: the body is not left of the rules"

        assert body["width"] > rules["width"], "#{key}: #{body["width"]} <= #{rules["width"]}"
        assert body["height"] >= rules["height"], "#{key}: #{body["height"]} < #{rules["height"]}"

        {body_at, _len} = :binary.match(html, ~s(data-map-node="#{body_id}"))
        {rules_at, _len} = :binary.match(html, ~s(data-map-node="#{rules_id}"))
        assert body_at < rules_at, "#{key}: the rules are drawn before the body"

        for %{"kind" => "block", "id" => step} <- pane["children"] do
          assert inside?(boxes[step], body), "#{key}: #{step} is outside the body"
        end
      end
    end

    # The rules stand in one column, top to bottom in rail order, each
    # inside the column's box.
    #
    # Sabotage: dropped separateConnectedComponents from the column's
    # options; ELK packed the rules by size and the registration's came out
    # of order, and this went red. Reverted from a copy.
    test "both library groups stack their rules in one column, in rail order",
         %{tmp_dir: dir} do
      for {key, group, rules} <- @groups do
        %{"drawn" => "map", "boxes" => boxes} = run(dir, key, library_graph(key))
        column = boxes["#{group}/interrupts"]

        for rule <- rules, do: assert(inside?(boxes[rule], column), "#{key}: #{rule}")

        for [upper, lower] <- Enum.chunk_every(rules, 2, 1, :discard) do
          assert boxes[lower]["y"] >= boxes[upper]["y"] + boxes[upper]["height"],
                 "#{key}: #{lower} is not below #{upper}"
        end
      end
    end

    # The rules column carries the group's caption on the line under its
    # label, above its first rule; the branch's band carries the branch's,
    # inside the band and after the fork mark. Both are the host's one
    # module's text.
    #
    # Sabotage: made drawNode leave a slot's caption out; this went red.
    # Made drawBand leave the band's caption out; this went red. Each
    # reverted from a copy.
    test "the rules column and the branch band carry their captions", %{tmp_dir: dir} do
      branches = %{"library_loan" => "blk_ll_due", "patron_registration" => "blk_pr_age"}

      for {key, group, [first | _rules]} <- @groups do
        %{"drawn" => "map", "boxes" => boxes, "bands" => bands, "captions" => captions} =
          run(dir, key, library_graph(key))

        rules_id = "#{group}/interrupts"
        column = boxes[rules_id]
        group_caption = TypeExplanation.caption("core.group")

        assert [%{"text" => ^group_caption, "x" => x, "y" => y}] = captions[rules_id]
        assert x > column["x"] and x < column["x"] + column["width"], key
        assert y > column["y"] + 16 and y < boxes[first]["y"], key

        branch = branches[key]
        branch_caption = TypeExplanation.caption("core.branch")
        [band] = bands[branch]

        assert [%{"text" => ^branch_caption, "x" => bx, "y" => by}] = captions[branch]
        assert bx > band["fork"]["x"] and bx < band["x"] + band["width"], key
        assert by > band["y"] and by <= band["y"] + band["height"], key
        assert band["x"] + band["width"] - bx >= text_width([branch_caption]) - 24, key
      end
    end
  end

  describe "the happy path, as drawn" do
    # Each library group, the steps of its body, and the steps of the
    # document's own flow after it.
    @happy [
      {"library_loan", "blk_ll_on_loan", ["blk_ll_loan_period"],
       ["blk_ll_due", "blk_ll_root/end"]},
      {"patron_registration", "blk_pr_verify", ["blk_pr_deadline", "blk_pr_email"],
       ["blk_pr_age", "blk_pr_welcome"]}
    ]

    # How far off one line a step's centre may sit, in pixels.
    @straight 1.0

    # The body's steps and the steps after the group are centred on one
    # vertical line, and the edge out of the group runs down it: it leaves
    # the group's bottom and enters the next step's top on the line.
    #
    # Sabotage: made put_ports/2 answer its node unchanged; the edge left
    # the middle of the group and the body's steps stood left of the line,
    # and this went red. Made onPorts attach no edge; this went red. Made
    # put_ports/2 count one padding, not two; the line moved 12px and this
    # went red. Made offPorts give no edge back its ends; the edge out of
    # the group came back from its port and this went red. Each reverted
    # from a copy.
    test "both library fixtures run their body's steps and what follows down one line",
         %{tmp_dir: dir} do
      for {key, group, steps, after_group} <- @happy do
        %{"drawn" => "map", "boxes" => boxes, "edges" => edges} =
          run(dir, key, library_graph(key))

        [line | _rest] = centres = Enum.map(steps ++ after_group, &centre(boxes[&1]))

        for {id, x} <- Enum.zip(steps ++ after_group, centres) do
          assert_in_delta x, line, @straight, "#{key}: #{id} is off the line at #{x}, not #{line}"
        end

        [next | _rest] = after_group
        id = "#{group}->#{next}"

        edge =
          Enum.find(edges, &(&1["id"] == id)) || flunk("#{key}: #{id} is not drawn")

        assert %{"source" => ^group, "target" => ^next} = edge
        assert_in_delta edge["start"]["x"], line, @straight, "#{key}: #{id} start"
        assert_in_delta edge["end"]["x"], line, @straight, "#{key}: #{id} end"
      end
    end

    # The rules column and every abandon edge drawn out of it stand to the
    # right of the body's steps, so nothing that interrupts the happy path
    # is drawn on it.
    #
    # Sabotage: made interruptsOf end an exit edge 30px in from the group's
    # left edge; the edge crossed the body's steps and this went red.
    # Reverted from a copy.
    test "both library fixtures draw their rules and abandon ends beside the happy path",
         %{tmp_dir: dir} do
      for {key, group, steps, _after_group} <- @happy do
        graph = library_graph(key)

        %{"drawn" => "map", "boxes" => boxes, "interrupts" => drawn} =
          run(dir, key, graph)

        right = steps |> Enum.map(&(boxes[&1]["x"] + boxes[&1]["width"])) |> Enum.max()
        column = boxes["#{group}/interrupts"]

        assert column["x"] > right, "#{key}: the rules column is not beside the steps"

        exits = for %{"to" => "exit"} = edge <- drawn, edge["target"] == group, do: edge
        refute exits == [], key

        for %{"id" => id, "d" => d} <- exits, point <- path_points(d) do
          assert point.x > right, "#{key}: #{id} crosses the happy path at #{point.x}"
        end
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

    # A real click lands on the rect, text, circle or path inside a drawn
    # group, and reaches the group by walking up. The driver's elements walk
    # up the same way, and every child answers what its group answers.
    #
    # Sabotage: made mapGesture match only the clicked element itself, not
    # its ancestors; every child click came back null and this went red.
    # Reverted from a copy.
    test "a click on a drawn child answers what its group answers", %{tmp_dir: dir} do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))

        %{"gestures" => gestures, "childGestures" => children} =
          run(dir, fixture.key, graph, "editable")

        by_element = Map.new(gestures, &{&1["element"], &1["gesture"]})

        refute children == []

        for %{"element" => element, "child" => tag, "gesture" => gesture} <- children do
          assert gesture == by_element[element], "#{fixture.key}: a click on #{element}'s #{tag}"
        end

        for element <- Map.keys(by_element) do
          assert Enum.any?(children, &(&1["element"] == element)), "#{element} has no child"
        end
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

  defp library_graph(key) do
    {:ok, fixture} = Charts.fixture(key)
    PlanMap.graph(ViewModel.build(fixture.document, Charts.palette(), []))
  end

  defp find(graph, id), do: Enum.find(walk(graph), &(&1["id"] == id))

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

  # The points of an SVG path drawn as `M x y L x y ...`.
  defp path_points(d) do
    for [_all, x, y] <- Regex.scan(~r/[ML](-?[\d.]+) (-?[\d.]+)/, d) do
      %{x: number(x), y: number(y)}
    end
  end

  defp number(text) do
    {value, ""} = Float.parse(text)
    value
  end

  defp centre(box), do: box["x"] + box["width"] / 2

  # Whether `box` lies wholly inside `outer`.
  defp inside?(box, outer) do
    box["x"] >= outer["x"] and box["y"] >= outer["y"] and
      box["x"] + box["width"] <= outer["x"] + outer["width"] and
      box["y"] + box["height"] <= outer["y"] + outer["height"]
  end

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
