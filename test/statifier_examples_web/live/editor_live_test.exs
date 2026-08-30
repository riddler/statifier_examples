defmodule StatifierExamplesWeb.EditorLiveTest do
  use StatifierExamplesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StatifierExamples.Charts

  @themes ["light", "dark", "brand"]

  describe "mounting by URL" do
    # The acceptance criterion the bead states, asserted as the product of the
    # two axes rather than one representative of each: a theme that only fails
    # on one document, or a document that only fails in one theme, is exactly
    # what a pair of single-axis tests misses.
    #
    # Sabotage: dropped the data-theme attribute from the page root in
    # render/1; every theme row went red, then reverted.
    test "every fixture renders in every theme", %{conn: conn} do
      for fixture <- Charts.fixtures(), theme <- @themes do
        {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: fixture.key, theme: theme]}")

        assert html =~ "sb-editor"
        assert html =~ ~s(data-theme="#{theme}")
        assert html =~ fixture.name
        assert html =~ "revision #{fixture.document.revision}"
        assert html =~ fixture.document.id
      end
    end

    # Sabotage: made document_param/2 return {:ok, fixture} straight from
    # Charts.fixture/1; this went red on the unknown key, then reverted.
    test "an unknown document is the first fixture", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "no_such_document"]}")

      assert html =~ hd(Charts.fixtures()).name
    end

    # Sabotage: made theme_param/1 fall back to :brand; this went red, then
    # reverted.
    test "an unknown theme is light", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[theme: "chartreuse"]}")

      assert html =~ ~s(data-theme="light")
    end

    # Sabotage: made handle_params/3 read params["doc"] without the is_binary
    # guard; the bare-path mount went red with a FunctionClauseError, then
    # reverted.
    test "the bare path mounts on the first fixture in light", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor")

      assert html =~ hd(Charts.fixtures()).name
      assert html =~ ~s(data-theme="light")
    end
  end

  describe "the header" do
    # Sabotage: removed the :header slot from the live_component call in
    # render/1; the header assertions went red, then reverted.
    test "carries the document identity, both switchers and Compile", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert html =~ "sb-editor__header"
      assert html =~ "myapp-header__title"
      assert html =~ "Card processing"
      assert html =~ "revision 42"
      assert html =~ "bdoc_cp_demo"
      assert html =~ ~s(id="doc-select")
      assert html =~ ~s(id="theme-select")
      assert html =~ "Compile"
    end

    # R1: undo and redo are the package's toolbar, not the host's header. Two
    # pairs of controls over one history is the thing the ruling forbids, and
    # the header is where the second pair would appear.
    #
    # Sabotage: added an Undo button to the header markup; this went red, then
    # reverted.
    test "carries no undo or redo of its own", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor")

      refute view |> element(".myapp-header") |> render() =~ "Undo"
      refute view |> element(".myapp-header") |> render() =~ "Redo"
    end

    # Sabotage: made the DOCUMENT form push a phx-click instead of a
    # phx-change; this went red, then reverted.
    test "the DOCUMENT switcher patches the url", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      html =
        view
        |> element("form[phx-change='select-document']")
        |> render_change(%{"doc" => "signup_wizard"})

      assert html =~ "Signup wizard"
      assert_patched(view, "/editor?doc=signup_wizard&theme=light")
    end

    # Sabotage: made select-theme push the first fixture's key instead of the
    # one on the socket; this went red, then reverted.
    test "the THEME switcher patches the url and keeps the document", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      html =
        view
        |> element("form[phx-change='select-theme']")
        |> render_change(%{"theme" => "brand"})

      assert html =~ ~s(data-theme="brand")
      assert html =~ "Signup wizard"
      assert_patched(view, "/editor?doc=signup_wizard&theme=brand")
    end
  end

  describe "the strict compile" do
    # The card-processing fixture carries exactly one deliberate finding: it
    # names myapp.legacy_check, which no palette entry answers, so the
    # unavailable-block chrome is exercised at depth 7. That is the fixture's
    # documented reason for existing, which is why the count is asserted
    # exactly rather than as "at least one".
    #
    # Sabotage: made compiler_findings/1 return [] for the {:error, _} branch -
    # the branch this fixture's finding arrives on, because an unresolvable
    # block type stops the compile at the resolve stage rather than warning;
    # this went red, then reverted.
    test "card processing reports its one deliberate finding", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert html =~ "1 finding"

      assert view |> element("button[phx-click='compile']") |> render_click() =~ "1 finding"
    end

    # Sabotage: made verdict/1 answer "0 findings" for zero; this went red,
    # then reverted.
    test "a document with nothing to report reads clean", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      assert html =~ "clean"
      assert view |> element("button[phx-click='compile']") |> render_click() =~ "clean"
    end
  end

  describe "the icon seam" do
    # The host component wins on every tile - the canvas cards and the palette
    # rows alike - so a page that rendered the package's SHIPPED glyphs
    # instead would still look fine and would still be wrong. The shipped set
    # stamps the same tile classes and the same data-icon attribute for the
    # same names, so none of those separates the two; what does is the glyph
    # itself, asserted as the body Charts.Icons read out of the heroicons
    # dependency rather than as a path string transcribed into this file.
    #
    # Sabotage: dropped the icon assign from the live_component call - the
    # editor fell back to its shipped set and every assertion but the last one
    # stayed green; this went red on the last, then reverted.
    test "the host's heroicons render on the cards and the palette", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert html =~ "sb-node__icon"
      assert html =~ "sb-palette__icon"
      assert html =~ ~s(data-icon="credit-card")
      # The path data, pulled out of the glyph the icon module read rather
      # than transcribed here. The whole element cannot be matched: the test
      # helper re-serializes the DOM, so a self-closing `<path/>` comes back
      # as `<path></path>` and a verbatim comparison fails on markup nobody
      # wrote.
      assert [_whole, credit_card_path] =
               Regex.run(~r/ d="([^"]+)"/, Charts.Icons.body("credit-card"))

      assert html =~ credit_card_path
    end
  end
end
