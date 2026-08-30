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

  describe "the card title" do
    # The bead's criterion, read off the rendered page rather than off the
    # schema: a step's config label is the card's title and the block type's
    # own label drops to the subtitle underneath it. Three named blocks, each
    # a leaf, so the child combinator addresses one card and not a subtree.
    #
    # Sabotage: dropped label_field/0 from Charts.Step.config_schema/2 - the
    # declaration is the whole of what ViewModel.title/1 reads - and all three
    # rows went red with the type name where the label belongs; then reverted.
    test "a step's label titles its card and its type becomes the subtitle",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      for {id, title, type} <- [
            {"blk_cp_intake", "Take the payment request", "Intake"},
            {"blk_cp_risk_rating", "Rate the transaction", "Risk rating"},
            {"blk_cp_receipt", "Build the receipt", "Receipt"}
          ] do
        assert card(view, id, "sb-node__label") =~ title
        assert card(view, id, "sb-node__type") =~ type
      end
    end

    # The wizard's two types reach the field through their own helper,
    # `StatifierExamples.Signup.Step`, which declared `invoke_type` directly
    # until this bead gave it a schema. A card-processing-only assertion would
    # not have noticed that second copy at all.
    #
    # Sabotage: put signup_step.ex back on Step.invoke_type_field/1; this went
    # red on the subtitle, then reverted.
    test "the wizard's steps are titled the same way", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      assert card(view, "blk_su_account", "sb-node__label") =~ "Collect email and password"
      assert card(view, "blk_su_account", "sb-node__type") =~ "Signup step"
      assert card(view, "blk_su_provision", "sb-node__label") =~ "Create the workspace"
    end

    # "The label sits first in the inspector form", the bead's other half,
    # read off the rendered form rather than off the schema: the inspector
    # draws one control per schema field in declaration order, so the order
    # the app declares is only observably the form's order here.
    #
    # Sabotage: put label_field/0 after invoke_type_field/1 in
    # Charts.Step.config_schema/2; this went red, then reverted.
    test "the label is the first control in the inspector form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      view
      |> element(~s([data-block-id="blk_cp_intake"] > .sb-node__chrome > .sb-node__label))
      |> render_click()

      form = view |> element(~s(form[data-block-id="blk_cp_intake"])) |> render()

      assert [label_at, invoke_at] =
               Enum.map(["Label", "Invoke type"], fn text ->
                 {at, _len} = :binary.match(form, text)
                 at
               end)

      assert label_at < invoke_at
    end

    # The control the two rows above need: an unlabelled block is titled by
    # its palette entry and carries no subtitle at all, which is what says the
    # declaration adds a title rather than a second line to every card.
    #
    # No sabotage note: nothing in `lib/` here decides this. `core.branch` is
    # the package's type and the fixture gives it no label, so the assertion
    # is on `statifier_blocks`' fallback and no mutation of this app's code
    # can move it.
    test "a block with no label of its own carries no subtitle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert card(view, "blk_cp_validation", "sb-node__label") =~ "Branch"

      refute has_element?(
               view,
               ~s([data-block-id="blk_cp_validation"] > .sb-node__chrome > .sb-node__type)
             )
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

  describe "the editor chrome the dependency carries" do
    # `se-jat` moved the app onto the statifier_blocks build that carries the
    # chrome parity work, and the only thing that made the new chrome appear
    # was the dependency. That is exactly the kind of change a screenshot
    # proves and nothing else does - so this asserts the shell's structural
    # markers instead, one per parity piece, and a later version bump that
    # loses one goes red here rather than in a capture nobody re-reads.
    #
    # `se-5ez` re-pinned that build from its git SHA to Hex `~> 0.4`; 0.4.0
    # is the release of the same chrome, and these markers held across it.
    #
    # Structural class and event names only. What they LOOK like is the
    # package's, and this app asserting a colour would be asserting the
    # package's stylesheet from the wrong repo.
    #
    # Sabotage: pinned mix.exs back to 890d95d - the SHA this app carried
    # before se-jat - and re-ran; the canvas-panel assertion went red (the
    # palette fold is the other marker that pin does not have at all, and the
    # rest are names whose MEANING moved rather than names that arrived),
    # then reverted.
    test "the shell, the panes and the drawer row all render", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      # The tier-2 grid, and the full-width drawer row under it.
      assert html =~ "sb-editor__layout"
      assert html =~ "sb-drawer__strip"

      # The canvas is a framed panel with its own header, not a bare stage.
      assert html =~ "sb-canvas-panel"

      # The palette folds; the inspector is a three-tab pane.
      assert html =~ ~s(phx-click="palette-collapse")
      assert html =~ ~s(phx-click="inspector-tab")

      # The card face carries its own delete.
      assert html =~ ~s(phx-click="remove")

      # And a container's body is boxed when it is a boundary (10c/10h).
      assert html =~ "sb-node--boundary"
    end
  end

  @spec card(Phoenix.LiveViewTest.View.t(), String.t(), String.t()) :: String.t()
  defp card(view, block_id, class) do
    view
    |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .#{class}))
    |> render()
  end
end
