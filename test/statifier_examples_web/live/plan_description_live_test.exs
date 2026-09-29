defmodule StatifierExamplesWeb.PlanDescriptionLiveTest do
  # Not async, for `StatifierExamplesWeb.PlanLiveTest`'s reason: the page
  # reads `StatifierExamples.Documents`, one named Agent that `ConnCase`
  # resets in `setup`.
  use StatifierExamplesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamplesWeb.EventPhrasing

  @library ["library_loan", "patron_registration"]
  @kinds ~w(block rule arm undecided_arm rules marker start edge interrupt timer)

  @region "#plan-description"
  @store "#plan-description-store"

  describe "the region" do
    # The region is always drawn, at the top of the panel and outside the
    # map's `aria-hidden` region, and with nothing selected it describes the
    # document.
    #
    # Sabotage: drew a line of the panel's own above the page's
    # `description_region`; this went red. Reverted from a copy.
    test "is at the top of the panel, aria-live polite, and idle on mount", %{conn: conn} do
      for key <- @library do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")
        page = LazyHTML.from_document(html)

        [region] = page |> LazyHTML.query(@region) |> Enum.to_list()
        assert LazyHTML.attribute(region, "aria-live") == ["polite"]

        assert page
               |> LazyHTML.query("section#plan-description.sb-map__description")
               |> Enum.count() == 1

        assert LazyHTML.attribute(region, "data-map-description") == ["idle"]

        # First thing in the panel.
        [first | _rest] = page |> LazyHTML.query("#plan-panel > *") |> Enum.to_list()
        assert LazyHTML.attribute(first, "id") == ["plan-description"]

        # Not inside the map, which a screen reader never reaches.
        assert page |> LazyHTML.query("[aria-hidden] #{@region}") |> Enum.count() == 0

        text = LazyHTML.text(region)
        assert text =~ fixture(key).document.metadata["name"]
        assert text =~ "Starts when told to"
        assert text =~ "Open slots"
      end
    end

    # Every row of the list points at the region, on the row and on the
    # button a keyboard focuses; the id it names exists exactly once.
    #
    # Sabotage: dropped `aria-describedby` from the row's sentence button;
    # this went red. Reverted from a copy.
    test "every list row names the region with aria-describedby", %{conn: conn} do
      for key <- @library do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")
        page = LazyHTML.from_document(html)

        rows = page |> LazyHTML.query("li[data-block-id]") |> Enum.to_list()
        assert length(rows) == length(ViewModel.outline(view_model(key)))

        for row <- rows do
          assert LazyHTML.attribute(row, "aria-describedby") == ["plan-description"]

          [button] = row |> LazyHTML.query("button.myapp-plan__sentence") |> Enum.to_list()
          assert LazyHTML.attribute(button, "aria-describedby") == ["plan-description"]
          assert LazyHTML.attribute(button, "phx-click") == ["select-row"]
        end

        assert page |> LazyHTML.query(~s([id="plan-description"])) |> Enum.count() == 1
      end
    end

    # Keyboard reachability, as the markup proves it: every control that
    # sends an event - the list's rows and the panel's controls - is a real
    # `<button>` or a form, none of them inside the map's `aria-hidden`
    # region, and pressing a row's button (its `select-row`) changes what
    # the region says.
    #
    # Sabotage: drew the panel's Delete control as a `<span phx-click>`
    # instead of a `<button>`; this went red. Reverted from a copy.
    test "every control is a real button outside the hidden map", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      assert LazyHTML.attribute(region(html), "data-map-description") == ["idle"]

      selected = view |> sentence_button("blk_ll_loan_period") |> render_click()
      page = LazyHTML.from_document(selected)

      clickable = page |> LazyHTML.query("[phx-click]") |> Enum.to_list()
      assert clickable != []

      for element <- clickable do
        assert LazyHTML.tag(element) == ["button"], LazyHTML.to_html(element)
      end

      assert page |> LazyHTML.query("#plan-panel button") |> Enum.count() > 0
      assert page |> LazyHTML.query("ol.myapp-plan__list button") |> Enum.count() > 0
      assert page |> LazyHTML.query("[aria-hidden] [phx-click]") |> Enum.count() == 0
      assert page |> LazyHTML.query("[aria-hidden] [phx-change]") |> Enum.count() == 0

      region = region(selected)
      assert LazyHTML.attribute(region, "data-map-description") == ["block"]
      assert LazyHTML.text(region) =~ "Wait 21d"
    end

    # The keyboard path: a row's sentence is a button, and pressing it fills
    # the region with that block; pressing it again returns the idle text.
    #
    # Sabotage: passed `selected={nil}` to the page's `description_region`
    # instead of the list's selection; this went red. Reverted from a copy.
    test "selecting a row fills it, deselecting returns it to idle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")

      html = view |> sentence_button("blk_ll_loan_period") |> render_click()
      region = region(html)

      assert LazyHTML.attribute(region, "data-map-description") == ["block"]
      text = LazyHTML.text(region)
      assert text =~ "Wait 21d"
      assert text =~ "Settings"
      assert text =~ "Wait for"
      assert text =~ "21d"
      assert text =~ "Step 1 of 1 in Steps of Group (Run interruptible steps)"
      assert text =~ "When the copy is returned, abandons Group"

      html = view |> sentence_button("blk_ll_loan_period") |> render_click()
      region = region(html)
      assert LazyHTML.attribute(region, "data-map-description") == ["idle"]
      assert LazyHTML.text(region) =~ "Riverbend Public Library loan"
    end

    # A rule is its own kind in the region too, and the root is described
    # as the root.
    #
    # Sabotage: passed `selected={nil}` to the page's `description_region`;
    # this went red on the rule. Reverted from a copy.
    test "selecting a rule or the root", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      rule = view |> sentence_button("blk_pr_expired") |> render_click() |> region()
      assert LazyHTML.attribute(rule, "data-map-description") == ["rule"]
      assert LazyHTML.text(rule) =~ "registration.deadline"

      root = view |> sentence_button("blk_pr_root") |> render_click() |> region()
      assert LazyHTML.text(root) =~ "The root: every other step sits inside it"
    end

    # Values, never controls, and nothing that posts: the region and the
    # store add no command to the page.
    #
    # Sabotage: none on this side. The markup inside the region and the
    # store is the package's, and no change to this page puts a control
    # there; the case stays as the embedder's check on that promise.
    test "shows values and never controls, and adds no command", %{conn: conn} do
      for key <- @library, readonly <- [nil, "1"] do
        {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: key, readonly: readonly]}")

        for {id, _kind} <- stored(render(view)) do
          html = if block?(key, id), do: select(view, id), else: render(view)
          described = LazyHTML.from_document(html)

          for area <- [@region, @store],
              control <- ["input", "select", "textarea", "button", "a", "form"] do
            assert described |> LazyHTML.query("#{area} #{control}") |> Enum.count() == 0,
                   "#{key} #{id}: a #{control} in #{area}"
          end

          # `phx-r` is LiveView's own render bookkeeping; every binding that
          # sends an event is `phx-<event>` or a hook.
          for area <- [@region, @store] do
            markup = described |> LazyHTML.query(area) |> LazyHTML.to_html()
            refute markup =~ ~r/phx-(click|change|submit|blur|focus|key|hook|window|value)/
          end

          if block?(key, id), do: select(view, id)
        end
      end
    end
  end

  describe "the store" do
    # Every element the map draws is described on the page, under the map's
    # own id, and the two library fixtures between them draw every kind.
    #
    # Sabotage: gave the page's `description_region` a different id from
    # the one its map region names (`plan-description-x`); the store moved
    # off `#plan-description-store` and this went red. Reverted from a copy.
    test "describes every drawn element on the two fixtures", %{conn: conn} do
      kinds =
        for key <- @library, reduce: MapSet.new() do
          acc ->
            {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")
            stored = stored(html)

            assert stored |> Enum.map(&elem(&1, 0)) |> Enum.sort() == drawn_ids(key),
                   "#{key}: the store is not the map's elements"

            assert html
                   |> LazyHTML.from_document()
                   |> LazyHTML.query("#{@store}[hidden]")
                   |> Enum.count() == 1

            MapSet.union(acc, stored |> Enum.map(&elem(&1, 1)) |> MapSet.new())
        end

      for kind <- @kinds, do: assert(kind in kinds, "no #{kind} on the page")
    end

    # Each kind's words are on the page, on each fixture that draws it.
    #
    # Sabotage: dropped `phrase={&EventPhrasing.phrase/1}` from the page's
    # `description_region`; the event names read as authored and this went
    # red. Reverted from a copy.
    test "each kind carries its own facts", %{conn: conn} do
      {:ok, _view, loan} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      {:ok, _view, patron} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      assert stored_text(loan, "blk_ll_due/arm_renew") =~ "copy.holds == 0 AND loan.renewals"
      assert stored_text(loan, "blk_ll_due/undecided") =~ "cannot be decided"
      assert stored_text(loan, "blk_ll_due/undecided/empty") =~ BlockMap.empty_text()

      assert stored_text(loan, "blk_ll_on_loan/interrupts") =~
               "When the copy is returned, abandon"

      assert stored_text(loan, "blk_ll_returned_early") =~ "abandons Group"

      assert stored_text(loan, "blk_ll_overdue_notice->blk_ll_late_return") =~
               "After Send word that the loan is overdue"

      assert stored_text(patron, "blk_pr_age/undecided") =~
               "Send word that the patron is asked to visit"

      assert stored_text(patron, "blk_pr_age/otherwise/empty") =~ "the end of Branch"
      assert stored_text(patron, "blk_pr_deadline") =~ "7d"
    end

    # The store follows the document: a write through the list reaches it.
    #
    # Sabotage: assigned the view model with `assign_new/3` in rebuild/1,
    # so the first one stuck; this went red. Reverted from a copy.
    test "a change made through the list reaches the store", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")
      assert "blk_pr_welcome" in Enum.map(stored(html), &elem(&1, 0))

      after_remove = render_hook(view, "remove", %{"block-id" => "blk_pr_welcome"})
      refute "blk_pr_welcome" in Enum.map(stored(after_remove), &elem(&1, 0))
    end
  end

  # ---------------------------------------------------------------- helpers

  defp fixture(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture
  end

  defp view_model(key), do: ViewModel.build(fixture(key).document, Charts.palette(), [])

  defp drawn_ids(key) do
    %{"children" => children} =
      graph = key |> view_model() |> BlockMap.graph(phrase: &EventPhrasing.phrase/1)

    timers = graph |> Map.get("timers", []) |> Enum.map(& &1["id"])
    (Enum.flat_map(children, &ids/1) ++ timers) |> Enum.sort()
  end

  defp ids(node) do
    [node["id"]] ++
      (node |> Map.get("children", []) |> Enum.flat_map(&ids/1)) ++
      (node |> Map.get("edges", []) |> Enum.map(& &1["id"])) ++
      (node |> Map.get("interrupts", []) |> Enum.map(& &1["id"]))
  end

  defp block?(key, id), do: ViewModel.find_node(view_model(key), id) != nil

  defp sentence_button(view, block_id),
    do: element(view, ~s(li[data-block-id="#{block_id}"] button.myapp-plan__sentence))

  defp select(view, block_id), do: view |> sentence_button(block_id) |> render_click()

  defp region(html) do
    [region] = html |> LazyHTML.from_document() |> LazyHTML.query(@region) |> Enum.to_list()
    region
  end

  # `{id, kind}` for every stored description, in page order.
  defp stored(html) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query("#{@store} > [data-describes]")
    |> Enum.map(fn entry ->
      {entry |> LazyHTML.attribute("data-describes") |> hd(),
       entry |> LazyHTML.attribute("data-describes-kind") |> hd()}
    end)
  end

  defp stored_text(html, id) do
    html
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s(#{@store} > [data-describes="#{id}"]))
    |> LazyHTML.text()
  end
end
