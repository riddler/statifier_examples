defmodule StatifierExamplesWeb.EditorLiveTest do
  use StatifierExamplesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Editor
  alias StatifierBlocks.Finding
  alias StatifierBlocks.Shell
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable}

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
      assert html =~ "revision 43"
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
    # Sabotage: dropped label_field/0 from the step config_schema/2 - the
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

    # The wizard's two types reached the field through a second helper of
    # their own until se-lin folded it into the app's step helper, and se-4dt.1
    # moved that helper's job to `StatifierBlocks.InvokeStep`.
    # A card-processing-only assertion would not have noticed that copy at
    # all, which is why this one covers the other domain too.
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
    # the step config_schema/2; this went red, then reverted.
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
    # its palette entry, and whatever subtitle it carries is the package's,
    # not a second line the host's declaration put there. That is what says
    # the declaration adds a title rather than a subtitle to every card.
    #
    # No sabotage note: nothing in `lib/` here decides this. `core.branch` is
    # the package's type and the fixture gives it no label, so the assertion
    # is on `statifier_blocks`' own rendering and no mutation of this app's
    # code can move it.
    #
    # 2026-08-30 (se-3io): before statifier_blocks 0.5.0 this refuted a
    # subtitle outright. The package now summarises core blocks in that slot,
    # so an unlabelled `core.branch` reads "1 arm + otherwise"; the row
    # asserts the summary instead, and still refutes the title being repeated
    # there.
    #
    # 2026-08-30 (se-e63, pin moved to the 0.6.0 prep): sb-2mxa split the
    # card's second line in two. `subtitle/1` is now the type label and is
    # `nil` for an unlabelled block, so `.sb-node__type` is absent entirely;
    # the summary moved to a chip row, `.sb-node__summary` > `.sb-node__chip`.
    # The row reads the chip row, which is where the summary lives now.
    test "a block with no label of its own is titled by its palette entry",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert card(view, "blk_cp_validation", "sb-node__label") =~ "Branch"

      summary = card(view, "blk_cp_validation", "sb-node__summary")

      assert summary =~ "arm"
      refute summary =~ "Branch"
    end
  end

  describe "the strict compile" do
    # D1 (campaign 018): the package's number is THE number. The compiler's
    # count and the drawer's are not the same count - the compiler reports
    # what it found, and `ViewModel` derives findings of its own on top of
    # whatever the caller hands in - so the header used to render the first
    # beside a drawer showing the second, and card processing was the document
    # that made the gap visible. `Editor.findings_count/3` is the seam sb-ukgu
    # added for exactly this, and it is read here with the SAME assigns the
    # component is passed, which is the whole condition on the two agreeing.
    #
    # The `seam > length(raw)` assertion is the criterion's "more than one
    # source", asserted as a relation rather than as two literals: the point
    # is that the header follows the seam and not the compiler, and a fixture
    # edit that changes either number by one should not have to edit this file
    # to keep saying so.
    #
    # Sabotage: put the pre-018 header back - verdict/2 answering
    # `length(findings)` instead of asking the seam; this went red with
    # "Findings 1" where "Findings 2" belongs, then reverted.
    test "the header verdict is the package's findings number", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      %{raw: raw, seam: seam} = counts("card_processing")

      assert seam > length(raw)
      assert html =~ "Findings #{seam}"
      refute html =~ "#{length(raw)} finding"

      assert view |> element("button[phx-click='compile']") |> render_click() =~
               "Findings #{seam}"
    end

    # The wording, at the value where the host's old vocabulary and the
    # package's diverge most: the package prints a zero and the host used to
    # print a word. Mirroring it exactly is the ruling - the drawer has no
    # singular form and no "clean", so neither does the header.
    #
    # Sabotage: made verdict/2 answer "clean" for a zero count again (the same
    # mutation as the row above, which also restores the word); this went red,
    # then reverted.
    test "a document with nothing to report reads the package's zero", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      assert %{seam: 0} = counts("signup_wizard")
      assert html =~ "Findings 0"
      refute html =~ "clean"

      assert view |> element("button[phx-click='compile']") |> render_click() =~ "Findings 0"
    end

    # The title is the package's own constant rather than a string this app
    # spells for itself, and this is what says so: the same function the
    # drawer titles its strip and its tab with. A package that renamed the tab
    # would move both at once, and a host that had transcribed the word would
    # be the only thing left saying the old one.
    #
    # Sabotage: covered by the same mutation as the first row, which this went
    # red alongside. The SPELLING is not this app's to break - it comes back
    # out of the package either way - and that is the point of the row: what a
    # mutation here can move is the number beside it, and what a package rename
    # would move is both sides of this assertion at once.
    test "the verdict carries the drawer's own title", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert html =~ "#{Shell.drawer_title(:findings)} #{counts("card_processing").seam}"
    end
  end

  describe "the fit the page opens at" do
    # D3 / sb-ehqn: the spike opened every document at Fit width and the
    # authors who used it never pressed the button, so the host opts in
    # through the package's `fit` attr instead of leaving a first-render zoom
    # of 100% on a document wider than the scroller. The attr is the mode, and
    # the canvas carries it as `data-fit`; the zoom itself needs a measurement
    # only the browser has, so the mount-time evidence is the mode and not a
    # number.
    #
    # Every fixture, because the attr is on the one component call all three
    # go through and a single-document row would pass on a page that had
    # somehow acquired a second.
    #
    # Sabotage: dropped `fit={:width}` from the live_component call; all three
    # rows went red with data-fit="manual", then reverted.
    test "every fixture opens at Fit width", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: fixture.key]}")

        assert html =~ ~s(data-fit="width")
      end
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

  describe "the viewport bound" do
    # The bound itself is a stylesheet rule and has to be: the package
    # declares `--sb-editor-height: auto` on `.sb-editor` itself, so a
    # declaration on an ancestor - the page root, an inline style this app
    # could stamp there - loses to it and reaches nothing. The token is set
    # through a descendant selector, which is the recipe the package's
    # docs/theming.md documents, and a LiveViewTest cannot see a stylesheet.
    #
    # So the two halves are asserted against each other instead. The
    # declaration is read out of `assets/css/app.css`, and the selector it is
    # written with is run - as a selector - against the document the page
    # actually renders. A rule that stops declaring a length goes red on the
    # first test; a page root or an editor element that stops matching the
    # rule that bounds it goes red on the second. Neither half can drift away
    # from the other quietly, which is the failure this seam actually has:
    # everything still renders, and the drawer strip is simply below the fold.
    @bound_selector ".myapp-page .sb-editor"

    # Sabotage: replaced the calc with `auto` in app.css; this went red on the
    # `calc(100vh` assertion, then reverted.
    test "the stylesheet bounds the editor to the viewport" do
      declaration = bound_declaration()

      # A length, and the viewport is where it comes from.
      assert declaration =~ "calc(100vh"
      # The page's gutter is subtracted twice, because the editor's box is
      # inset by the page padding on both edges and the reference header is
      # inside the editor's own header slot rather than above it.
      assert declaration =~ "2 * var(--myapp-page-gutter)"
      refute declaration =~ "auto"
    end

    # Sabotage: renamed the page root's class to `myapp-shell` in render/1;
    # every fixture went red here while every other test in this file stayed
    # green, then reverted.
    test "every fixture page matches the selector the bound is written with", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: fixture.key]}")

        assert html
               |> LazyHTML.from_document()
               |> LazyHTML.query(@bound_selector)
               |> Enum.count() == 1
      end
    end

    # The value side of `--sb-editor-height` in the one rule that sets it, or
    # a failure naming what was looked for - an empty string would let the
    # assertions above pass against a stylesheet that lost the rule entirely.
    @spec bound_declaration() :: String.t()
    defp bound_declaration do
      css = File.read!("assets/css/app.css")
      pattern = ~r/#{Regex.escape(@bound_selector)}\s*\{([^}]*)\}/

      with [_, body] <- Regex.run(pattern, css),
           [_, value] <- Regex.run(~r/--sb-editor-height:\s*([^;]+);/, body) do
        String.trim(value)
      else
        _ ->
          flunk(
            "no `--sb-editor-height` declaration on `#{@bound_selector}` in assets/css/app.css"
          )
      end
    end
  end

  describe "the disabled Run button" do
    # Run refuses on a document that does not compile - `@compiled` is nil
    # and the button renders `disabled` - and that refusal has to be legible
    # from the page. The two halves are asserted against each other the way
    # the viewport bound above is: the attribute is read off the document the
    # app actually renders, and the treatment that attribute selects is read
    # out of `assets/css/app.css`, because a LiveViewTest cannot see a
    # stylesheet.
    #
    # Which fixtures compile is deliberately not written down here. The
    # expectation is taken from the same compiler call the page makes, so a
    # fixture that starts or stops compiling moves both sides at once instead
    # of turning this file red for a reason that is not about the button.
    @run_button ~s(.myapp-header__button[phx-click="run-start"])
    @disabled_rule ".myapp-header__button:disabled"

    # Sabotage: made the button's `disabled` read `is_nil(@run)` instead of
    # `is_nil(@compiled)` in render/1; this went red on the first compiling
    # fixture - which then renders disabled - along with the eleven run tests
    # that can no longer press Run, then reverted.
    test "Run carries `disabled` exactly when the document does not compile", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: fixture.key]}")

        compiles? = match?({:ok, _}, Durable.compile(fixture.document, fixture.declare))
        document = LazyHTML.from_document(html)
        expected = if compiles?, do: 0, else: 1

        assert document |> LazyHTML.query(@run_button) |> Enum.count() == 1

        assert document |> LazyHTML.query(@run_button <> "[disabled]") |> Enum.count() ==
                 expected
      end
    end

    # Sabotage: deleted the `background` and `color` lines from the rule in
    # app.css; this went red on both, then reverted.
    test "the stylesheet gives the disabled Run button its own treatment" do
      body = disabled_body()

      # Not a press, and it says so twice: the pointer, and the accent fill
      # every other header button wears taken off rather than kept and dimmed.
      assert body =~ "cursor: not-allowed"
      assert body =~ "background: transparent"
      assert body =~ "color: var(--sb-fg-muted)"

      # Every colour here is a theme token, which is what makes the enabled
      # and disabled buttons distinct in light and in dark rather than in
      # whichever one a literal was picked against.
      refute body =~ ~r/#[0-9a-fA-F]{3}/
    end

    # Sabotage: put the hover rule back as a bare `:hover`; this went red on
    # the `refute`, then reverted.
    test "the hover fill does not reach the disabled Run button" do
      css = File.read!("assets/css/app.css")

      assert css =~ ".myapp-header__button:hover:not(:disabled)"
      refute css =~ ~r/\.myapp-header__button:hover\s*\{/
    end

    # The body of the one rule that dresses the disabled state, or a failure
    # naming what was looked for - an empty string would let the assertions
    # above pass against a stylesheet that lost the rule entirely.
    @spec disabled_body() :: String.t()
    defp disabled_body do
      css = File.read!("assets/css/app.css")
      pattern = ~r/#{Regex.escape(@disabled_rule)}\s*\{([^}]*)\}/

      case Regex.run(pattern, css) do
        [_, body] -> body
        _ -> flunk("no `#{@disabled_rule}` rule in assets/css/app.css")
      end
    end
  end

  describe "running the open document" do
    # The bead's acceptance criteria, machine-checked against the rendered
    # page rather than against the run struct: a Run press starts a session,
    # and the editor paints the marks the host hands it.
    #
    # Sabotage: made `push_run/1` push `active_marks: []`; the
    # `data-run-active` assertion went red, then reverted.
    test "a Run press marks the active blocks on the canvas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      assert run(view) =~ ~s(data-run-active="true")

      assert view
             |> element(~s([data-block-id="blk_su_verify_wait"]))
             |> render() =~ ~s(data-run-active="true")
    end

    # The invoke mark and its outcome, on the block that finished last. Since
    # the reminder window landed (se-hp2) that is the `core.send` arming the
    # nudge: it completes in the same macrostep it is entered in, after the
    # verification call has already come back.
    #
    # Sabotage: made `push_run/1` push `invoke_mark: nil`; this went red on
    # the outcome attribute, then reverted.
    test "the block whose call came back carries the outcome", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)

      assert view
             |> element(~s([data-block-id="blk_su_reminder_timer"]))
             |> render() =~ ~s(data-invoke-outcome="done")
    end

    # The drawer's first host tenant. The tab is the package's markup and the
    # panel is this app's, so both halves are asserted: the strip names it,
    # and the rows are the feed's own.
    #
    # Sabotage: gave the descriptor the reserved id `tables`, which
    # `Shell.host_tabs/1` drops; the tab vanished and this went red, then
    # reverted.
    test "the run feed is a drawer tab, with the run's rows in it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      html = open_runs(view)

      assert html =~ "Runs"
      assert html =~ "myapp-runs"
      assert html =~ "Invoke dispatched"
      assert html =~ "Collect email and password"
      assert html =~ ~s(data-run-entry="outcome")
    end

    # se-5ep: the page's own compile has to carry the fixture's declared
    # `<data>` roots, because a guard reading a root nothing declared raises
    # `error.execution` rather than reading it as undefined - and so does
    # the wizard's `core.assign`, which runs two blocks into the run. The
    # feed is where a reader would see it, so the feed is where it is
    # refuted.
    #
    # Sabotage: dropped `declare:` from `compile/1` in `EditorLive`, leaving
    # the page compiling the wizard the way it did before this bead; the
    # `error.execution` row appeared in the drawer and this went red, then
    # reverted.
    test "the run of the shipped wizard raises nothing on the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      html = open_runs(view)

      refute html =~ "error.execution"
    end

    # The event affordance: one button per event the document declares, and
    # pressing it puts a row in the feed.
    #
    # The assertion is on the feed's DETAIL CELL and not on the string: the
    # button that sends the event carries the same name, so a page that
    # dropped the press entirely would still contain it.
    #
    # Sabotage: made the `run-send` handler drop the press instead of
    # sending the event; the row never appeared and this went red, then
    # reverted.
    test "an event button steps the run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      open_runs(view)

      view
      |> element(~s(button[phx-value-event="signup.email_verified"]))
      |> render_click()

      assert render_until(view, cell("signup.email_verified"))
    end

    # A run is a run OF a document, so switching documents ends it. The
    # assertion is on the HOST's own status, not on the marks: the editor
    # clears those itself on a document switch, so a host that kept its
    # session running would look identical on the canvas and differ only
    # here, which is exactly the defect worth catching.
    #
    # Sabotage: made `end_run_on_switch/2` return the socket unchanged; the
    # header still said `running` and this went red, then reverted.
    test "switching documents ends the run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      assert run(view) =~ ~s(data-run-status="running")

      html =
        view
        |> form("#document-switcher", %{"doc" => "card_processing"})
        |> render_change()

      refute html =~ "data-run-status"
      refute html =~ ~s(data-run-active="true")
    end

    # The invoke-type suggestions. The datalist stamps its own count, so the
    # assertion is that the host's list arrived rather than that some list
    # did: an empty `invoke_types` renders the same element with a 0.
    #
    # Sabotage: dropped the `invoke_types` attr from the component call; the
    # count came back 0 and this went red, then reverted.
    test "the host's invoke types reach the invoke_type field", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      html =
        view
        |> element(~s([data-block-id="blk_su_account"] .sb-node__label))
        |> render_click()

      assert html =~ ~s(data-invoke-types="#{length(Charts.invoke_types())}")
      assert html =~ "myapp:signup"
    end
  end

  describe "picking a durable run back up" do
    # The run id is in the URL because a durable run outlives the process
    # that started it, and a run nobody can name again is not much use
    # after a restart. This is the affordance the README's kill-and-resume
    # walkthrough turns into a step.
    #
    # Sabotage: made `patch_to_run/1` patch with `nil` for the run id; this
    # went red, then reverted.
    test "the Run press puts the run id in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)

      assert_patch(view) =~ "run="
    end

    # The restart, as the page sees it: a second mount that shares nothing
    # with the first but the URL, and comes up on the configuration the run
    # was left in.
    #
    # Sabotage: made `restore_run/2` ignore its run id and answer the
    # socket unchanged; the marks were gone and this went red, then
    # reverted.
    test "reloading the run URL resumes the stored run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      path = assert_patch(view)

      {:ok, resumed, html} = live(conn, path)

      assert html =~ ~s(data-run-status="running")

      assert resumed
             |> element(~s([data-block-id="blk_su_verify_wait"]))
             |> render() =~ ~s(data-run-active="true")

      assert open_runs(resumed) =~ "Run resumed from storage"
    end

    # And it steps: a resumed run answers the event buttons the same way,
    # which is what "continues" means on this page.
    #
    # Sabotage: made `send_run_event/2` drop its `Durable.send_event/3` and
    # answer the socket unchanged; the press did nothing and this went red,
    # along with the two other tests that step a run by pressing. Reverted.
    # (se-b2f: the note here used to name `run.session`, a field the deleted
    # in-memory driver owned.)
    test "a resumed run steps on the next press", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      {:ok, resumed, _html} = live(conn, assert_patch(view))

      open_runs(resumed)

      resumed
      |> element(~s(button[phx-value-event="signup.abandoned"]))
      |> render_click()

      assert render_until(resumed, cell("signup.abandoned"))
    end

    # se-k4a, on the page rather than on the driver: a run driven past the
    # verification wait finishes, and the header says `done` instead of
    # sitting on `running` forever. The page compiles with
    # `terminate: true`, and this is the only test that reads what that buys
    # a reader.
    #
    # se-d74 put one beat between the press and the finish. The abandon
    # route lands in the onboarding group, whose company-details step is
    # this app's one asynchronous call, so the press now leaves the run
    # RESTING on that invocation with the header still reading `running` -
    # which is the correct answer, not a stall. Draining the invocations
    # queue is that call's job running; the answer re-enters the stored run
    # and the page redraws off the broadcast, which is what `render_until/2`
    # is waiting for.
    #
    # Sabotage: dropped `terminate: true` from `EditorLive`'s `compile/1`;
    # the header stayed `running` through the drain and this went red on
    # the `render_until/2` flunk. Reverted.
    test "a run that reaches its root outcome finishes on the page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      assert_patch(view)
      open_runs(view)

      html =
        view
        |> element(~s(button[phx-value-event="signup.abandoned"]))
        |> render_click()

      assert html =~ ~s(data-run-status="running")

      assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

      assert render_until(view, ~s(data-run-status="done"))
    end

    # A link that outlived its run, or one somebody typed. The page says so
    # rather than showing an empty canvas and letting a reader guess.
    #
    # Sabotage: made `adopt/2`'s error clause answer the socket unchanged;
    # this went red, then reverted.
    test "a run id nobody stored is refused on the page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "signup_wizard", run: "no-such-run"]}")

      assert html =~ "run refused"
      assert html =~ "run_not_found"
    end

    # Stop is the host's own terminal transition, and the page stops naming
    # a run it has abandoned.
    #
    # Sabotage: made the `run-stop` handler skip its patch; the run id
    # stayed in the URL and this went red, then reverted.
    test "Stop drops the run from the page and from the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      assert_patch(view)

      html = view |> element(~s(button[phx-click="run-stop"])) |> render_click()

      refute html =~ "data-run-status"
      refute assert_patch(view) =~ "run="
    end
  end

  # Presses Run in the host header, then renders until the run has actually
  # reached the page. The press only starts the session; the effects arrive
  # as ordinary messages afterwards, so the render the click returns is the
  # one taken before the first of them was handled. Polling the render is
  # what a subscriber-driven page makes available - there is no callback to
  # await and no state to peek at from out here - and the deadline is what
  # turns a stalled run into a failure rather than a hang.
  @spec run(Phoenix.LiveViewTest.View.t()) :: String.t()
  defp run(view) do
    view |> element(~s(button[phx-click="run-start"])) |> render_click()

    render_until(view, ~s(data-run-active="true"))
  end

  # A feed row's detail cell, verbatim, so an assertion about the feed
  # cannot be satisfied by a control that happens to carry the same text.
  @spec cell(String.t()) :: String.t()
  defp cell(text), do: ~s(<td class="myapp-runs__detail">#{text}</td>)

  @spec render_until(Phoenix.LiveViewTest.View.t(), String.t(), non_neg_integer()) :: String.t()
  defp render_until(view, needle, attempts \\ 100) do
    html = render(view)

    cond do
      html =~ needle ->
        html

      attempts == 0 ->
        flunk("the page never rendered #{needle}")

      true ->
        # The pause is load-bearing, not padding: a render is a round-trip
        # through the LiveView process and costs microseconds, so a hundred
        # of them back to back all happen before the session has done any
        # work at all. What is being waited for is another process, so the
        # poll has to give it time rather than only give it turns.
        Process.sleep(10)
        render_until(view, needle, attempts - 1)
    end
  end

  # Opens the drawer and selects the host's own tab. The drawer starts
  # closed, which is why Run is in the header and not in the panel.
  @spec open_runs(Phoenix.LiveViewTest.View.t()) :: String.t()
  defp open_runs(view) do
    view |> element(".sb-drawer__strip") |> render_click()
    view |> element(~s(button[phx-value-tab="runs"])) |> render_click()
  end

  # The host's compile, run outside the page so a test can hold both numbers
  # the page has to choose between: what the compiler reported, and what the
  # package counts once its own derives are folded in. The `findings:` option
  # is the assign the component is given and nothing else, which is what makes
  # the seam's answer the drawer's answer.
  @spec counts(String.t()) :: %{raw: [Compiler.Finding.t()], seam: non_neg_integer()}
  defp counts(key) do
    {:ok, fixture} = Charts.fixture(key)
    palette = Charts.palette()

    raw =
      case Compiler.compile(fixture.document, palette,
             known_invoke_types: Charts.invoke_types(),
             declare: fixture.declare,
             terminate: true
           ) do
        {:ok, compiled} -> compiled.warnings
        {:error, findings} -> findings
      end

    {anchored, _refused} = Finding.from_compiler_all(raw)

    %{raw: raw, seam: Editor.findings_count(fixture.document, palette, findings: anchored)}
  end

  @spec card(Phoenix.LiveViewTest.View.t(), String.t(), String.t()) :: String.t()
  defp card(view, block_id, class) do
    view
    |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .#{class}))
    |> render()
  end
end
