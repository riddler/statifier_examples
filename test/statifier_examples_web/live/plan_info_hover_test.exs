defmodule StatifierExamplesWeb.PlanInfoHoverTest do
  @moduledoc """
  The description region on hover: the page's own `PlanInfo` hook
  (`assets/js/plan_info.mjs`) run over what the Plan page actually
  rendered.

  Hover happens in the browser, so the only honest test of it runs the
  same JavaScript. `test/support/js/plan_info_hover.mjs` draws the page's
  own map graph with the map hook's `drawMap`, mounts the real hook over
  the page's region and store, points at every element the drawing
  carries and at every child of each, and prints what the region held
  each time. Node must be on the path, as for the map's layout tests.
  """

  # Not async, for `StatifierExamplesWeb.PlanLiveTest`'s reason: the page
  # reads `StatifierExamples.Documents`, one named Agent that `ConnCase`
  # resets in `setup`.
  use StatifierExamplesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts

  @driver Path.expand("../../support/js/plan_info_hover.mjs", __DIR__)
  @hook Path.expand("../../../assets/js/plan_info.mjs", __DIR__)

  describe "the hook's element" do
    # The hook sits on an element of its own, outside the region, the store
    # and the map, and names the region and the store by ids the page has.
    #
    # Sabotage: named the store `plan-description` in `data-store`; this
    # went red. Reverted from a copy.
    test "is its own element, naming the region and the store", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      page = LazyHTML.from_document(html)

      [hook] = page |> LazyHTML.query(~s([phx-hook="PlanInfo"])) |> Enum.to_list()
      assert LazyHTML.attribute(hook, "id") == ["plan-info"]
      assert LazyHTML.attribute(hook, "data-region") == ["plan-description"]
      assert LazyHTML.attribute(hook, "data-store") == ["plan-descriptions"]

      for inside <- ["#plan-description", "#plan-descriptions", "#plan-map", "[aria-hidden]"] do
        assert page |> LazyHTML.query(~s(#{inside} [phx-hook="PlanInfo"])) |> Enum.count() == 0
      end
    end
  end

  describe "hover" do
    # Every element the map draws, and every child of each, fills the region
    # with exactly that element's stored description, and moving off puts
    # the idle description back byte for byte - on every fixture, so a shape
    # only one document draws is still pointed at.
    #
    # Sabotage: made `show` in plan_info.mjs copy nothing into the region;
    # every hover came back unshown and this went red. Reverted from a copy.
    test "fills the region from the store and restores the idle content", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: fixture.key]}")
        result = run(render(view))

        assert result["missing"] == [], "#{fixture.key}: drawn with no description"
        refute result["hovers"] == []

        for hover <- result["hovers"] do
          where = "#{fixture.key}: #{hover["element"]} #{hover["child"]}"
          assert hover["id"] == hover["element"], where
          assert hover["shown"], "#{where}: the region did not show its entry"
          assert hover["restored"], "#{where}: moving off did not restore the region"
        end
      end
    end

    # The rest of the pointer's paths: straight from one element to another,
    # out of the window, onto a gap's "+", and off after a patch has already
    # redrawn the region.
    #
    # Sabotage: made `restore` put the kept content back without asking for
    # the hover mark; the patched region was overwritten and this went red.
    # Reverted from a copy.
    test "chained, out of the window, over a gap, and after a patch", %{conn: conn} do
      for key <- ["library_loan", "patron_registration"] do
        {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: key]}")

        assert %{"chained" => true, "outOfWindow" => true, "gaps" => true, "stale" => true} =
                 run(render(view)),
               key
      end
    end

    # A row selected after the page is up patches the region; moving off a
    # hovered element then restores the selected block's description, not
    # the document's the page mounted with.
    #
    # Sabotage: made hover/2 keep the region's content once, when the hook
    # mounted, and restore that; every restore came back with the idle
    # description and this went red. Reverted from a copy.
    test "restores the selected block's description", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      idle = page(html)

      %{"region" => selected} =
        view
        |> element(~s(li[data-block-id="blk_ll_loan_period"] button.myapp-plan__sentence))
        |> render_click()
        |> page()

      assert selected =~ "Wait 21d"
      refute selected == idle["region"]

      result = run_page(Map.put(idle, "patched", selected))
      refute result["hovers"] == []
      assert Enum.all?(result["hovers"], & &1["restored"])
    end

    # A hover never reaches the server: the hook pushes nothing, whatever it
    # is pointed at, leaves no listener behind, and its source names no push.
    #
    # Sabotage: added `this.pushEvent("hover", {})` to the hook's
    # mouseover listener; `pushes` came back non-empty and this went red.
    # Reverted from a copy.
    test "pushes nothing to the server", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      assert %{"pushes" => [], "listening" => 0} = run(render(view))
      refute File.read!(@hook) =~ "pushEvent("
    end
  end

  # ---------------------------------------------------------------- helpers

  defp run(html), do: html |> page() |> run_page()

  # What the page rendered, as the driver reads it: the map's graph, the
  # region's markup, and the store's entries.
  defp page(html) do
    doc = LazyHTML.from_document(html)

    [graph] = doc |> LazyHTML.query("#plan-map") |> LazyHTML.attribute("data-graph")

    entries =
      doc
      |> LazyHTML.query("#plan-descriptions > [data-describes]")
      |> Enum.map(fn entry ->
        %{
          "id" => entry |> LazyHTML.attribute("data-describes") |> hd(),
          "html" => entry |> LazyHTML.child_nodes() |> LazyHTML.to_html()
        }
      end)

    region = doc |> LazyHTML.query("#plan-description") |> LazyHTML.child_nodes()

    %{"graph" => Jason.decode!(graph), "region" => LazyHTML.to_html(region), "entries" => entries}
  end

  defp run_page(page) do
    dir = Path.join(System.tmp_dir!(), "plan-info-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "page.json")
    File.write!(path, Jason.encode!(page))

    node = System.find_executable("node") || flunk("the hover tests need Node on the PATH")
    {out, status} = System.cmd(node, [@driver, path], stderr_to_stdout: true)
    File.rm_rf!(dir)
    assert status == 0, out
    Jason.decode!(out)
  end
end
