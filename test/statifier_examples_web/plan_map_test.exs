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
  alias StatifierExamplesWeb.TypeExplanation

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

  describe "captions" do
    # A group's rules column and a branch carry the host's one module's
    # caption for their type, and nothing else on the map carries one.
    #
    # Sabotage: made put_caption/3 caption every rail, not only a group's;
    # the card fixture's failure path came back captioned and this went
    # red. Made put_band/2 leave the caption off; this went red. Each
    # reverted from a copy.
    test "only a group's rules column and a branch carry a caption, the host's own text" do
      for fixture <- Charts.fixtures() do
        graph = PlanMap.graph(view_model(fixture))

        expected =
          for node <- walk(graph),
              node["kind"] == "block",
              type = ViewModel.find_node(view_model(fixture), node["id"]).type,
              TypeExplanation.caption(type) != nil,
              into: %{} do
            if node["band"],
              do: {node["id"], TypeExplanation.caption(type)},
              else: {"#{node["id"]}/interrupts", TypeExplanation.caption(type)}
          end

        captioned =
          for node <- walk(graph), node["caption"], into: %{}, do: {node["id"], node["caption"]}

        assert captioned == expected, fixture.key
      end

      assert find(graph("library_loan"), "blk_ll_on_loan/interrupts")["caption"] ==
               "leave the group when they happen"
    end
  end

  describe "event names in words" do
    # The two teaching documents draw their event names as words, and
    # every other document draws its sentences exactly as the package
    # writes them.
    #
    # Sabotage: made block/1 draw ViewModel.sentence/1 again; this went
    # red. Reverted from a copy.
    test "a box's line reads the library world's event names as words" do
      loan = graph("library_loan")
      assert find(loan, "blk_ll_close")["lines"] == ["Send word that the loan is closed"]

      assert find(loan, "blk_ll_late_return")["lines"] |> Enum.join(" ") =~
               "Wait until the copy is returned"

      for key <- ["library_loan", "patron_registration"],
          node <- walk(graph(key)),
          line <- Map.get(node, "lines", []),
          event <- ~w(copy.returned loan.closed registration.deadline email.verified) do
        refute line =~ event, "#{key}: #{node["id"]} draws #{event} as a name"
      end
    end

    # Sabotage: made EventPhrasing.sentence/1 end every sentence with a
    # full stop; this went red. Reverted from a copy.
    test "a document whose events have no words draws the package's sentence" do
      for fixture <- Charts.fixtures(),
          fixture.key not in ["library_loan", "patron_registration"] do
        view_model = view_model(fixture)

        for %{"kind" => "block", "id" => id, "lines" => [_ | _] = lines} = node <-
              walk(PlanMap.graph(view_model)),
            not Map.has_key?(node, "children") do
          sentence = view_model |> ViewModel.find_node(id) |> ViewModel.sentence()
          assert Enum.join(lines, " ") == sentence, "#{fixture.key}: #{id}"
        end
      end
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
          Map.has_key?(node, "width"),
          # The start dot and the end marks carry no text to be wide enough for.
          node["kind"] not in ["start", "end"] do
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
    # red. Reverted from a copy. Took the head from the group's first
    # child, the body's pane itself, rather than the pane's first; this
    # went red. Reverted from a copy.
    test "a resume rule leads to the head of its group's body" do
      resumes =
        for fixture <- Charts.fixtures(),
            edge <- PlanMap.interrupts(PlanMap.graph(view_model(fixture))),
            edge["to"] == "body",
            do: {fixture.key, edge}

      refute resumes == []

      for {key, %{"group" => group}} <- resumes do
        node = find(graph(key), group)
        # The body is the group's first child, a pane; its head is the pane's first.
        assert [%{"style" => "body", "children" => [%{"id" => head} | _steps]} | _rest] =
                 node["children"]

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
      body = find(graph("patron_registration"), "blk_pr_verify/body")

      assert Enum.map(body["children"], & &1["id"]) == [
               "blk_pr_deadline",
               "blk_pr_email",
               "blk_pr_age",
               "blk_pr_welcome"
             ]

      assert Enum.map(body["edges"], &{&1["sources"], &1["targets"]}) == [
               {["blk_pr_deadline"], ["blk_pr_email"]},
               {["blk_pr_email"], ["blk_pr_age"]},
               {["blk_pr_age"], ["blk_pr_welcome"]}
             ]
    end
  end

  describe "the happy path" do
    # A group whose body is all leaves attaches its edges at a fixed point
    # on its top and bottom sides: its and its pane's padding (12 each)
    # plus half its widest step. A group whose body holds a container has
    # no width to read and carries no ports.
    #
    # Sabotage: made put_ports/2 put out ports for any body with a leaf in
    # it; the card group whose body holds containers carried ports and
    # this went red. Made it count one padding, not two; this went red.
    # Each reverted from a copy.
    #
    # The loan's group is the group of leaves: the registration's group
    # holds its age branch in its body, so the deadline ends the document,
    # and a body holding a container carries no ports.
    test "a group of leaves carries its two ports where its steps stand, and no other does" do
      on_loan = find(graph("library_loan"), "blk_ll_on_loan")
      x = 12 + 12 + 150 / 2

      assert on_loan["layoutOptions"]["org.eclipse.elk.portConstraints"] == "FIXED_POS"

      assert [
               %{"id" => "blk_ll_on_loan#in", "x" => ^x, "layoutOptions" => north},
               %{"id" => "blk_ll_on_loan#out", "x" => ^x, "layoutOptions" => south}
             ] = on_loan["ports"]

      assert north == %{"org.eclipse.elk.port.side" => "NORTH"}
      assert south == %{"org.eclipse.elk.port.side" => "SOUTH"}

      for {key, id} <- [
            {"card_processing", "blk_cp_authz"},
            {"patron_registration", "blk_pr_verify"}
          ] do
        group = find(graph(key), id)
        refute Map.has_key?(group, "ports"), id
        refute Map.has_key?(group["layoutOptions"], "org.eclipse.elk.portConstraints"), id
      end

      for fixture <- Charts.fixtures(),
          node <- walk(PlanMap.graph(view_model(fixture))),
          Map.has_key?(node, "ports") do
        assert [%{"style" => "body"} | _rest] = node["children"], fixture.key
      end
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

        for %{"edges" => edges} <- walk(graph),
            %{"kind" => kind, "sources" => [from], "targets" => [to]} <- edges do
          expected =
            cond do
              String.ends_with?(from, "/start") -> "start"
              from in branches -> "rejoin"
              String.contains?(to, "/end/") -> "end"
              true -> "sequence"
            end

          assert kind == expected,
                 "#{fixture.key}: #{from}"
        end
      end
    end
  end

  describe "the end" do
    # Every end of every fixture's own flow is one of the outline's: a
    # `done` end for the `:exit` edge from the root's last step into the
    # root's exit, and an `abandon` end where that step is a group one of
    # whose rules abandons it. `done` is the outline's own outcome for the
    # root, which is why the map may write it rather than read it. No end
    # mark is a block.
    #
    # Sabotage: made put_ends/2 draw no end; this went red. Made
    # abandons/1 answer [] for every step; the registration's abandon end
    # went missing and this went red. Made abandons/1 read every rule as an
    # abandon; no fixture has a resume rule on its last step, so this
    # stayed green - the test after next holds that. Each reverted from a
    # copy.
    test "every fixture's ends are Describe's, one per way it finishes" do
      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)
        graph = PlanMap.graph(view_model)
        outline = Describe.outline(fixture.document, Charts.palette(), [])
        root = view_model.root.block_id

        done =
          for %Edge{kind: :exit, container: ^root, from: {:block, last}} <- outline.edges,
              do: {last, "done"}

        abandon =
          for {last, "done"} <- done,
              %Edge{kind: :interrupt, container: ^last, to: {:exit, ^last}} <- outline.edges,
              uniq: true,
              do: {last, "abandon"}

        drawn =
          for node <- walk(graph),
              %{"sources" => [from], "targets" => [to], "outcome" => outcome} <-
                Map.get(node, "edges", []),
              do: {from, outcome, to}

        assert Enum.map(drawn, fn {from, outcome, _to} -> {from, outcome} end) ==
                 done ++ abandon,
               fixture.key

        refute done == [], fixture.key
        assert %Describe.Node{outcomes: ["done"]} = Enum.find(outline.nodes, &(&1.id == root))

        for {_from, outcome, to} <- drawn do
          assert to == "#{root}/end/#{outcome}"
          assert %{"kind" => "end", "outcome" => ^outcome} = find(graph, to)
          refute to in PlanMap.nodes(graph)
        end
      end
    end

    # The loan finishes when its branch does: the branch rejoins into one
    # solid end. The registration's group is its last step and its rules
    # abandon it, so it finishes done or abandoned: two ends, the edge into
    # each captioned with its outcome.
    #
    # Sabotage: made end_edge/4 caption every edge "done"; this went red.
    # Made put_ends/2 give the edge out of a branch kind "end"; this went
    # red. Each reverted from a copy.
    test "the loan ends done after its branch, the registration done or abandoned" do
      root = find(graph("library_loan"), "blk_ll_root")

      assert Enum.map(root["children"], & &1["id"]) ==
               ["blk_ll_root/start", "blk_ll_on_loan", "blk_ll_due", "blk_ll_root/end/done"]

      assert %{"kind" => "end", "outcome" => "done"} = done = List.last(root["children"])
      refute Map.has_key?(done, "title")

      assert List.last(root["edges"]) == %{
               "id" => "blk_ll_due->blk_ll_root/end/done",
               "sources" => ["blk_ll_due"],
               "targets" => ["blk_ll_root/end/done"],
               "kind" => "rejoin",
               "outcome" => "done",
               "labels" => [
                 %{
                   "id" => "blk_ll_due->blk_ll_root/end/done/caption",
                   "text" => "done",
                   "width" => 52,
                   "height" => 16
                 }
               ]
             }

      root = find(graph("patron_registration"), "blk_pr_root")

      assert Enum.map(root["children"], & &1["id"]) ==
               [
                 "blk_pr_root/start",
                 "blk_pr_verify",
                 "blk_pr_root/end/done",
                 "blk_pr_root/end/abandon"
               ]

      assert [
               %{"kind" => "end", "outcome" => "done", "labels" => [%{"text" => "done"}]},
               %{"kind" => "end", "outcome" => "abandon", "labels" => [%{"text" => "abandon"}]}
             ] = Enum.filter(root["edges"], &Map.has_key?(&1, "outcome"))

      assert Enum.map(Enum.filter(root["edges"], &Map.has_key?(&1, "outcome")), & &1["sources"]) ==
               [["blk_pr_verify"], ["blk_pr_verify"]]
    end

    # A group whose rules only resume it is never left by them, so it ends
    # the document done and nothing else; a group of abandon rules adds the
    # one abandon end however many rules there are.
    #
    # Sabotage: made abandons/1 read every rule as an abandon; the resume
    # group drew an abandon end and this went red. Made abandons/1 add two
    # abandon ends; this went red. Each reverted from a copy.
    test "only an abandon rule adds an abandon end, once" do
      for {outcomes, ends} <- [
            {["resume"], ["done"]},
            {["abandon", "abandon"], ["done", "abandon"]},
            {["resume", "abandon"], ["done", "abandon"]}
          ] do
        rules =
          for {outcome, n} <- Enum.with_index(outcomes),
              do:
                Block.new("core.on_event",
                  id: "rule#{n}",
                  config: %{"event" => "e#{n}", "outcome" => outcome}
                )

        group =
          Block.new("core.group",
            id: "held",
            slots: %{
              "body" => [Block.new("core.send", id: "s", config: %{"event" => "x"})],
              "interrupts" => rules
            }
          )

        root = Block.new("core.sequence", id: "root", slots: %{"body" => [group]})

        graph =
          root
          |> Document.new()
          |> ViewModel.build(Charts.palette(), [])
          |> PlanMap.graph()

        assert for(%{"kind" => "end", "outcome" => outcome} <- walk(graph), do: outcome) == ends,
               inspect(outcomes)
      end
    end

    # A step that is last in a nested flow hands back to the block around
    # it, which goes on: no end follows it. Every Send in the two library
    # fixtures is such a step - at the foot of an arm or of the
    # registration's body - and none is joined to an end; every end is
    # joined to the root's last step alone.
    #
    # Sabotage: made put_ends/2 join the end to the last step of its last
    # step's first slot - a Send in both fixtures - rather than to the last
    # step itself; this went red. Reverted from a copy.
    test "a send that continues is followed by no end" do
      for key <- ["library_loan", "patron_registration"] do
        {:ok, fixture} = Charts.fixture(key)
        view_model = view_model(fixture)
        graph = PlanMap.graph(view_model)

        sends =
          for {%Node{type: "core.send", block_id: id}, _depth, _kind} <-
                ViewModel.outline(view_model),
              do: id

        refute sends == [], key

        [last | _rest] =
          view_model.root
          |> ViewModel.body_slots()
          |> hd()
          |> ViewModel.flow_children()
          |> Enum.reverse()

        into_ends =
          for node <- walk(graph),
              %{"sources" => [from], "targets" => [to]} <- Map.get(node, "edges", []),
              String.contains?(to, "/end/"),
              do: from

        refute into_ends == [], key
        assert Enum.uniq(into_ends) == [last.block_id], key
        for send <- sends, do: refute(send in into_ends, "#{key}: #{send}")
      end
    end
  end

  describe "the start" do
    # One start dot per document, first among the root's children, and one
    # start edge from it into the first step of the root's own flow,
    # captioned with the one sentence - whether the document declares the
    # events it accepts (the library fixtures) or declares none (the card
    # and signup fixtures). The dot is no block: it is in no outline.
    #
    # Sabotage: made put_start/2 answer the graph unchanged; this went red.
    # Made put_start/2 aim the edge at the root instead of the first step;
    # this went red. Made start_edge/2's label name an accepted event
    # instead of the one sentence; this went red. Each reverted from a copy.
    test "every fixture starts once, with one captioned edge into its first step" do
      assert PlanMap.start_text() == "Starts when told to"

      accepts = for fixture <- Charts.fixtures(), do: fixture.document.accepts != []
      assert true in accepts and false in accepts

      for fixture <- Charts.fixtures() do
        view_model = view_model(fixture)
        graph = PlanMap.graph(view_model)
        root_id = view_model.root.block_id
        start = "#{root_id}/start"

        [%{block_id: first} | _rest] =
          view_model.root |> ViewModel.body_slots() |> hd() |> ViewModel.flow_children()

        assert [%{"id" => ^start, "kind" => "start"} = dot] =
                 Enum.filter(walk(graph), &(&1["kind"] == "start"))

        refute Map.has_key?(dot, "title")
        assert [^dot | _rest] = find(graph, root_id)["children"]

        edges = for node <- walk(graph), edge <- Map.get(node, "edges", []), do: edge

        assert [
                 %{
                   "sources" => [^start],
                   "targets" => [^first],
                   "labels" => [%{"text" => "Starts when told to"}]
                 }
               ] = Enum.filter(edges, &(&1["kind"] == "start"))

        refute start in PlanMap.nodes(graph)
      end
    end

    # A document with no step yet starts into its root's empty marker.
    #
    # Sabotage: made put_start/2 fall back to the root, not the first drawn
    # child, when the flow is empty; this went red. Reverted from a copy.
    test "a document with no step starts into its empty slot" do
      graph =
        Block.new("core.sequence", id: "root", slots: %{"body" => []})
        |> Document.new()
        |> ViewModel.build(Charts.palette(), [])
        |> PlanMap.graph()

      root = find(graph, "root")

      assert [%{"id" => "root/start"}, %{"id" => "root/body/empty"}] = root["children"]

      assert [%{"sources" => ["root/start"], "targets" => ["root/body/empty"]}] =
               root["edges"]
    end

    # A root whose flow is not drawn inside it - a group, whose body is a
    # pane of its own - has its dot above its box and its edge into the box.
    #
    # Sabotage: dropped the inline? check from put_start/2; the group
    # root's dot went inside its box and this went red. Reverted from a
    # copy.
    test "a root whose flow is not drawn inside it starts above its box" do
      graph =
        Block.new("core.group",
          id: "held",
          slots: %{
            "body" => [
              Block.new("core.await", id: "wait", config: %{"event" => "hold.collected"})
            ],
            "interrupts" => []
          }
        )
        |> Document.new()
        |> ViewModel.build(Charts.palette(), [])
        |> PlanMap.graph()

      assert [%{"id" => "held/start", "kind" => "start"}, %{"id" => "held"}] = graph["children"]

      assert [%{"sources" => ["held/start"], "targets" => ["held"], "kind" => "start"}] =
               graph["edges"]

      refute Enum.any?(find(graph, "held")["children"], &(&1["kind"] == "start"))
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
