defmodule StatifierExamplesWeb.PlanLiveTest do
  # Not async: this file drives pages that write `StatifierExamples.Documents`,
  # which is one named Agent shared process-wide, and `ConnCase` resets that
  # store in `setup` - two async cases clear it under each other mid-test.
  use StatifierExamplesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Block
  alias StatifierBlocks.Composite
  alias StatifierBlocks.Document
  alias StatifierBlocks.Map, as: BlockMap
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.CardAuth.AuthorizeWithDeadline
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Messaging.Notify
  alias StatifierExamples.Documents
  alias StatifierExamples.Signup.{GuardedSection, GuardedStep}
  alias StatifierExamplesWeb.EventPhrasing

  @themes ["light", "dark", "brand"]

  # The document the config tests edit, and the block on it they edit: a
  # `myapp.notify` whose `label` is what the card is titled by, so a change
  # made here is visible on the other view without either page being asked
  # what it stored.
  @doc_key "signup_onboarding"
  @block_id "blk_so_welcome"
  @block_label "Welcome them to the new workspace"

  # The document the structural tests move blocks around in, and the block
  # whose gap they insert into. It is a different fixture because this one
  # has a root body with several children in it, which is what makes "one
  # place up" a question with an answer.
  @plan_doc "card_processing"
  @plan_block "blk_cp_intake"
  @plan_slot "body"

  # The same fixture's authorization group, and the block sitting at the head
  # of its body. The gap under that block is inside a `core.group`, which is
  # what the core `"deadline"` recipe's landing rule asks for; the gap under
  # `@plan_block` is inside the root `core.sequence`, which is what it
  # refuses. Two positions in one document, so the picker's recipe filter can
  # be read as a filter rather than as an on/off switch.
  @plan_group "blk_cp_authz"
  @group_member "blk_cp_authz_deadline"

  # The three composites this app ships, as `{fixture key, block id, module,
  # sentence}`. Each is read on a fixture of its own that holds its root, the
  # composite and nothing else the author did not put inside the composite -
  # so "one row for the composite, and one for each block the author placed"
  # is a question the row COUNT can answer. The module is carried so a case
  # can ask the declaration what its params and its slots are rather than
  # transcribe them.
  @composites [
    {"card_processing_composite", "blk_cpx_authz", AuthorizeWithDeadline,
     "Authorize within 1h, else abandon"},
    {"signup_guarded_step", "blk_gs_step", GuardedStep, "Run myapp:provision, notify on failure"},
    {"signup_guarded_section", "blk_gx_section", GuardedSection,
     "Run myapp:provision, notify on failure, then continue"}
  ]

  describe "the outline as rows" do
    # The bead's first criterion, asked of every fixture rather than of a
    # representative one: `outline/1` is a walk over whatever tree it is
    # given, so a document whose shape no other fixture has is exactly the
    # one a single-fixture test misses.
    #
    # The expectation is built with the same public walk the page renders
    # from, which is deliberate. What is asserted is that the PAGE shows
    # every entry the walk hands over - not that the walk is correct, which
    # is `statifier_blocks`' own test's job.
    #
    # Sabotage: hid the rails section in render/1; three tests went red on
    # the missing block ids and the row count, then reverted.
    test "every fixture renders one row per outline entry, each with a sentence", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: fixture.key]}")

        outline = outline_of(fixture)

        refute Enum.empty?(outline)
        assert rows_in(html) == length(outline)

        for {node, depth, kind} <- outline do
          assert html =~ ~s(data-block-id="#{node.block_id}")
          assert html =~ ~s(data-depth="#{depth}")
          assert html =~ ~s(data-kind="#{kind}")
          assert html =~ escaped(sentence_of(node))
        end
      end
    end

    # `kind` is a partition, so the three sections between them hold every
    # row and no row twice. The page is what has to keep that true: a rail
    # drawn in the plan and in its own section is one block a reader counts
    # as two.
    #
    # Sabotage: widened the plan section's filter to `kind != :tray`, so the
    # rails were drawn twice; three tests went red on the section row
    # counts, then reverted.
    test "rails fold into one section and trays into the footer", %{conn: conn} do
      for fixture <- Charts.fixtures() do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: fixture.key]}")

        by_kind = fixture |> outline_of() |> Enum.frequencies_by(fn {_n, _d, k} -> k end)
        plan = Map.get(by_kind, :step, 0) + Map.get(by_kind, :arm, 0)

        assert rows_in(section(html, "plan")) == plan
        assert rows_in(section(html, "rails")) == Map.get(by_kind, :rail, 0)
        assert rows_in(section(html, "trays")) == Map.get(by_kind, :tray, 0)

        if Map.get(by_kind, :rail, 0) > 0 do
          assert html =~ "If something goes wrong"
        end
      end
    end

    # The three parameters this page reads, each falling back rather than
    # refusing - the reason `StatifierExamplesWeb.EditorLive` gives, applied
    # to the second page that reads the same query string.
    #
    # Sabotage: pointed `@default_theme` at `:brand`; the unknown-theme row
    # went red, then reverted.
    test "the URL contract matches the editor's, plus readonly", %{conn: conn} do
      for theme <- @themes do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: @doc_key, theme: theme]}")
        assert html =~ ~s(data-theme="#{theme}")
      end

      {:ok, _view, unknown_doc} = live(conn, ~p"/plan?#{[doc: "no_such_document"]}")
      assert unknown_doc =~ hd(Charts.fixtures()).name

      {:ok, _view, unknown_theme} = live(conn, ~p"/plan?#{[theme: "chartreuse"]}")
      assert unknown_theme =~ ~s(data-theme="light")

      {:ok, _view, bare} = live(conn, ~p"/plan")
      assert bare =~ hd(Charts.fixtures()).name
    end

    # The link the "one document, two views" claim rests on. It carries the
    # key, so what opens there is what is being read here.
    #
    # Sabotage: pointed editor_path/2 at the plan route; this went red, then
    # reverted.
    test "Open in editor links to the same document", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: @doc_key, theme: "dark"]}")

      assert view
             |> element("a", "Open in editor")
             |> render() =~ "/editor?doc=#{@doc_key}&amp;theme=dark"
    end
  end

  describe "editing" do
    # The bead's second criterion, and the one the design gap was about:
    # `:documents` used to be a per-socket assign, so an edit made here was
    # invisible to a separately mounted `/editor`. It goes through
    # `StatifierExamples.Documents` now, and this is what says so - end to
    # end, through two LiveView mounts rather than through the store.
    #
    # Sabotage: took the `Documents.put/2` call out of `store/1`; this and
    # the round-trip test went red, then reverted.
    test "a field edited in Plan is what /editor opens on", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @doc_key]}")

      select(plan, @block_id)

      plan
      |> element("#sb-form-#{@block_id}")
      |> render_change(%{"config" => %{"label" => "Say hello to the new workspace"}})

      assert render(plan) =~ "Say hello to the new workspace"

      {:ok, _editor, editor_html} = live(conn, ~p"/editor?#{[doc: @doc_key]}")

      assert editor_html =~ "Say hello to the new workspace"
      refute editor_html =~ @block_label
    end

    # Insert, move, delete and undo, each asserted against the stored
    # document rather than against the markup: what a command has to do is
    # change the document, and a row that moved on screen without the
    # document moving is the bug this catches.
    #
    # Sabotage: made the "move" handler target `index` rather than
    # `index + step`; the reorder assertion went red, then reverted.
    test "insert, move, delete and undo each round-trip", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @plan_doc]}")

      before = body_ids()
      assert @plan_block in before

      # Insert: arm the gap under the block, then pick a type off the list
      # the package's own drop check said fits there.
      plan
      |> element(~s(li[data-block-id="#{@plan_block}"] button.myapp-plan__add))
      |> render_click()

      plan
      |> element(
        ~s(li[data-block-id="#{@plan_block}"] [data-plan-picker="open"] button),
        "Intake"
      )
      |> render_click()

      inserted = body_ids()
      assert length(inserted) == length(before) + 1

      new_id = Enum.find(inserted, &(&1 not in before))
      assert index_of(inserted, new_id) == index_of(before, @plan_block) + 1

      # Move: one place up puts it where the block it followed was.
      move(plan, new_id, "up")
      assert index_of(body_ids(), new_id) == index_of(before, @plan_block)

      # Delete, and then step back and forward over it.
      plan
      |> element(~s(li[data-block-id="#{new_id}"] button), "Delete")
      |> render_click()

      assert body_ids() == before

      plan |> element("button", "Undo") |> render_click()
      assert new_id in body_ids()

      plan |> element("button", "Redo") |> render_click()
      assert body_ids() == before
    end

    # The root is a row like any other, and every command it could be given
    # is refused. Which is the point of the assertion: this page routes each
    # gesture through `Edit.History.commit/4` rather than around it, so the
    # package's refusals are the page's refusals - and the reader is told,
    # rather than pressing a button that silently does nothing.
    #
    # Sabotage: dropped `error_sentence/1`'s `:cannot_remove_root` clause so
    # the generic sentence answered instead; the sentence assertion went red,
    # then reverted.
    test "the root is refused, and the refusal is on the page", %{conn: conn} do
      {:ok, plan, html} = live(conn, ~p"/plan?#{[doc: @plan_doc]}")

      root = document(@plan_doc).root.id
      assert html =~ ~s(data-block-id="#{root}")

      before = document(@plan_doc)

      move(plan, root, "down")
      assert document(@plan_doc) == before

      assert render_hook(plan, "remove", %{"block-id" => root}) =~
               "The root block cannot be deleted."

      assert document(@plan_doc) == before
    end

    # A refused value is the author's bytes, not an error: the document keeps
    # what it had, the form keeps what was typed, and Discard is the way out.
    #
    # Sabotage: made change_config/3's refusal branch assign a document
    # instead of holding the draft; the pending-note assertion went red,
    # then reverted.
    test "a refused value is held as a draft", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @doc_key]}")

      select(plan, @block_id)

      html =
        plan
        |> element("#sb-form-#{@block_id}")
        |> render_change(%{"config" => %{"invoke_type" => ""}})

      assert html =~ "Nothing is stored yet"
      assert config_of(@doc_key, @block_id)["invoke_type"] != ""

      assert plan
             |> element("#plan-panel button", "Discard edits")
             |> render_click() =~ @block_label

      refute render(plan) =~ "Nothing is stored yet"
    end

    # `se-f4a`, folded into `se-avi`, and re-pointed by `se-6jn`. The page
    # used to say a refusal happened and stop there; then it derived the
    # draft's own findings by re-running `validate_config/1` over the
    # draft, because `Edit.Session.change_config/3` discarded the findings
    # its own `{:invalid_config, id, findings}` refusal carried.
    #
    # `sb-8fa8` closed that: the refusal's findings are kept in the
    # session's `draft_findings` under the block's id and
    # `ViewModel.overlay_findings/2` routes them onto the form. The page's
    # `route_findings/3` and `draft_findings/3` are gone with it, and what
    # this case now pins is that the findings on screen are the ones the
    # funnel stated rather than a second derivation of them.
    #
    # Both halves of the expectation are still asked of the declaration
    # rather than written down: the label off `config_schema/1` and the
    # message off `validate_config/1`, so a type that rewords either is a
    # change this case follows instead of one it goes red on for the wrong
    # reason. `validate_config/1` is called by the TEST to state the
    # expectation; the page no longer calls it at all.
    #
    # Sabotage: replaced `Map.get(findings, node.block_id, [])` in
    # `overlay_draft/3` with `[]`, so the refusal's findings never reached
    # the form; this went red on the pending sentence, which is built from
    # the fields the findings landed on, and no other case in the file
    # moved. Reverted from a copy.
    test "a refused draft names the field it is about", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @doc_key]}")

      select(plan, @block_id)

      label =
        Notify.config_schema(%{})
        |> Enum.find(&(&1.key == "template"))
        |> Map.fetch!(:label)

      {:error, findings} =
        @doc_key
        |> config_of(@block_id)
        |> Map.put("template", "")
        |> Notify.validate_config()

      {"template", message} = Enum.find(findings, &(elem(&1, 0) == "template"))

      html =
        plan
        |> element("#sb-form-#{@block_id}")
        |> render_change(%{"config" => %{"template" => ""}})

      # The sentence names the field, and the finding is drawn under it.
      assert html =~ "Nothing is stored yet: #{label}"
      assert html =~ escaped(message)

      # One field is named, not every field: the routing is by key.
      assert occurrences(html, "Nothing is stored yet: #{label}.") == 1

      # And the draft is still a draft - the document kept what it had.
      assert config_of(@doc_key, @block_id)["template"] != ""

      # Discarding takes the finding away with the bytes.
      refute plan
             |> element("#plan-panel button", "Discard edits")
             |> render_click() =~ escaped(message)
    end
  end

  describe "a composite as a row" do
    # The no-slot ruling (2026-09-07) at the page: a composite exposes no
    # slot, so it is ONE row - the declaration's sentence with this block's
    # params in it - and the arrangement `subtree/1` describes is drawn
    # nowhere. The expanded ids are asked of `Composite.expand/2` rather than
    # written down, so an expansion that reshaped is still refuted by the same
    # case.
    #
    # This goes through the page rather than only through
    # `StatifierExamples.ViewModelPinTest` because the row is what an author
    # reads: a composite the walk answers as one node and the page draws as
    # two is a defect the view model's own test cannot see.
    #
    # Sabotage: dropped `sentence/1`'s binary clause in `plan_live.ex`, so
    # every row fell through to `ViewModel.title/1`; this went red on the
    # composite's line and took the all-fixtures case above with it, then
    # was reverted from a copy.
    test "each composite is one row carrying its own sentence", %{conn: conn} do
      for {key, block_id, module, sentence} <- @composites do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")

        authored = authored_children(key, block_id, module)

        assert rows_in(html) == 2 + length(authored),
               "#{key}: the root, the composite and the author's own blocks are the rows"

        assert occurrences(html, ~s(data-block-id="#{block_id}")) == 1
        assert html =~ escaped(sentence)

        {:ok, {members, _params}} = Composite.expand(block_in(key, block_id), module)

        # `expand/2` answers the SPLICED tree, so the author's own children are
        # in it - and they are the one thing in it the page is right to draw.
        for %Block{id: expanded} <- Composite.flatten(members), expanded not in authored do
          refute html =~ ~s(data-block-id="#{expanded}"),
                 "#{key}: #{expanded} is an expanded block and was drawn"
        end
      end
    end

    # The pass-through ruling (2026-09-07) at the page, and the half the count
    # above cannot see: a composite that declares a pass-through slot draws as
    # ONE row with the author's blocks as rows BENEATH it - one `data-depth`
    # deeper - rather than as siblings, and the block the author placed
    # carries its own id and its own sentence exactly as it would have
    # anywhere else in the document.
    #
    # This goes through the page rather than only through
    # `StatifierExamples.ViewModelPinTest` for the reason the case above gives:
    # the row is what an author reads.
    #
    # Sabotage: dropped `:slots` from `GuardedSection`'s `use`, which is a
    # composite that carries the author's blocks nowhere; the child row went
    # away and this went red, one of thirteen cases across this file,
    # `StatifierExamples.CompositesTest` and
    # `StatifierExamples.ViewModelPinTest`. Reverted from a copy.
    test "the pass-through composite's children are rows beneath it", %{conn: conn} do
      key = "signup_guarded_section"
      block_id = "blk_gx_section"
      child = "blk_gx_confirm"

      {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")

      assert authored_children(key, block_id, GuardedSection) == [child]

      composite = row(html, block_id)
      child_row = row(html, child)

      assert composite =~ ~s(data-depth="1")
      assert child_row =~ ~s(data-depth="2")

      assert html =~ escaped("Run myapp:provision, notify on failure, then continue")
      assert html =~ escaped("Notify")

      # The composite is still one row: the interior is where the child is
      # drawn, not a second card for the composite.
      assert occurrences(html, ~s(data-block-id="#{block_id}")) == 1
      assert occurrences(html, ~s(data-block-id="#{child}")) == 1
    end

    # What the row opens onto. `shown_fields/1` is the filter and the
    # composite's `config_schema/1` is its params, so the form under a
    # selected composite carries one field per param that is not `hidden?`,
    # in declaration order.
    #
    # Neither shipped composite declares a hidden param today, so the
    # expectation is computed from the declaration rather than written down:
    # a param that GAINS `hidden?` later is then a change this case follows
    # instead of one it goes red on for the wrong reason.
    #
    # Sabotage: pointed `shown_fields/1` at `& &1.required?` instead of
    # `& &1.hidden?`, so the required params came off the surface; this went
    # red naming `card_processing_composite`, and nothing else in the file
    # did - the plan page's field surface was untested before this case.
    # Reverted from a copy.
    #
    # A second sabotage is worth recording because it did NOT go red: marking
    # `outcome` hidden AND dropping `shown_fields/1`'s reject left this green,
    # because `Field.field/1` renders nothing for a hidden field on its own.
    # The two filters are redundant by design (`plan_live.ex` says so at
    # `shown_fields/1`), so what this case pins is the SURFACE - which is the
    # claim the bead makes - and not which of the two produced it.
    test "a selected composite's fields are its params minus the hidden ones", %{conn: conn} do
      for {key, block_id, module, _sentence} <- @composites do
        {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: key]}")

        shown =
          module.config_schema(%{})
          |> Enum.reject(&Map.get(&1, :hidden?, false))
          |> Enum.map(& &1.key)

        refute Enum.empty?(shown)

        assert plan |> select(block_id) |> field_keys() == shown,
               "#{key}: the form under the composite row is not its params"
      end
    end

    # `se-7p1`: the surface those fields sit on is the PACKAGE's form, not a
    # pair of host templates around `Field.field/1`. `sb-ykkl` promoted
    # `Editor.ConfigForm.config_form/1` to a call a host composes, and this
    # is what says the page composes it - the form the package draws, under
    # this page's own row, posting this page's own event and carrying the
    # hidden `block-id` this page reads back out of its params.
    #
    # Both mounts are asserted, because the pair that went was two
    # templates: the editable `<form>` and the read-only `<div>` of raised
    # fields. `read_only={@readonly?}` is the one attr that now chooses
    # between them, so a case that read only one of the two would not notice
    # the attr being dropped.
    #
    # The two composite fixtures are the rows asked, for the reason the case
    # above asks them: they are the rows whose form is guaranteed to have
    # fields on it.
    #
    # Sabotage: dropped `read_only={@readonly?}` from the `config_form/1`
    # call, so the read-only mount drew the editable form; the read-only half
    # of this case went red naming `card_processing_composite`, and the two
    # read-only cases below went red with it, while every write-guard case
    # stayed green - which is the point, a rendering is not the write gate.
    # Reverted from a copy.
    test "a selected composite's field surface is the package's own form", %{conn: conn} do
      for {key, block_id, _module, _sentence} <- @composites do
        {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: key]}")

        editable = plan |> select(block_id) |> section("panel")

        assert editable =~ ~s(id="sb-form-#{block_id}"),
               "#{key}: the panel's form is not the package's"

        assert editable =~ ~s(class="sb-form myapp-plan__fields")
        assert editable =~ ~s(phx-change="config-change")
        assert editable =~ ~s(name="block-id" value="#{block_id}")
        refute editable =~ "plan-form-#{block_id}"

        {:ok, readonly, _html} = live(conn, ~p"/plan?#{[doc: key, readonly: "1"]}")

        read = readonly |> select(block_id) |> section("panel")

        assert read =~ ~s(class="sb-form sb-form--readonly"),
               "#{key}: the read-only panel is not the package's read-only form"

        assert read =~ ~s(data-read-only="true")
        refute read =~ ~s(id="sb-form-#{block_id}")
        refute read =~ "phx-change="
      end
    end
  end

  describe "the field surface of a selected row" do
    # The case above asked "fields == the declaration's params minus the
    # hidden ones" of the two composites. `se-0u1` asks it of every row of
    # every fixture, for the reason the outline case is asked of every
    # fixture: the claim is about the PAGE's form, and a form is built the
    # same way for a `core.branch` with arms in it as it is for a composite
    # with eight params. A two-fixture case reads as a claim about
    # composites; this one is the claim the page actually makes.
    #
    # The expectation comes from `ViewModel.shown_fields/1` on the same node
    # the page renders, so what is asserted is that the page put on the
    # surface exactly what the view model handed it - in order, and nothing
    # else. What `shown_fields/1` itself decides is `statifier_blocks`'
    # test's business.
    #
    # One LiveView per fixture rather than one per row: `select-row` toggles
    # only when the SAME row is clicked twice, so clicking each row in turn
    # walks the document without a reload.
    #
    # Sabotage: pointed the row template's `:for` at `@node.form.fields`
    # instead of `ViewModel.shown_fields(@node)`; this stayed green, because
    # `Field.field/1` draws nothing for a hidden field on its own and no
    # shipped type declares one - the same redundancy the composite case
    # above records. Reverted from a copy. A discriminating sabotage:
    # dropped the `<Field.field>` line from the non-readonly form, which
    # went red on the first fixture with a selected row that has fields, and
    # was reverted from a copy.
    test "every fixture's every row shows exactly its shown fields", %{conn: conn} do
      surfaces =
        for fixture <- Charts.fixtures() do
          {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: fixture.key]}")

          view_model = ViewModel.build(fixture.document, Charts.palette(), [])

          checked =
            for {node, _depth, _kind} <- ViewModel.outline(view_model) do
              expected = view_model |> ViewModel.find_node(node.block_id) |> shown_keys()
              html = select(plan, node.block_id)

              assert field_keys(html) == expected,
                     "#{fixture.key}/#{node.block_id}: the form is not this node's shown fields"

              length(expected)
            end

          refute Enum.empty?(checked), "#{fixture.key}: no row was checked"

          {fixture.key, Enum.sum(checked)}
        end

      # A page that drew no field anywhere would satisfy every assertion
      # above, so the walk says how much surface it actually read - and the
      # two composite fixtures are named, because their rows are the ones
      # the narrower case already covered.
      assert Enum.sum(Enum.map(surfaces, fn {_key, fields} -> fields end)) > 50

      for {key, _block_id, module, _sentence} <- @composites do
        params = module.config_schema(%{}) |> Enum.reject(&Map.get(&1, :hidden?, false))
        assert {^key, count} = Enum.find(surfaces, fn {k, _} -> k == key end)
        assert count >= length(params)
      end
    end
  end

  describe "read-only" do
    # `?readonly=1` renders values and no controls. Every gesture is checked
    # rather than one representative: what makes a read-only page read-only
    # is that none of them is there.
    #
    # Sabotage: dropped the `not @readonly?` guard from the row's control
    # group; the `refute` on `phx-click="move"` went red, then reverted.
    test "renders values and no control", %{conn: conn} do
      {:ok, plan, html} = live(conn, ~p"/plan?#{[doc: @doc_key, readonly: "1"]}")

      assert html =~ ~s(data-readonly="true")
      refute html =~ ~s(phx-click="move")
      refute html =~ ~s(phx-click="remove")
      refute html =~ ~s(phx-click="insert-open")
      refute html =~ "myapp-plan__add"
      refute html =~ ">Undo<"
      refute html =~ ">Redo<"

      # The rows are still the rows: read-only is the same view with the
      # gestures gone, not a different one.
      assert rows_in(html) == length(outline_of(fixture(@doc_key)))

      selected = select(plan, @block_id)

      assert selected =~ ~s(data-field-readonly="true")
      assert selected =~ @block_label
      refute selected =~ ~s(id="sb-form-#{@block_id}")
      assert selected =~ ~s(data-read-only="true")
    end

    # The controls are gone from the markup, so the only thing that could
    # send one is a crafted payload. It changes nothing.
    #
    # Sabotage: removed the read-only `handle_event/3` clause; the stored
    # document moved under the hook and this went red, then reverted.
    test "a write event on a read-only page changes nothing", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @doc_key, readonly: "1"]}")

      before = document(@doc_key)

      render_hook(plan, "remove", %{"block-id" => @block_id})
      render_hook(plan, "move", %{"block-id" => @block_id, "dir" => "up"})

      assert document(@doc_key) == before
    end

    # `se-4v1`, folded into `se-avi`, and answered the other way round from
    # how it was filed. The bead asked for the host's `handle_event/3`
    # catch-all to be deleted once `statifier_blocks` had its own
    # `read_only?` profile. It is not deleted, because the profile is an
    # assign on the `StatifierBlocks.Editor` live component and this page
    # mounts no editor, and because the package's own `docs/profiles.md`
    # says `read_only?` "is not an authorization boundary... If you must
    # prevent a write, enforce that where you handle the write, not by
    # trusting a rendering."
    #
    # So the two halves are separate here, and this pins both: the package
    # owns the RENDERING (a field drawn as a value, `readonly?` raised),
    # and this page owns the GATE. Every event the guard names is sent, and
    # a `config-change` that the editable page in `describe "editing"`
    # above commits is the one that proves the gate is what refused it.
    #
    # Sabotage: removed the `readonly?: true` catch-all clause; the
    # config-change assertion went red on the stored config, which the
    # existing crafted-payload case above did not catch. Reverted from a
    # copy.
    test "the package draws the value and this page keeps the write gate", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @doc_key, readonly: "1"]}")

      # The package's read-only rendering, per field.
      assert select(plan, @block_id) =~ ~s(data-field-readonly="true")

      before = document(@doc_key)

      for {event, params} <- [
            {"config-change",
             %{"block-id" => @block_id, "config" => %{"label" => "A crafted write"}}},
            {"discard-draft", %{"block-id" => @block_id}},
            {"field-list-add", %{"key" => "template"}},
            {"field-list-remove", %{"key" => "template", "index" => "0"}},
            {"insert-open", %{"block-id" => @block_id}},
            {"insert-close", %{}},
            {"insert", %{"block-id" => @block_id, "type" => "myapp.notify"}},
            {"move", %{"block-id" => @block_id, "dir" => "down"}},
            {"remove", %{"block-id" => @block_id}},
            {"undo", %{}},
            {"redo", %{}}
          ] do
        render_hook(plan, event, params)
        assert document(@doc_key) == before, "#{event} reached the document"
      end

      refute render(plan) =~ "A crafted write"
    end
  end

  describe "the picker's recipe rows" do
    # `se-ezz`. A palette has two namespaces and this picker used to draw one
    # of them, on the grounds that inserting a recipe is more than one
    # command. It is, and the extra command is the package's to compose.
    #
    # What decides whether a RECIPE belongs at a gap is not a set of type
    # names - a recipe is not a block type, so no such set answers for it.
    # The package asks it with its own function, `Targets.accepted_recipes/4`,
    # over the full `{parent_id, slot, index}` position rather than the
    # `{parent_id, slot}` pair the type filter takes.
    #
    # The core `"deadline"` recipe is the subject because its landing rule is
    # a real one and this fixture puts both sides of it in reach: the pair
    # only means anything on a block carrying an `interrupts` rail, so it
    # lands in the authorization group's body and is refused in the root
    # sequence's. That both answers come off one document in one case is what
    # makes this a filter rather than a blanket.
    #
    # Sabotage: made `insertable/2` keep the old `entry.kind == :type` test;
    # this case went red on the group's gap having no "Deadline" row, and the
    # next one went red with no row to click, while every type assertion held.
    # Reverted from a copy.
    test "a recipe is offered where it lands and left out where it is not", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @plan_doc]}")

      # Inside the group: the recipe row is drawn beside the type rows.
      open_picker(plan, @group_member)
      assert has_element?(plan, picker_button(@group_member), "Deadline")
      assert has_element?(plan, picker_button(@group_member), "Notify")

      # In the root's body, over the same palette and the same document: the
      # type rows are still there and the recipe row is gone.
      open_picker(plan, @plan_block)
      refute has_element?(plan, picker_button(@plan_block), "Deadline")
      assert has_element?(plan, picker_button(@plan_block), "Notify")
    end

    # Choosing the row commits the arrangement rather than a block:
    # `{:compound, commands}` through the same funnel a type row's
    # `{:insert, ...}` goes through, so both halves land and the history
    # holds one entry for them.
    #
    # The halves are asserted where the recipe says it writes them - the send
    # at the head of the group's body, the handler at the end of that group's
    # interrupts rail, both naming one event - because "the document holds
    # the inserted blocks" is a claim about placement, and a compound that
    # wrote them anywhere would still have written two blocks.
    #
    # Sabotage: made the recipe clause commit `hd(commands)` instead of the
    # compound; the rail assertion went red on a rail that had not grown.
    # Reverted from a copy.
    test "choosing a recipe row commits the compound", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @plan_doc]}")

      before_body = slot_ids(@plan_group, "body")
      before_rail = slot_ids(@plan_group, "interrupts")

      open_picker(plan, @group_member)

      plan
      |> element(picker_button(@group_member), "Deadline")
      |> render_click()

      body = blocks_in(@plan_group, "body")
      rail = blocks_in(@plan_group, "interrupts")

      assert length(body) == length(before_body) + 1
      assert length(rail) == length(before_rail) + 1

      timer = hd(body)
      handler = List.last(rail)

      assert timer.type == "core.send"
      assert handler.type == "core.on_event"
      assert timer.config["event"] == handler.config["event"]
      assert timer.config["delay"] not in [nil, ""]

      # One gesture, one history entry: Undo takes the whole arrangement out.
      plan |> element("button", "Undo") |> render_click()

      assert slot_ids(@plan_group, "body") == before_body
      assert slot_ids(@plan_group, "interrupts") == before_rail
    end

    # The picker paints the package's filter and the write re-runs it, so a
    # crafted payload naming a recipe that does not land here is refused by
    # the same function that kept the row off the list - not by a second
    # landing rule written on this page.
    test "a crafted recipe payload is refused where the recipe does not land", %{conn: conn} do
      {:ok, plan, _html} = live(conn, ~p"/plan?#{[doc: @plan_doc]}")

      before = document(@plan_doc)

      # The right recipe at the wrong position.
      render_hook(plan, "insert", %{
        "block-id" => @plan_block,
        "kind" => "recipe",
        "type" => "deadline"
      })

      assert document(@plan_doc) == before

      # A recipe name the palette does not carry, at the position that would
      # have taken the one it does.
      render_hook(plan, "insert", %{
        "block-id" => @group_member,
        "kind" => "recipe",
        "type" => "no.such.recipe"
      })

      assert document(@plan_doc) == before
    end
  end

  describe "the transparent-container readers" do
    # `se-6jn`. `sb-6xkf` promoted the three readers a host that FLATTENS
    # containers out of its own outline needs - `ViewModel.transparent?/2`,
    # `effective_parent/3` and `end_of_list_target/3`, over a caller's own
    # list of transparent type names with `ViewModel.core_containers/0` as
    # the documented default.
    #
    # This page flattens nothing. Every block the walk hands over is drawn,
    # indented by its own depth, and where the "+" under a row inserts is
    # the next place in the row's OWN slot - `gap_target/2`, built on the
    # `ViewModel.positions/1` map. So the honest answer to "does this page
    # adopt the readers" is no, and the honest measurement is that not one
    # line was deleted for them.
    #
    # What is worth pinning is the AGREEMENT, which is the reason the
    # readers were promoted in the first place: with the caller's list
    # EMPTY - this page's list, since it draws through nothing - the
    # package's reader gives the same answer this page's own map does, for
    # every block of every fixture and for a row nested inside a
    # `core.group`, which no fixture has. If the two ever disagree, one of
    # the two views of this document is wrong about where a row sits.
    #
    # The `core_containers/0` half is asserted too, and asserted to be
    # DIFFERENT: it is what this page would get if it adopted flattening,
    # so a later pass that adopts it is a deliberate change to this case
    # rather than a silent one.
    #
    # Sabotage: the code under test is the DEPENDENCY's, so the mutation
    # was too - dropped the `transparent?(parent, types)` half of
    # `effective_parent/3`'s climb guard in `deps/statifier_blocks`, making
    # it climb past every ancestor whatever the caller's list said. Both
    # cases below went red, the first naming `blk_cp_three_ds_group` in
    # `card_processing`. Reverted from a copy, with
    # `MIX_ENV=test mix deps.compile statifier_blocks --force` run either
    # side of the revert - a stale test build reads as a false green.
    test "agree with the positions map this page's gap target reads" do
      for fixture <- Charts.fixtures() do
        vm = ViewModel.build(fixture.document, Charts.palette(), [])
        positions = ViewModel.positions(vm)

        refute Enum.empty?(positions)

        for {id, position} <- positions do
          assert ViewModel.effective_parent(vm, id, []) == position,
                 "#{fixture.key}: the package reader and this page's map disagree about #{id}"
        end
      end
    end

    test "climb past a group only when the caller asks them to" do
      wait_a = Block.new("core.wait", id: "wait_a", config: %{"duration" => "30s"})
      wait_b = Block.new("core.wait", id: "wait_b", config: %{"duration" => "1s"})
      group = Block.new("core.group", id: "grp", slots: %{"body" => [wait_a, wait_b]})

      vm =
        "core.sequence"
        |> Block.new(id: "root", slots: %{"body" => [group]})
        |> Document.new()
        |> ViewModel.build(Charts.palette(), [])

      positions = ViewModel.positions(vm)

      # This page's list is empty, and on it the reader is the map.
      assert positions["wait_b"] == {"grp", "body", 1}
      assert ViewModel.effective_parent(vm, "wait_b", []) == {"grp", "body", 1}

      # `gap_target/2` is "the next place in the row's own slot", and for
      # the last row of a slot that is the end of the list - which is the
      # other reader, on the same empty list.
      assert ViewModel.end_of_list_target(vm, "wait_b", []) == {"grp", "body", 2}

      # And what the page does NOT do: draw the group through.
      assert ViewModel.transparent?(ViewModel.find_node(vm, "grp"), ViewModel.core_containers())

      assert ViewModel.effective_parent(vm, "wait_b", ViewModel.core_containers()) ==
               {"root", "body", 0}

      refute ViewModel.effective_parent(vm, "wait_b", ViewModel.core_containers()) ==
               positions["wait_b"]
    end
  end

  describe "the map" do
    # The map is the page's first section, and the graph it carries is the
    # whole document: every block, every arm, every empty slot's marker.
    # What the browser draws from it is the package's to prove; what this
    # asserts is that the page hands the package's map region this page's
    # view model and its words for event names.
    #
    # Sabotage: rendered the map region after the list; this went red on
    # the order. Reverted from a copy.
    test "both library fixtures open on a map of the whole document, above the list",
         %{conn: conn} do
      for {key, empty} <- [
            {"library_loan", "blk_ll_due/undecided/empty"},
            {"patron_registration", "blk_pr_age/otherwise/empty"}
          ] do
        {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: key]}")
        fixture = fixture(key)
        graph = map_graph(html)

        expected = BlockMap.graph(view_model_of(fixture), phrase: &EventPhrasing.phrase/1)
        assert graph == Jason.decode!(Jason.encode!(expected))

        assert BlockMap.nodes(graph) ==
                 for({node, _depth, _kind} <- outline_of(fixture), do: node.block_id)

        assert empty in map_ids(graph)

        [before_list | _rest] = String.split(html, ~s(data-plan-section="plan"))
        assert before_list =~ ~s(id="plan-map")
      end
    end

    # The list is untouched by the map: every row still there, and the map
    # region hidden from assistive technology with nothing in it that takes
    # focus - so a keyboard or a screen reader meets the document once, in
    # the list.
    #
    # Sabotage: replaced the page's `MapRegions.map_region` call with the
    # same markup written out without `aria-hidden`; this went red.
    # Reverted from a copy.
    test "the list stays complete and the map stays out of its path", %{conn: conn} do
      for key <- ["library_loan", "patron_registration"] do
        {:ok, view, html} = live(conn, ~p"/plan?#{[doc: key]}")

        assert rows_in(html) == length(outline_of(fixture(key)))

        # With a block selected, so the panel's markup is inside the check.
        [_root, {second, _depth, _kind} | _rest] = outline_of(fixture(key))
        selected = render_hook(view, "select-row", %{"block-id" => second.block_id})
        assert selected =~ ~s(data-plan-panel="#{second.block_id}")

        region = map_region(selected)
        map = LazyHTML.to_html(region)
        assert map =~ ~s(class="sb-map__region myapp-plan__map")
        refute map =~ ~r/<(button|input|select|textarea|a)[\s>]/
        refute map =~ "plan-panel"
        # The canvas scrolls, and a scroll box with nothing focusable in it
        # is a Tab stop unless it says otherwise: it is taken out of the tab
        # order, and it is the only thing in the region with a tabindex.
        assert [["-1"]] =
                 region |> LazyHTML.query("[tabindex]") |> Enum.map(&tabindex/1)

        assert region |> LazyHTML.query("#plan-map[tabindex=\"-1\"]") |> Enum.count() == 1
      end
    end

    # The hook on the map is the package's, and what it is handed is this
    # page's: the list's own event names, whether the page edits, the
    # description region's id and its store, and the picker to scroll into
    # view after an insert armed from the map.
    #
    # Sabotage: passed `select_event="select"` to the page's map region;
    # this went red. Reverted from a copy.
    test "the map's hook is handed the list's events and the description region",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      [map] = html |> LazyHTML.from_document() |> LazyHTML.query("#plan-map") |> Enum.to_list()

      assert LazyHTML.attribute(map, "phx-hook") == ["StatifierBlocksMap"]
      assert LazyHTML.attribute(map, "data-select-event") == ["select-row"]
      assert LazyHTML.attribute(map, "data-insert-event") == ["insert-open"]
      assert LazyHTML.attribute(map, "data-editable") == ["true"]
      assert LazyHTML.attribute(map, "data-info-region") == ["plan-description"]
      assert LazyHTML.attribute(map, "data-info-store") == ["plan-description-store"]
      assert LazyHTML.attribute(map, "data-insert-reveal") == ["[data-plan-picker=open]"]

      # The two ids it names are on the page, once each.
      page = LazyHTML.from_document(html)
      assert page |> LazyHTML.query("#plan-description") |> Enum.count() == 1
      assert page |> LazyHTML.query("#plan-description-store[hidden]") |> Enum.count() == 1
    end

    # The boxes read the library world's event names as words, because the
    # page hands the package `EventPhrasing.phrase/1` as `:phrase`.
    #
    # Sabotage: dropped `phrase={&EventPhrasing.phrase/1}` from the page's
    # map region; the box read "Send loan.closed" and this went red.
    # Reverted from a copy.
    test "the map's boxes read event names as words", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")
      close = html |> map_graph() |> graph_node("blk_ll_close")
      lines = Enum.join(close["lines"] || [], " ")

      assert lines =~ "Send word that the loan is closed"
      refute lines =~ "loan.closed"
    end

    # A click on the map sends the list's own event: the row is selected,
    # the hook is told which box to mark, and the panel shows the block.
    #
    # Sabotage: made panel/2 answer nil whatever was selected; this went red,
    # with the two other cases that select. Dropped the panel sentence's
    # :if; this went red on the root. Each reverted from a copy.
    #
    # 2026-09-27: statifier_blocks 0.36.0 gives `core.sequence` a sentence
    # of its own, so the library root's panel now says it under the title,
    # and the block named once is a card fixture's `Invoke`, whose type
    # declares no sentence.
    test "selecting a block from the map selects its row and names it in the panel",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")

      html = render_hook(view, "select-row", %{"block-id" => "blk_ll_loan_period"})

      assert html =~ ~s(data-selected="blk_ll_loan_period")
      assert html =~ ~s(data-plan-panel="blk_ll_loan_period")
      assert section(html, "panel") =~ "Wait 21d"

      # The root's sentence is not its title, so the panel says both.
      root = render_hook(view, "select-row", %{"block-id" => "blk_ll_root"})
      assert section(root, "panel") =~ "Run its steps in order"
      assert html =~ ~r/myapp-plan__row--selected"[^>]*data-block-id="blk_ll_loan_period"/
      assert field_keys(html) == ["duration"]

      deselected = render_hook(view, "select-row", %{"block-id" => "blk_ll_root"})
      refute deselected =~ "data-plan-panel"
      refute deselected =~ ~s(data-selected=)

      # A block whose sentence is its title is named once.
      {:ok, card, _html} = live(conn, ~p"/plan?#{[doc: "card_processing"]}")
      invoke = render_hook(card, "select-row", %{"block-id" => "blk_cp_authorize"})
      assert invoke =~ ~s(data-plan-panel="blk_cp_authorize")
      refute invoke =~ "myapp-plan__panel-sentence"
    end

    # The panel names a block as the map draws it, event names in words;
    # the row keeps the package's sentence, the name as authored.
    #
    # Sabotage: made the panel draw ViewModel.sentence/1 again; this went
    # red. Reverted from a copy.
    test "the panel reads an event name as words, the row keeps the name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "library_loan"]}")

      html = render_hook(view, "select-row", %{"block-id" => "blk_ll_close"})
      # The panel's own line, not the description region above it, which
      # says the same words.
      [_all, panel_sentence] =
        Regex.run(~r/myapp-plan__panel-sentence"\s*>\s*([^<]*?)\s*</, html)

      assert panel_sentence == "Send word that the loan is closed"
      assert row_markup(html, "blk_ll_close") =~ "Send loan.closed"
    end

    # A delayed send's clock mark has its twin in words: the row reads the
    # send's sentence, which names the delay, and so do the panel and the
    # map's own graph, which also carries the dotted edge the delay arms.
    #
    # Sabotage: blanked the deadline send's delay in the registration
    # fixture; the panel lost the delay and this went red. Reverted from a
    # copy.
    test "the registration's delayed send names its delay in the row and the panel",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      html = render_hook(view, "select-row", %{"block-id" => "blk_pr_deadline"})

      [_all, panel_sentence] =
        Regex.run(~r/myapp-plan__panel-sentence"\s*>\s*([^<]*?)\s*</, html)

      assert panel_sentence == "In 7 days, send word that the registration week is up"
      assert row_markup(html, "blk_pr_deadline") =~ "In 7 days, send registration.deadline"

      assert [%{"from" => "blk_pr_deadline", "to" => "blk_pr_expired", "delay" => "7d"}] =
               BlockMap.timers(map_graph(html))
    end

    # The map redraws from the document the page holds, so a write made
    # through the list shows on it without the map being asked.
    #
    # Sabotage: assigned the view model with `assign_new/3` in rebuild/1,
    # so the first one stuck; this went red. Reverted from a copy.
    test "a change made through the list reaches the map", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")
      assert "blk_pr_welcome" in BlockMap.nodes(map_graph(html))

      after_remove = render_hook(view, "remove", %{"block-id" => "blk_pr_welcome"})
      refute "blk_pr_welcome" in BlockMap.nodes(map_graph(after_remove))
    end

    # Read-only draws the same map, with editing off, so the hook arms no
    # insert; and selecting still names the block.
    #
    # Sabotage: passed `editable={true}` to the page's map region; the
    # read-only page said data-editable="true" and this went red. Reverted
    # from a copy.
    test "a read-only page draws the map too", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/plan?#{[doc: "library_loan", readonly: "1"]}")
      assert html =~ ~s(phx-hook="StatifierBlocksMap")
      [map] = html |> LazyHTML.from_document() |> LazyHTML.query("#plan-map") |> Enum.to_list()
      assert LazyHTML.attribute(map, "data-editable") == ["false"]
      assert LazyHTML.attribute(map, "data-select-event") == ["select-row"]

      selected = render_hook(view, "select-row", %{"block-id" => "blk_ll_loan_period"})
      assert selected =~ ~s(data-plan-panel="blk_ll_loan_period")
    end
  end

  describe "editing from the map" do
    # What the map sends is read off the page: the event names the page
    # hands the package's hook on `#plan-map`, and the payload the package
    # README's "Mounting the Map" section says the hook sends for each
    # element of the graph it draws (`"block-id"`, and `"slot"` for an empty
    # slot's marker). That the hook's clicks send exactly that is the
    # package's to prove; what the cases below hold this page to is that the
    # names it hands over are the ones its own handlers answer.

    # Sabotage: passed `select_event="select"` to the page's map region;
    # this went red, with the move, remove and update_config cases.
    # Reverted from a copy.
    test "a block selected from the map opens the one form, in the panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      %{event: event, payload: payload} =
        map_gesture(view, "block:blk_pr_deadline")

      html = render_hook(view, event, payload)

      # One form on the page, and it is in the panel.
      assert occurrences(html, ~s(id="sb-form-blk_pr_deadline")) == 1
      assert section(html, "panel") =~ ~s(id="sb-form-blk_pr_deadline")
      refute section(html, "plan") =~ "sb-form"
      assert field_keys(html) == shown_keys(node_in("patron_registration", "blk_pr_deadline"))
    end

    # The keyboard path: the selected row carries a link into the panel,
    # the panel takes focus and sits outside the map's aria-hidden region,
    # and every control in it is an ordinary button or field.
    #
    # Sabotage: put aria-hidden on the panel; this went red. Pointed the
    # row's "Its fields" link elsewhere; this went red. Each reverted from a
    # copy.
    test "the panel is reached from the row by keyboard", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")
      html = select(view, "blk_pr_deadline")

      assert row_markup(html, "blk_pr_deadline") =~ ~r/<a[^>]*href="#plan-panel"/
      assert html =~ ~r/<aside[^>]*id="plan-panel"[^>]*tabindex="-1"/
      map = html |> map_region() |> LazyHTML.to_html()
      refute map =~ "plan-panel"
      refute map =~ "sb-form"
      refute section(html, "panel") =~ "aria-hidden"
    end

    # Insert at a gap after a block: the map's "+" arms the same gap the
    # row's "+" arms, and the same pick lands the same step.
    #
    # Sabotage: passed `insert_event="insert"` to the page's map region;
    # nothing was armed and this went red. Reverted from a copy.
    test "insert at a gap: map and list give the same document", %{conn: conn} do
      from_map =
        edit(conn, "patron_registration", fn view ->
          %{event: event, payload: payload} =
            map_gesture(view, "gap:blk_pr_deadline")

          render_hook(view, event, payload)
          pick(view, ~s(li[data-block-id="blk_pr_deadline"] [data-plan-picker="open"] button))
        end)

      from_list =
        edit(conn, "patron_registration", fn view ->
          view
          |> element(~s(li[data-block-id="blk_pr_deadline"] button.myapp-plan__add))
          |> render_click()

          pick(view, ~s(li[data-block-id="blk_pr_deadline"] [data-plan-picker="open"] button))
        end)

      assert from_map == from_list

      assert slot_of(from_map, "blk_pr_verify", "body") == [
               "blk_pr_deadline",
               "new",
               "blk_pr_email",
               "blk_pr_age",
               "blk_pr_welcome"
             ]
    end

    # Insert at the head of an empty slot: the gap only the map draws. The
    # list has no row to put a "+" under, so what it is held to is the
    # package's own insert at that position.
    #
    # Sabotage: made gap_target/2 answer index 1 for a slot key; the insert
    # was refused and this went red. Reverted from a copy.
    test "insert into an empty slot lands at its head, as the package's insert does",
         %{conn: conn} do
      from_map =
        edit(conn, "patron_registration", fn view ->
          %{event: event, payload: payload} =
            map_gesture(view, "empty:blk_pr_age/otherwise/empty")

          html = render_hook(view, event, payload)
          assert section(html, "panel") =~ ~s(data-plan-slot-insert="blk_pr_age/otherwise")
          pick(view, ~s(#plan-panel [data-plan-picker="open"] button))
        end)

      original = fixture("patron_registration").document
      {:ok, wait} = StatifierBlocks.Palette.new_block(Charts.palette(), "core.wait")

      {:ok, expected, _inverse} =
        StatifierBlocks.Edit.apply(original, {:insert, {"blk_pr_age", "otherwise", 0}, wait})

      assert from_map == normalize(expected, original)
    end

    # Sabotage: made the panel's "Move up" post dir "down"; this went red.
    # Reverted from a copy.
    test "move: map and list give the same document", %{conn: conn} do
      from_map =
        edit(conn, "patron_registration", fn view ->
          map_select(view, "blk_pr_age")
          view |> element("#plan-panel button", "Move up") |> render_click()
        end)

      from_list =
        edit(conn, "patron_registration", fn view ->
          view
          |> element(~s(li[data-block-id="blk_pr_age"] button), "Move up")
          |> render_click()
        end)

      assert from_map == from_list

      assert slot_of(from_map, "blk_pr_verify", "body") == [
               "blk_pr_deadline",
               "blk_pr_age",
               "blk_pr_email",
               "blk_pr_welcome"
             ]
    end

    # Sabotage: made the panel's "Delete" post insert-close; this went red.
    # Reverted from a copy.
    test "remove: map and list give the same document", %{conn: conn} do
      from_map =
        edit(conn, "patron_registration", fn view ->
          map_select(view, "blk_pr_welcome")
          view |> element("#plan-panel button", "Delete") |> render_click()
        end)

      from_list =
        edit(conn, "patron_registration", fn view ->
          view
          |> element(~s(li[data-block-id="blk_pr_welcome"] button), "Delete")
          |> render_click()
        end)

      assert from_map == from_list

      assert slot_of(from_map, "blk_pr_verify", "body") == [
               "blk_pr_deadline",
               "blk_pr_email",
               "blk_pr_age"
             ]
    end

    # update_config: the panel's form is the one form, reached from a map
    # click or from the row, and the same change stores the same config.
    #
    # Sabotage: made config-change store nothing; this went red, with the
    # three list-side editing cases. Reverted from a copy.
    test "update_config: map and list give the same document", %{conn: conn} do
      change = fn view ->
        view
        |> element("#sb-form-blk_pr_deadline")
        |> render_change(%{"config" => %{"event" => "registration.deadline", "delay" => "10d"}})
      end

      from_map =
        edit(conn, "patron_registration", fn view ->
          map_select(view, "blk_pr_deadline")
          change.(view)
        end)

      from_list =
        edit(conn, "patron_registration", fn view ->
          select(view, "blk_pr_deadline")
          change.(view)
        end)

      assert from_map == from_list

      assert %{"delay" => "10d"} =
               from_map
               |> Document.blocks()
               |> Enum.find(&(&1.id == "blk_pr_deadline"))
               |> Map.get(:config)
    end

    # One set of move and delete controls for the selected block: the
    # panel's. Its row hides its own while it is selected, so a screen
    # reader walking the page meets the set once.
    #
    # Sabotage: drew the row's controls whatever was selected; this went
    # red. Reverted from a copy.
    test "the selected block has one set of move and delete controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")
      html = map_select(view, "blk_pr_age")

      up = ~s(phx-value-block-id="blk_pr_age" phx-value-dir="up")
      assert occurrences(html, up) == 1
      assert section(html, "panel") =~ up
      assert occurrences(html, ~s(phx-click="remove" phx-value-block-id="blk_pr_age")) == 1

      # Every other row keeps its own.
      assert row_markup(html, "blk_pr_welcome") =~
               ~s(phx-value-block-id="blk_pr_welcome" phx-value-dir="up")
    end

    # Arming an empty slot while a block is selected: the panel shows the
    # slot's picker and nothing of the block.
    #
    # Sabotage: made insert-open keep the selection for a slot key; the
    # block's form stayed beside the picker and this went red. Reverted from
    # a copy.
    test "the panel shows one thing: arming an empty slot clears the selection",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")
      map_select(view, "blk_pr_deadline")

      %{event: event, payload: payload} =
        map_gesture(view, "empty:blk_pr_age/otherwise/empty")

      html = render_hook(view, event, payload)
      panel = section(html, "panel")

      assert panel =~ ~s(data-plan-slot-insert="blk_pr_age/otherwise")
      refute panel =~ "sb-form"
      refute html =~ "data-plan-panel="
      refute html =~ "myapp-plan__row--selected"
    end

    # A refused pick at an armed empty slot closes the picker rather than
    # leaving it open on a stale target.
    #
    # Sabotage: dropped assign_insertable/1 from the insert handler's
    # refusal branch; the panel picker stayed open and this went red.
    # Reverted from a copy.
    test "a refused pick at an empty slot closes its picker", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      %{event: event, payload: payload} =
        map_gesture(view, "empty:blk_pr_age/otherwise/empty")

      assert render_hook(view, event, payload) =~ "data-plan-slot-insert"

      html = render_hook(view, "insert", Map.put(payload, "type", "no.such.type"))
      refute html =~ "data-plan-slot-insert"
      refute html =~ ~s(data-plan-picker="open")
      assert document("patron_registration") == fixture("patron_registration").document
    end

    # A read-only page hands the map `editable` off, so its hook draws no
    # gaps and arms nothing; the insert its marker would have sent is
    # refused by the page's write gate all the same; and a crafted slot
    # payload naming a slot the block does not have arms nothing.
    #
    # Sabotage: dropped "insert-open" from the read-only write gate's
    # event list; the crafted read-only insert armed a picker and this
    # went red. Reverted from a copy.
    test "nothing inserts where it cannot", %{conn: conn} do
      {:ok, read_only, html} =
        live(conn, ~p"/plan?#{[doc: "patron_registration", readonly: "1"]}")

      [map] = html |> LazyHTML.from_document() |> LazyHTML.query("#plan-map") |> Enum.to_list()
      assert LazyHTML.attribute(map, "data-editable") == ["false"]

      armed =
        render_hook(read_only, "insert-open", %{"block-id" => "blk_pr_age", "slot" => "otherwise"})

      refute armed =~ "data-plan-slot-insert"

      {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: "patron_registration"]}")

      html =
        render_hook(view, "insert-open", %{"block-id" => "blk_pr_age", "slot" => "no_such_slot"})

      refute html =~ "data-plan-slot-insert"

      render_hook(view, "insert", %{
        "block-id" => "blk_pr_age",
        "slot" => "no_such_slot",
        "type" => "core.wait"
      })

      assert document("patron_registration") == fixture("patron_registration").document
    end
  end

  # ----------------------------------------------------------------- helpers

  # The graph the page handed the map hook, decoded.
  defp map_graph(html) do
    [json] =
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("#plan-map")
      |> LazyHTML.attribute("data-graph")

    Jason.decode!(json)
  end

  defp map_ids(%{} = node),
    do: [node["id"] | Enum.flat_map(Map.get(node, "children", []), &map_ids/1)]

  # One graph node by its id, wherever it sits.
  defp graph_node(%{"id" => id} = node, id), do: node

  defp graph_node(%{} = node, id),
    do: node |> Map.get("children", []) |> Enum.find_value(&graph_node(&1, id))

  # The package's map region on the page: the one `aria-hidden` section
  # it renders, which holds the hook's element.
  defp map_region(html) do
    assert [region] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query(~s(section.sb-map__region[aria-hidden="true"]))
             |> Enum.to_list()

    region
  end

  defp tabindex(element), do: LazyHTML.attribute(element, "tabindex")

  defp view_model_of(fixture), do: ViewModel.build(fixture.document, Charts.palette(), [])

  defp fixture(key) do
    {:ok, fixture} = Charts.fixture(key)
    fixture
  end

  defp document(key) do
    fixture = fixture(key)
    Documents.get(key, fixture.document)
  end

  defp config_of(key, block_id) do
    key
    |> document()
    |> Document.blocks()
    |> Enum.find(&(&1.id == block_id))
    |> Map.fetch!(:config)
  end

  defp outline_of(fixture) do
    fixture.document
    |> ViewModel.build(Charts.palette(), [])
    |> ViewModel.outline()
  end

  defp sentence_of(%ViewModel.Node{sentence: sentence})
       when is_binary(sentence) and sentence != "",
       do: sentence

  defp sentence_of(node), do: ViewModel.title(node)

  defp rows_in(html), do: length(String.split(html, "myapp-plan__row")) - 1

  # A sentence goes into the markup escaped - `core.branch`'s carries the
  # quoted arm names - so the expectation has to be escaped too.
  defp escaped(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  # One `data-plan-section` block, so a row count can be asked of the plan,
  # the rails and the trays separately.
  defp section(html, name) do
    case String.split(html, ~s(data-plan-section="#{name}")) do
      [_before, rest] -> hd(String.split(rest, "data-plan-section"))
      _absent -> ""
    end
  end

  # The block ids in the structural fixture's root body, in order - the one
  # thing every command in the round-trip test moves. It is read off the
  # STORED document rather than off the markup, because what a command has
  # to do is change the document.
  defp body_ids do
    @plan_doc
    |> document()
    |> Map.fetch!(:root)
    |> Map.fetch!(:slots)
    |> Map.fetch!(@plan_slot)
    |> Enum.map(& &1.id)
  end

  defp occurrences(html, needle), do: length(String.split(html, needle)) - 1

  # The markup of one row, from its `data-block-id` to the end of that
  # element's opening tag, so a case can ask what a single row carries.
  defp row(html, block_id) do
    [_before, rest] = String.split(html, ~s(data-block-id="#{block_id}"), parts: 2)

    hd(String.split(rest, ">", parts: 2))
  end

  # What a click on `element` of the page's map sends: the event name the
  # page handed the hook for that gesture, read off `#plan-map`, and the
  # payload the package README says the hook sends for it. `element` is
  # `block:<id>`, `gap:<id>` or `empty:<marker id>`, and it has to be one
  # the graph on the page actually draws.
  defp map_gesture(view, element) do
    [map] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#plan-map")
      |> Enum.to_list()

    [graph] = LazyHTML.attribute(map, "data-graph")
    graph = Jason.decode!(graph)
    [select] = LazyHTML.attribute(map, "data-select-event")
    [insert] = LazyHTML.attribute(map, "data-insert-event")

    case element do
      "block:" <> id ->
        assert %{"kind" => "block"} = graph_node(graph, id)
        %{event: select, payload: %{"block-id" => id}}

      "gap:" <> id ->
        assert %{"kind" => "block", "gap" => true} = graph_node(graph, id)
        %{event: insert, payload: %{"block-id" => id}}

      "empty:" <> id ->
        assert %{"kind" => "empty", "parent" => parent, "slot" => slot} = graph_node(graph, id)
        %{event: insert, payload: %{"block-id" => parent, "slot" => slot}}
    end
  end

  defp map_select(view, block_id) do
    %{event: event, payload: payload} = map_gesture(view, "block:#{block_id}")
    render_hook(view, event, payload)
  end

  # A fresh store, one mount, `gesture` run against it, and the stored
  # document that results with any block the gesture created renamed "new".
  defp edit(conn, key, gesture) do
    :ok = Documents.reset()
    {:ok, view, _html} = live(conn, ~p"/plan?#{[doc: key]}")
    gesture.(view)
    normalize(document(key), fixture(key).document)
  end

  # Clicks the "Wait" entry of the picker under `selector`.
  defp pick(view, selector), do: view |> element(selector, ~r/^\s*Wait\s*$/) |> render_click()

  defp normalize(%Document{root: root} = document, %Document{} = original) do
    known = original |> Document.blocks() |> MapSet.new(& &1.id)
    %{document | root: rename_new(root, known)}
  end

  defp rename_new(%Block{id: id, slots: slots} = block, known) do
    slots =
      Map.new(slots, fn {name, children} -> {name, Enum.map(children, &rename_new(&1, known))} end)

    %{block | id: if(MapSet.member?(known, id), do: id, else: "new"), slots: slots}
  end

  defp slot_of(%Document{} = document, block_id, slot) do
    document
    |> Document.blocks()
    |> Enum.find(&(&1.id == block_id))
    |> Map.fetch!(:slots)
    |> Map.fetch!(slot)
    |> Enum.map(& &1.id)
  end

  defp node_in(key, block_id) do
    fixture(key).document
    |> ViewModel.build(Charts.palette(), [])
    |> ViewModel.find_node(block_id)
  end

  # The markup of one row's body: from its `<li>` to the start of the next
  # row, so a case can ask what a single row draws rather than what the page
  # draws. It anchors on the `<li>` carrying the id rather than on the id's
  # first occurrence, because the panel ahead of the list carries the
  # selected block's id on its form too.
  defp row_markup(html, block_id) do
    [_before, rest] = Regex.split(~r/<li[^>]*data-block-id="#{block_id}"/, html, parts: 2)

    hd(String.split(rest, "<li"))
  end

  # The ids of the blocks the author placed in a composite's declared
  # pass-through slots, in declaration order - the rows the plan draws beneath
  # the composite's own. Computed from `slots/1` rather than written down, so
  # a composite that gains or loses a slot is followed here.
  defp authored_children(key, block_id, module) do
    block = block_in(key, block_id)

    module.slots(%{})
    |> Enum.flat_map(fn {name, _arity, _label} -> Map.get(block.slots, name, []) end)
    |> Composite.flatten()
    |> Enum.map(& &1.id)
  end

  defp block_in(key, block_id) do
    key
    |> fixture()
    |> Map.fetch!(:document)
    |> Document.blocks()
    |> Enum.find(&(&1.id == block_id))
  end

  # The field keys in a rendered row, in order. `Field.field/1` stamps
  # `data-field` on every field it draws and draws nothing at all for a
  # hidden one, so this is exactly what the page put on the surface.
  defp field_keys(html) do
    ~r/data-field="([^"]+)"/
    |> Regex.scan(html)
    |> Enum.map(fn [_all, key] -> key end)
  end

  # The field keys a node puts on the surface, in order: the same call the
  # row template renders from, so the expectation and the page cannot drift.
  defp shown_keys(node), do: node |> ViewModel.shown_fields() |> Enum.map(& &1.key)

  # The picker, armed under `block_id`. The "+" only draws while the picker
  # is closed, and the page holds one armed gap at a time, so arming a
  # second one closes the first - which is the page's own behaviour, not a
  # test convenience.
  defp open_picker(view, block_id) do
    view
    |> element(~s(li[data-block-id="#{block_id}"] button.myapp-plan__add))
    |> render_click()
  end

  defp picker_button(block_id),
    do: ~s(li[data-block-id="#{block_id}"] [data-plan-picker="open"] button)

  # A block's slot as the STORE holds it, which is where a command has to
  # land for the gesture to have meant anything.
  defp blocks_in(block_id, slot) do
    @plan_doc
    |> document()
    |> Document.blocks()
    |> Enum.find(&(&1.id == block_id))
    |> Map.fetch!(:slots)
    |> Map.get(slot, [])
  end

  defp slot_ids(block_id, slot), do: blocks_in(block_id, slot) |> Enum.map(& &1.id)

  defp index_of(ids, id), do: Enum.find_index(ids, &(&1 == id))

  defp select(view, block_id) do
    view
    |> element(~s(li[data-block-id="#{block_id}"] button.myapp-plan__sentence))
    |> render_click()
  end

  defp move(view, block_id, dir) do
    render_hook(view, "move", %{"block-id" => block_id, "dir" => dir})
  end
end
