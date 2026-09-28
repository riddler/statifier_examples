defmodule StatifierExamplesWeb.PlanEmptySlotLiveTest do
  # Not async, for `StatifierExamplesWeb.PlanLiveTest`'s reason: the page
  # reads and writes `StatifierExamples.Documents`, one named Agent that
  # `ConnCase` resets in `setup`.
  use StatifierExamplesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Edit
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamples.Documents
  alias StatifierExamplesWeb.PlanMap

  # The map's empty-slot marker is the one insert the list has no row for.
  # These cases reach the same gap from the keyboard: select a row in the
  # list, and the panel offers one button per empty slot of that block,
  # posting the marker's own `insert-open` payload. None of them touches the
  # map or its hook.

  @key "patron_registration"
  @branch "blk_pr_age"
  @slot "otherwise"

  @slot_buttons ~s(#plan-panel button[data-plan-empty-slot])

  describe "the panel's empty-slot buttons" do
    # Parity with the map, asked of every fixture: for every block the map
    # draws an empty marker in, selecting that block's row offers exactly
    # the markers' slots, each as the payload the marker sends. The
    # expectation is read off `PlanMap.graph/1`, so a slot the map marks and
    # the panel misses, or the reverse, is a difference here.
    #
    # Sabotage: made the panel offer only a block's body slots; the rail
    # markers (an invoke's failure slot) had no button and this went red.
    # Reverted from a copy.
    test "offer the slots the map marks empty, for every block of every fixture",
         %{conn: conn} do
      for fixture <- Charts.fixtures() do
        markers = markers(fixture.document)

        {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: fixture.key]}")

        for {block_id, slots} <- markers do
          html = select(view, block_id)
          page = LazyHTML.from_fragment(html)

          offered =
            page
            |> LazyHTML.query(@slot_buttons)
            |> Enum.map(fn button ->
              assert LazyHTML.attribute(button, "phx-click") == ["insert-open"]
              assert LazyHTML.attribute(button, "phx-value-block-id") == [block_id]
              [slot] = LazyHTML.attribute(button, "phx-value-slot")
              slot
            end)

          assert offered == slots,
                 "#{fixture.key} #{block_id}: panel offers #{inspect(offered)}, " <>
                   "map marks #{inspect(slots)}"
        end
      end
    end

    # Each button is a real `<button>`, outside the map's `aria-hidden`
    # region, and says which slot it adds to by the slot's label.
    #
    # Sabotage: rendered the button's text as the slot's name rather than
    # its label; "Add a step to Otherwise" was gone and this went red.
    # Reverted from a copy.
    test "are buttons named by the slot's label, outside the hidden map", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: @key]}")
      page = view |> select(@branch) |> LazyHTML.from_fragment()

      [button] = page |> LazyHTML.query(@slot_buttons) |> Enum.to_list()
      assert LazyHTML.tag(button) == ["button"]
      assert LazyHTML.attribute(button, "type") == ["button"]
      assert LazyHTML.text(button) =~ ~r/^\s*Add a step to Otherwise\s*$/
      assert page |> LazyHTML.query("[aria-hidden] [data-plan-empty-slot]") |> Enum.count() == 0
    end

    # The keyboard path end to end: select the row, press the panel's
    # button, pick a type. The step lands at the head of the slot, exactly
    # where the package's own insert at that position puts it.
    #
    # Sabotage: made the button post the slot's label rather than its name;
    # the slot key named no slot, nothing was armed and this went red.
    # Reverted from a copy.
    test "arm the slot's picker, and a pick lands at the slot's head", %{conn: conn} do
      :ok = Documents.reset()
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: @key]}")
      select(view, @branch)

      html = view |> element(@slot_buttons, "Otherwise") |> render_click()
      assert panel(html) =~ ~s(data-plan-slot-insert="#{@branch}/#{@slot}")

      view
      |> element(~s(#plan-panel [data-plan-picker="open"] button), ~r/^\s*Wait\s*$/)
      |> render_click()

      original = fixture(@key).document
      {:ok, wait} = Palette.new_block(Charts.palette(), "core.wait")
      {:ok, expected, _inverse} = Edit.apply(original, {:insert, {@branch, @slot, 0}, wait})

      assert normalize(document(@key), original) == normalize(expected, original)
      assert slot_types(document(@key), @branch, @slot) == ["core.wait"]
    end

    # The list stays complete: arming a slot from the panel removes no row,
    # and the step it inserts gets a row of its own.
    #
    # Sabotage: dropped the armed slot's block from the plan's rows while
    # its picker was open; its row was missing and this went red. Reverted
    # from a copy.
    test "leave every row in the list, and the new step gets one", %{conn: conn} do
      :ok = Documents.reset()
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: @key]}")
      before = row_ids(html)
      assert before == outline_ids(fixture(@key).document)

      select(view, @branch)
      armed = view |> element(@slot_buttons, "Otherwise") |> render_click()
      assert row_ids(armed) == before

      after_insert =
        view
        |> element(~s(#plan-panel [data-plan-picker="open"] button), ~r/^\s*Wait\s*$/)
        |> render_click()

      assert row_ids(after_insert) == outline_ids(document(@key))
      assert length(row_ids(after_insert)) == length(before) + 1
    end

    # A block whose every slot holds a step, and a block with no slot,
    # offer none; neither does a read-only page, which draws no control.
    #
    # Sabotage: dropped `not @readonly?` from the buttons' condition; the
    # read-only panel drew one and this went red. Reverted from a copy.
    test "are drawn only where a slot is empty and the page edits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: @key]}")
      assert view |> select("blk_pr_verify") |> slot_buttons() == 0
      assert view |> select("blk_pr_welcome") |> slot_buttons() == 0
      assert view |> select(@branch) |> slot_buttons() == 1

      {:ok, readonly, _html} = live(conn, ~p"/plan?#{[doc: @key, readonly: "1"]}")
      assert readonly |> select(@branch) |> slot_buttons() == 0
    end
  end

  # ----------------------------------------------------------------- helpers

  defp fixture(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture
  end

  defp document(key), do: Documents.get(key, fixture(key).document)

  # The map's empty markers, as `[{block id, [slot name]}]` in the order the
  # map draws them - read off the graph the page's own map is drawn from.
  defp markers(%Document{} = document) do
    document
    |> ViewModel.build(Charts.palette(), [])
    |> PlanMap.graph()
    |> Map.fetch!("children")
    |> Enum.flat_map(&empties/1)
    |> Enum.group_by(fn {parent, _slot} -> parent end, fn {_parent, slot} -> slot end)
    |> Enum.to_list()
  end

  defp empties(%{"kind" => "empty", "parent" => parent, "slot" => slot}), do: [{parent, slot}]
  defp empties(%{"children" => children}), do: Enum.flat_map(children, &empties/1)
  defp empties(_leaf), do: []

  defp select(view, block_id) do
    view
    |> element(~s(li[data-block-id="#{block_id}"] button.myapp-plan__sentence))
    |> render_click()
  end

  defp slot_buttons(html),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(@slot_buttons) |> Enum.count()

  defp panel(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.query("#plan-panel") |> LazyHTML.to_html()
  end

  defp row_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("li.myapp-plan__row")
    |> Enum.flat_map(&LazyHTML.attribute(&1, "data-block-id"))
  end

  # Every block the list draws, in the page's order: the plan, then the
  # rails, then the trays - the three sections the page draws `outline/1` in.
  defp outline_ids(%Document{} = document) do
    outline = document |> ViewModel.build(Charts.palette(), []) |> ViewModel.outline()

    for kinds <- [[:step, :arm], [:rail], [:tray]],
        {node, _depth, kind} <- outline,
        kind in kinds,
        do: node.block_id
  end

  defp block_ids(%Document{} = document), do: document |> Document.blocks() |> Enum.map(& &1.id)

  # `document` with every block `original` does not have renamed "new": the
  # page and the package each mint their own id for an inserted block.
  defp normalize(%Document{root: root} = document, %Document{} = original) do
    known = original |> block_ids() |> MapSet.new()
    %{document | root: rename_new(root, known)}
  end

  defp rename_new(%Block{id: id, slots: slots} = block, known) do
    slots =
      Map.new(slots, fn {name, children} -> {name, Enum.map(children, &rename_new(&1, known))} end)

    %{block | id: if(MapSet.member?(known, id), do: id, else: "new"), slots: slots}
  end

  defp slot_types(%Document{} = document, block_id, slot) do
    document
    |> Document.blocks()
    |> Enum.find(&(&1.id == block_id))
    |> Map.fetch!(:slots)
    |> Map.get(slot, [])
    |> Enum.map(& &1.type)
  end
end
