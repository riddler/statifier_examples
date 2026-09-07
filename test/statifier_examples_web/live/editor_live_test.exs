defmodule StatifierExamplesWeb.EditorLiveTest do
  use StatifierExamplesWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Document
  alias StatifierBlocks.Editor
  alias StatifierBlocks.Finding
  alias StatifierBlocks.Shell
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable}
  alias StatifierExamples.DivergentDocument
  alias StatifierExamples.TwoStageDocument

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
    # 2026-09-06 (se-bv9): this row used to assert `seam > length(raw)` on
    # `card_processing`, and that relation is no longer producible from a
    # document this app ships. The gap came from the unregistered
    # `myapp.legacy_check` - one compiler finding, two view-model ones - and
    # registering it is what made the shipped document's later stages
    # reachable in the editor at all. Every fixture now reports the same
    # number from both sources, so what is left to assert is the one that
    # still has teeth: the header renders the seam's number, read with the
    # SAME assigns the component is passed, at a value that is not zero and
    # at zero.
    #
    # Sabotage: made verdict/2 answer a constant `0` instead of asking the
    # seam; the sketch row went red on "Findings 2". Reverted from a backup
    # copy.
    test "the header verdict is the package's findings number", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "card_processing_sketch"]}")

      %{raw: raw, seam: seam} = counts("card_processing_sketch")

      assert seam == length(raw)
      assert seam > 0
      assert html =~ "Findings #{seam}"

      assert view |> element("button[phx-click='compile']") |> render_click() =~
               "Findings #{seam}"

      {:ok, _clean, clean_html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert %{seam: 0} = counts("card_processing")
      assert clean_html =~ "Findings 0"
    end

    # se-9s2: the property the row above used to carry, given a home where it
    # can be CONSTRUCTED. The header reading the seam and the header reading
    # the compiler are two different pages, and they are only distinguishable
    # on a document where the two numbers differ - which no document this app
    # ships is, and none should be: a shipped document with a block nothing
    # resolves is a bug in the fixture, not a fixture. So the gap is built
    # here instead, by retiring a block type in a copy of the shipped
    # card-processing document, and it is built by the same mechanism the old
    # one had - the compiler stops at the resolution stage with one finding,
    # the view model derives a second for the block it cannot resolve.
    #
    # The document reaches the page the way an edit does: `:document_changed`
    # is the message the editor component sends its host, and the host's
    # `handle_info/2` clause for it is the only way a document that is not a
    # fixture's own is ever on this page. Constructing one and mounting it
    # through a query parameter is not available, and should not be - the
    # switcher lists what the app ships.
    #
    # `refute` on the compiler's number is the half with teeth: a header that
    # rendered `length(raw)` would still read a plausible non-zero count on
    # every shipped document, and this is the row that separates them. Both
    # halves are read off the header ELEMENT rather than off the page,
    # because the drawer prints the same title and a number of its own a few
    # hundred bytes later - a page-wide `=~` passes on a header that rendered
    # nothing at all.
    #
    # Sabotage: made verdict/2 answer `length(findings)` - the anchored
    # compiler findings it is handed - instead of asking the seam; this went
    # red on "Findings 2" while every other row in this file stayed green.
    # Reverted from a backup copy.
    test "the header renders the seam's number where it exceeds the compiler's",
         %{conn: conn} do
      document = DivergentDocument.document()
      fixture = DivergentDocument.fixture()

      %{raw: raw, seam: seam} = counts(document, fixture)

      assert seam > length(raw)
      assert raw != []

      assert [block] =
               Enum.filter(
                 Document.blocks(document),
                 &(&1.type == DivergentDocument.retired_type())
               )

      assert block.id == "blk_cp_legacy"

      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: fixture.key]}")

      send(view.pid, {:document_changed, document})

      verdict = view |> element(".myapp-header__verdict") |> render()

      assert verdict =~ "#{Shell.drawer_title(:findings)} #{seam}"
      refute verdict =~ "#{Shell.drawer_title(:findings)} #{length(raw)}"
    end

    # se-bv9's own criterion, read off the page the capture is taken from:
    # the type refusal the card-processing domain is authored to demonstrate
    # is one edit away on the SHIPPED document, and the editor shows it.
    # Until the type at depth 7 was registered, this document failed at the
    # resolution stage, the compiler reported that stage only, and the
    # refusal below could be asserted in the suite but never seen here.
    #
    # The edit is `myapp.receipt`'s `settlement` field pointed at the subject
    # path, which is where the intake block left a transaction: two declared
    # records that are not the same record, and neither widens into the
    # other.
    #
    # Sabotage: dropped "myapp.legacy_check" from CardAuth's @block_types;
    # the header read "Findings 1" for the unresolved type before the edit
    # and the refusal never appeared, so this went red. Reverted from a
    # backup copy.
    test "a refused read on the shipped card document lands in the pane",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert html =~ "Findings 0"

      view
      |> element(~s([data-block-id="blk_cp_receipt"] .sb-node__label))
      |> render_click()

      view
      |> element(~s(form#sb-form-blk_cp_receipt))
      |> render_change(%{
        "block-id" => "blk_cp_receipt",
        "config" => %{"settlement" => "cards.current_txn"}
      })

      html = view |> element("button[phx-click='compile']") |> render_click()

      assert html =~ "Findings 1"
      assert html =~ "Settlement"
      assert html =~ "Credit card transaction"
      assert html =~ "cards.current_txn"
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

    # se-obu, the second of the two seams the first production embedder
    # found in a day. A config error on one card used to HIDE an
    # unsatisfied read on another: Config and Structure ran in sequence, so
    # a document with both defects reported the first stage only, and an
    # author fixed one field, recompiled, and met the next refusal. The
    # package now runs the pair - a block Config refused is skipped by id
    # and the walk continues past it - and the refusal carries the union.
    #
    # This app is the reference embedder, so the property is asserted here
    # on a document made of the types it registers, through the page an
    # author reads it on rather than through the compiler alone. Both are
    # read: the compiler's own refusal says the union is what came back,
    # and the findings drawer says both rows reach the author, each
    # anchored on the field it is about - `config.retries` on the capture
    # and `config.settlement` on the receipt, which is the `config_key` the
    # `type_mismatch` finding now carries.
    #
    # Neither defect can be produced through the config form: a config the
    # form refuses is parked as a draft rather than committed, so the
    # compiler never sees it. `StatifierExamples.TwoStageDocument` is where
    # the construction and its guard live, and it reaches the page the way
    # `DivergentDocument` does - `:document_changed`, the message the
    # editor component sends its host.
    #
    # Sabotage: made `StatifierExamples.CardAuth.Capture`'s `check_retries`
    # accept any stored value; the config half went red on the drawer row
    # and on the compiler's `:config` finding, while the receipt half
    # stayed green. Reverted from a backup copy.
    test "a config error on one block does not hide a refused read on another",
         %{conn: conn} do
      fixture = TwoStageDocument.fixture()
      document = TwoStageDocument.document()

      assert {:error, findings} =
               Compiler.compile(document, Charts.palette(),
                 terminate: true,
                 datamodel: fixture.datamodel
               )

      assert [
               %Compiler.Finding{
                 stage: :config,
                 block_id: config_block,
                 config_key: "retries",
                 code: :invalid_config
               },
               %Compiler.Finding{
                 stage: :structure,
                 block_id: read_block,
                 config_key: "settlement",
                 code: :type_mismatch,
                 reason:
                   {:type_mismatch, _, "blk_cp_intake", _held, _expected, "cards.current_txn"}
               }
             ] = findings

      assert config_block == TwoStageDocument.config_block()
      assert read_block == TwoStageDocument.read_block()

      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: fixture.key]}")

      send(view.pid, {:document_changed, document})

      view |> element("button[phx-click='compile']") |> render_click()
      view |> element(".sb-drawer__strip") |> render_click()
      view |> element("#sb-drawer-tab-findings") |> render_click()

      rows = findings_rows(view)

      assert %{source: "config", anchor: "config.retries"} =
               Enum.find(rows, &(&1.block_id == config_block))

      assert %{source: "assignability", anchor: "config.settlement"} =
               Enum.find(rows, &(&1.block_id == read_block))
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

  describe "the drop a declared read refuses" do
    # se-obu, the first of the two seams the first production embedder found
    # in a day. `myapp.receipt` is this app's one type whose read is declared
    # on a CONFIG FIELD rather than on `io/1`: its `settlement` is a
    # `{:path, %{expects: "cards.settlement"}}`, so what it reads and where
    # is a function of what the author configured, and the answer changes
    # under the author's hands.
    #
    # ADR-0011 promises that read is checked at the DROP as well as at the
    # compile - a gap the write cannot satisfy is greyed before the card
    # lands in it, rather than accepting the card and reporting a finding
    # afterwards - and this is the row that says the promise reaches a host's
    # own type. It is asserted through a drag of the configured block rather
    # than through a palette insert, because a palette insert probes the
    # type's DECLARED config and this app declares no type whose declared
    # config is refused anywhere: see the note below.
    #
    # Both halves are read off the same document one edit apart, which is
    # what makes the second half evidence. Before the edit the receipt reads
    # `cards.settlement`, which the document declares AS the
    # `cards.settlement` record at that path, so the read meets exactly the
    # record it expects: every gap takes it and no slot has a data-flow
    # reason to give. After it the read is at the subject, where the
    # document declares an `object` and `myapp.intake` writes a
    # `cards.credit_txn`, and every gap is greyed and NAMES the intake.
    #
    # [2026-09-07, `se-yag` under RQ-SF036-0a and the `statifier_blocks`
    # ADR-0011 Note of the same date] The root's own body is greyed too,
    # and this row now says so. Seeding a declared path type is
    # ROOT-FORWARD: it enters at the document root and reaches every gap
    # downstream of it, the gap AHEAD of the intake included, so that gap
    # is not empty and the read there is not unknown. A bare `object` is
    # NOMINAL and covers a `cards.settlement` read no better than a
    # `cards.credit_txn` does, so the root body refuses for the same
    # reason the tail does. The existential distinction this row used to
    # draw at the root body is therefore not observable at a DECLARED
    # path any more; what it still holds is that the verdict follows the
    # author's config edit under his hands, and that every refusal names
    # the block that could fix it.
    #
    # Sabotage, both halves, 2026-09-07:
    #
    #   * changed `StatifierExamples.CardAuth.Receipt`'s `settlement` field
    #     to expect "cards.credit_txn" - the record the subject actually
    #     holds - and the BEFORE half went red, every slot refusing
    #     `not_assignable` where it had no reason to give: a declared path
    #     answers a wrong `expects` immediately rather than leaving it
    #     unknown;
    #   * dropped the `cards.current_txn` entry from
    #     `priv/fixtures/card-processing.datamodel.json` and the AFTER half
    #     went red at the root body, which came back "ok". That is the
    #     mutation that says root-forward SEEDING is what greys the gap
    #     ahead of the intake: with nothing declared at the subject the gap
    #     is genuinely empty and takes the card, exactly as it did before
    #     `statifier_blocks` 0.23.0.
    #
    # Both reverted from backup copies.
    test "a read declared on a config field greys the gaps its write refuses",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      assert view |> drag_slots("blk_cp_receipt") |> refusal_reasons() == %{}

      view
      |> element(~s([data-block-id="blk_cp_receipt"] .sb-node__label))
      |> render_click()

      view
      |> element(~s(form#sb-form-blk_cp_receipt))
      |> render_change(%{
        "block-id" => "blk_cp_receipt",
        "config" => %{"settlement" => "cards.current_txn"}
      })

      slots = drag_slots(view, "blk_cp_receipt")
      reasons = refusal_reasons(slots)

      assert reasons != %{}
      assert Enum.uniq(Map.values(reasons)) == ["fixable_by:blk_cp_intake"]
      assert reasons[{"blk_cp_tail", "body"}] == "fixable_by:blk_cp_intake"
      assert slots[{"blk_cp_tail", "body"}].drop == "no"
      assert slots[{"blk_cp_root", "body"}].drop == "no"
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

        compiles? =
          match?({:ok, _}, Durable.compile(fixture.document, fixture.declare, fixture.datamodel))

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
    # The marks are the pane's, and the pane resolves them through a chart it
    # recompiles itself - so this is as much a test of `compile_options/1`
    # and the `declare` assign as of the marks. A page that passed the
    # editor a different option list than the run executed under would
    # resolve the run's state ids against different bytes and mark nothing.
    #
    # se-dh0 retired the assertion that used to live here, that the block
    # whose call came back carries `data-invoke-outcome="done"`. That mark
    # was the host's, pushed from `Run.invoke`, which knew what this process
    # had watched happen; a run seated in the pane derives its invoke mark
    # from the trace instead, and `StatifierBlocks.Runtime.Marks.from_trace/2`
    # marks a call that is still OUT with no outcome (`{block_id, nil}`) and
    # says nothing about one that has come back. The chip is a real reading
    # to have lost, and it belongs upstream rather than back here: this app
    # would have to keep a second, live-only run beside the stored one to
    # paint it, which is exactly what this bead retired.
    # What `compile_options` actually buys, on the only run where it can be
    # seen. The Run pane resolves a run's state ids through a chart the editor
    # recompiles for itself, and this page hands it the option list the run was
    # compiled with. For a run resting mid-flight the two compiles agree about
    # every state the run is in anyway, so nothing shows; for a run that has
    # SETTLED, the configuration includes a top-level `<final>` that only
    # `terminate: true` puts in the chart at all - so a recompile without it
    # resolves the last configuration to nothing and the finished run draws no
    # marks.
    #
    # `card_processing` is the fixture because it runs to `done` on one press:
    # every call it makes is answered inside the step that made it.
    #
    # Sabotage: dropped `compile_options` from `render/1`'s component call,
    # leaving the editor to recompile without `terminate: true`; the finished
    # run's mark was gone and this went red, while every mid-flight test above
    # stayed green. Reverted from a backup copy.
    test "a settled run still marks the block it settled in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing"]}")

      view |> element(~s(button[phx-click="run-start"])) |> render_click()

      html = render_until(view, ~s(data-run-status="done"))

      assert html =~ ~s(data-run-active="true")
    end

    # Sabotage: dropped the `declare` assign from `render/1`'s component call,
    # leaving the editor to recompile the run's provenance with `declare: []`
    # while the run itself ran on the fixture's declarations. The two compiles
    # produce different bytes, the run's state ids resolved against none of
    # them, and this went red with no marks on the page at all. Reverted from
    # a backup copy.
    test "the marks are read off the replayed run, through the host's own compile options",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)

      assert view
             |> element(~s([data-block-id="blk_su_verify_wait"]))
             |> render() =~ ~s(data-run-active="true")
    end

    OLD_END

    # The run's narration is the pane's log now, not a drawer tab of this
    # app's own, and what it narrates is the STORED run rather than what this
    # process watched: the log is built by replaying the run's persisted
    # input log through statifier-ui (`StatifierExamples.Charts.Replay`).
    # The macrostep grouping is statifier-ui's, the section is
    # statifier_blocks', and neither is this app's markup any more - which is
    # the point of the bead.
    #
    # Sabotage: made `push_run/1` push `run: nil` whatever it replayed; the
    # pane vanished and this went red on the section, then reverted.
    test "the run's log is the pane's, replayed from the stored inputs", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)
      html = render(view)

      assert html =~ ~s(class="sb-run")
      assert html =~ ~s(data-run="true")
      assert html =~ "statifier-ui-macrosteps"
      assert html =~ "Macrostep 1 - initialize"
      refute html =~ "myapp-runs__detail"
    end

    OLD_END

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
      html = render(view)

      refute html =~ "error.execution"
    end

    OLD_END

    # The event affordance: one button per event the document declares, in
    # the page's own header beside Run and Stop, and pressing it steps the
    # stored run.
    #
    # They are the page's rather than the Run pane's send control, and that
    # is a fact about a durable run rather than a preference. The pane's
    # control writes into a live `Statifier.Session` server and is enabled
    # only for a run that has one (`run_session` non-nil and the run's
    # `stats` non-nil); a durable run has no session process at all, and a
    # replayed reading of one is exactly what statifier-ui's `stats: nil`
    # means. So the pane correctly reads this app's run as not sendable, and
    # the host keeps the affordance.
    #
    # The assertion is on the LOG and not on the button's own name: the
    # button carries the event name, so a page that dropped the press
    # entirely would still contain the string.
    #
    # Sabotage: made the `run-send` handler drop the press instead of
    # sending the event; the macrostep never appeared and this went red,
    # then reverted.
    test "an event button steps the run", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "signup_wizard"]}")

      run(view)

      view
      |> element(~s(button[phx-value-event="signup.email_verified"]))
      |> render_click()

      assert render_until(view, "Macrostep 4 - signup.email_verified")
    end

    OLD_END

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

      # And the whole run comes back with it, not one row saying it was
      # picked up. The feed this replaced derived its rows from the effects
      # a step returned, and effects are not stored, so a resumed run
      # opened with a single "Run resumed from storage" line; the input log
      # is the run's own history, so a resumed page opens on all of it.
      assert render_until(resumed, "Macrostep 1 - initialize")
      OLD_END
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

      resumed
      |> element(~s(button[phx-value-event="signup.abandoned"]))
      |> render_click()

      assert render_until(resumed, "signup.abandoned")
      OLD_END
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
      OLD_END

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

  describe "the drafts tray" do
    # What the uptake is FOR: the two block types statifier_blocks added in
    # sb-uag7 reach this app's editor with no wiring at all - `core: true` on
    # `Palette.from_modules/2` carries them, the package's stylesheet the app
    # already imports carries `.sb-slot--tray`, and `"inbox"` is a name the
    # host's heroicon set already resolves. This row is what says so on the
    # rendered page rather than in prose: the shelf draws as a tray, the
    # parked fragment is inside it, and the gap marker draws in the flow.
    #
    # `statifier_blocks` 0.13.0 changed what the editor shows FIRST: a
    # stocked shelf opens folded, so this document opens showing its flow
    # rather than its parked work, and the tray is not in the DOM until the
    # author opens it. That opening is asserted here rather than worked
    # around, because it is the behaviour a host embedding the editor now
    # gets; what the tray holds once opened is unchanged.
    #
    # Sabotage: retyped `blk_cps_drafts` to `core.sequence` in
    # `priv/fixtures/card_processing_sketch.json` - a real type, holding the
    # same child, in the same place - and the tray assertions went red with
    # an ordinary primary slot where the strip belongs. Reverted from a
    # backup copy. What the package draws is the package's; what this app
    # decides is that the fixture asks for it.
    #
    # Sabotage: dropped the `unfold/2` call, leaving the tray
    # assertions to run against the freshly mounted page; this went red on
    # `sb-slot--tray`, which is what says the fold is real and the unfold is
    # load-bearing rather than decoration. Reverted from a backup copy.
    test "the sketch draws its shelf as a tray with the tail parked in it",
         %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/editor?#{[doc: "card_processing_sketch"]}")

      # Opens folded: the parked work is there, and out of the way.
      refute html =~ "sb-slot--tray"

      html = unfold(view, "blk_cps_drafts")

      assert html =~ "sb-slot--tray"

      tray =
        view
        |> element(~s(.sb-slot--tray[data-parent-id="blk_cps_drafts"][data-slot-name="body"]))
        |> render()

      assert tray =~ ~s(data-slot-style="tray")
      assert tray =~ ~s(data-empty="false")
      assert tray =~ ~s(data-block-id="blk_cps_tail")
      assert tray =~ "Build the receipt"

      assert card(view, "blk_cps_gap", "sb-node__label") =~ "Placeholder"
    end

    # The publish gate, read off the page: a shelf with anything in it and a
    # placeholder each raise an author warning on a compile that SUCCEEDS
    # (sb ADR-0004 D4), so the host's own header - which counts through
    # `Editor.findings_count/3`, not through the compiler - says the document
    # is unfinished while either is there.
    #
    # Sabotage: emptied the shelf's `body` slot in
    # `priv/fixtures/card_processing_sketch.json`; the count fell to 1 and
    # this went red. Reverted from a backup copy.
    test "a parked fragment and a gap marker each show in the header count",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/editor?#{[doc: "card_processing_sketch"]}")

      %{seam: seam} = counts("card_processing_sketch")

      assert seam == 2
      assert html =~ "Findings 2"
      assert html =~ "parked work"
      assert html =~ "Authorize, then capture"
    end

    # The beat `docs/demo-script.md` section 13 walks, driven as the browser
    # drives it: the author already knows the tail, so it is parked first;
    # the sources are built afterwards; the tail is placed last. Every step
    # is one of the editor's own events, which is what makes this the beat's
    # machine-verified half rather than a paraphrase of it - the demo script
    # is read out loud, and this is read by CI.
    #
    # The document ends publishable: the tray is empty, no placeholder is
    # left, and the header falls to `Findings 0`. That is the whole argument
    # for the two types - unfinished work is *sayable* in the document, and
    # saying it is visible to a host deciding whether to publish.
    #
    # The beat opens the shelf first, because as of `statifier_blocks`
    # 0.13.0 a stocked shelf opens folded - which is the demo script's
    # order too: the author looks at the flow, then at what they parked.
    #
    # Sabotage: retyped `blk_cps_drafts` to `core.sequence` in the sketch
    # fixture, so the tail started in an ordinary slot rather than parked;
    # `tray_ids/1` found no tray and this went red before the sequence
    # began. Reverted from a backup copy.
    test "a fixture is built sink-backwards: park the tail, build the sources, place the tail",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/editor?#{[doc: "card_processing_sketch"]}")

      assert flow_ids(view) == [
               "blk_cps_intake",
               "blk_cps_reset_attempts",
               "blk_cps_gap",
               "blk_cps_drafts"
             ]

      unfold(view, "blk_cps_drafts")

      assert tray_ids(view) == ["blk_cps_tail"]

      # The sources, dragged out of the palette onto the gap the placeholder
      # is standing in. `insert-dragstart` then `insert-drop` is the palette
      # drag's two round-trips, and the index is the gap the drop landed on.
      insert(view, "myapp.authorize", 2)
      insert(view, "myapp.capture", 3)

      # The gap marker has served its purpose: what goes here is now there.
      view |> element(~s([data-block-id="blk_cps_gap"] .sb-node__remove)) |> render_click()

      # And the tail comes out of the tray into the flow it was always for.
      canvas(view) |> render_hook("dragstart", %{"block-id" => "blk_cps_tail"})

      canvas(view)
      |> render_hook("drop", %{
        "block-id" => "blk_cps_tail",
        "parent-id" => "blk_cps_root",
        "slot" => "body",
        "index" => "4"
      })

      assert tray_ids(view) == []

      assert [
               "blk_cps_intake",
               "blk_cps_reset_attempts",
               authorize,
               capture,
               "blk_cps_tail",
               "blk_cps_drafts"
             ] = flow_ids(view)

      assert authorize != capture

      html = view |> element("button[phx-click='compile']") |> render_click()

      assert html =~ "Findings 0"
      refute html =~ "parked work"
    end
  end

  # The editor's drag events are pushed by the client rather than by a
  # control with a `phx-click` on it, so a test reaches them the way the
  # package's own suite does: through the canvas, which is where the hook
  # that pushes them lives.
  @spec canvas(Phoenix.LiveViewTest.View.t()) :: Phoenix.LiveViewTest.Element.t()
  defp canvas(view), do: element(view, "#sb-canvas")

  # Unfolds a container by clicking its own fold control, the way an author
  # does. As of `statifier_blocks` 0.13.0 a NON-EMPTY drafts shelf opens
  # folded, so a tray assertion has to open the shelf first rather than
  # expect it already open; an empty shelf still opens as it was, because
  # its tray IS the drop target for the first parked fragment.
  @spec unfold(Phoenix.LiveViewTest.View.t(), String.t()) :: String.t()
  defp unfold(view, block_id) do
    view
    |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome .sb-node__fold))
    |> render_click()
  end

  # One palette drag: arm the type, then drop it on a gap in the root's body.
  @spec insert(Phoenix.LiveViewTest.View.t(), String.t(), non_neg_integer()) :: String.t()
  defp insert(view, type, index) do
    canvas(view) |> render_hook("insert-dragstart", %{"type" => type})

    canvas(view)
    |> render_hook("insert-drop", %{
      "type" => type,
      "parent-id" => "blk_cps_root",
      "slot" => "body",
      "index" => to_string(index)
    })
  end

  # Starts a drag of a block that is IN the document and reads every slot's
  # verdict off the page it re-renders. A block drag rather than a palette
  # insert is what asks the question about the block's own config: the
  # insert probe is built from the type's declared defaults and its palette
  # entry's `default_config`, so a type whose declared config names no path
  # the document refuses is accepted everywhere no matter what an author
  # later types into it.
  #
  # The key is the slot's address - its parent and its name - because that
  # is what `Edit.Targets` answers about and what the reason is anchored to.
  @spec drag_slots(Phoenix.LiveViewTest.View.t(), String.t()) ::
          %{{String.t(), String.t()} => %{drop: String.t() | nil, reason: String.t() | nil}}
  defp drag_slots(view, block_id) do
    canvas(view)
    |> render_hook("dragstart", %{"block-id" => block_id})
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".sb-slot")
    |> Enum.map(fn slot ->
      {
        {attribute(slot, "data-parent-id"), attribute(slot, "data-slot-name")},
        %{drop: attribute(slot, "data-drop"), reason: attribute(slot, "data-drop-reason")}
      }
    end)
    |> Map.new()
  end

  # The slots that refused with a DATA-FLOW reason to give, and the reason.
  # A slot that refused for an arrangement reason - an interrupt rail that
  # takes only listeners, an error slot that takes only a handler - carries
  # no reason at all, and leaving those out is what keeps the assertions
  # about the read rather than about the shape of the document.
  @spec refusal_reasons(%{{String.t(), String.t()} => map()}) ::
          %{{String.t(), String.t()} => String.t()}
  defp refusal_reasons(slots) do
    for {address, %{drop: "no", reason: reason}} <- slots, reason != nil, into: %{} do
      {address, reason}
    end
  end

  # The findings drawer's rows, as the three things each one says about
  # itself: which block it is anchored on, which field of that block, and
  # which source derived it.
  @spec findings_rows(Phoenix.LiveViewTest.View.t()) ::
          [%{block_id: String.t() | nil, anchor: String.t() | nil, source: String.t() | nil}]
  defp findings_rows(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".sb-findings__list .sb-finding")
    |> Enum.map(fn row ->
      %{
        block_id:
          row |> LazyHTML.query(".sb-findings__reveal") |> attribute("phx-value-block-id"),
        anchor: row |> LazyHTML.query(".sb-findings__anchor") |> LazyHTML.text() |> String.trim(),
        source: row |> LazyHTML.query(".sb-findings__source") |> LazyHTML.text() |> String.trim()
      }
    end)
  end

  @spec attribute(LazyHTML.t(), String.t()) :: String.t() | nil
  defp attribute(node, name), do: node |> LazyHTML.attribute(name) |> List.first()

  @flow_slot ~s(.sb-slot[data-parent-id="blk_cps_root"][data-slot-name="body"])
  @tray_slot ~s(.sb-slot--tray[data-parent-id="blk_cps_drafts"][data-slot-name="body"])

  # The block ids in the root's `body`, in document order. Read off the
  # rendered page rather than off the document, because what this file is
  # asserting about is the page.
  @spec flow_ids(Phoenix.LiveViewTest.View.t()) :: [String.t()]
  defp flow_ids(view), do: child_ids(view, @flow_slot)

  @spec tray_ids(Phoenix.LiveViewTest.View.t()) :: [String.t()]
  defp tray_ids(view), do: child_ids(view, @tray_slot)

  # The ids of a slot's OWN children: a child combinator rather than a
  # descendant search, so a card nested inside one of them - the receipt
  # step inside the parked tail, say - is not counted as a sibling of it.
  @spec child_ids(Phoenix.LiveViewTest.View.t(), String.t()) :: [String.t()]
  defp child_ids(view, slot_selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#{slot_selector} > .sb-node")
    |> LazyHTML.attribute("data-block-id")
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

  # The host's compile, run outside the page so a test can hold both numbers
  # the page has to choose between: what the compiler reported, and what the
  # package counts once its own derives are folded in. The `findings:` option
  # is the assign the component is given and nothing else, which is what makes
  # the seam's answer the drawer's answer.
  @spec counts(String.t()) :: %{raw: [Compiler.Finding.t()], seam: non_neg_integer()}
  defp counts(key) do
    {:ok, fixture} = Charts.fixture(key)

    counts(fixture.document, fixture)
  end

  # The document and the environment separately, because the page holds them
  # separately: an edit replaces the document while the fixture's `declare`
  # and `datamodel` stay where they were, and a document that is not the
  # fixture's own is exactly what the divergence row needs measured.
  @spec counts(Document.t(), Charts.Fixture.t()) :: %{
          raw: [Compiler.Finding.t()],
          seam: non_neg_integer()
        }
  defp counts(%Document{} = document, fixture) do
    palette = Charts.palette()

    raw =
      case Compiler.compile(document, palette,
             known_invoke_types: Charts.invoke_types(),
             declare: fixture.declare,
             datamodel: fixture.datamodel,
             terminate: true
           ) do
        {:ok, compiled} -> compiled.warnings
        {:error, findings} -> findings
      end

    {anchored, _refused} = Finding.from_compiler_all(raw)

    %{
      raw: raw,
      seam:
        Editor.findings_count(document, palette,
          findings: anchored,
          datamodel: fixture.datamodel
        )
    }
  end

  @spec card(Phoenix.LiveViewTest.View.t(), String.t(), String.t()) :: String.t()
  defp card(view, block_id, class) do
    view
    |> element(~s([data-block-id="#{block_id}"] > .sb-node__chrome > .#{class}))
    |> render()
  end
end
