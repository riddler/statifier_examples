defmodule StatifierExamplesWeb.PlanLiveTest do
  # Not async: this file drives pages that write `StatifierExamples.Documents`,
  # which is one named Agent shared process-wide, and `ConnCase` resets that
  # store in `setup` - two async cases clear it under each other mid-test.
  use StatifierExamplesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias StatifierBlocks.Block
  alias StatifierBlocks.Composite
  alias StatifierBlocks.Document
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.CardAuth.AuthorizeWithDeadline
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Messaging.Notify
  alias StatifierExamples.Documents
  alias StatifierExamples.Signup.GuardedStep

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

  # The two composites this app ships, as `{fixture key, block id, module,
  # sentence}`. Each is read on a fixture of its own that holds nothing else,
  # so "one row for the composite" is a question the row COUNT can answer.
  # The module is carried so a case can ask the declaration what its params
  # are rather than transcribe them.
  @composites [
    {"card_processing_composite", "blk_cpx_authz", AuthorizeWithDeadline,
     "Authorize within 1h, else abandon"},
    {"signup_guarded_step", "blk_gs_step", GuardedStep, "Run myapp:provision, notify on failure"}
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
      |> element("#plan-form-#{@block_id}")
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
        |> element("#plan-form-#{@block_id}")
        |> render_change(%{"config" => %{"invoke_type" => ""}})

      assert html =~ "Nothing is stored yet"
      assert config_of(@doc_key, @block_id)["invoke_type"] != ""

      assert plan
             |> element(~s(li[data-block-id="#{@block_id}"] button), "Discard edits")
             |> render_click() =~ @block_label

      refute render(plan) =~ "Nothing is stored yet"
    end

    # `se-f4a`, folded into `se-avi`. The page used to say a refusal
    # happened and stop there. It now derives the draft's own findings from
    # the public `validate_config/1` and routes each onto the field its key
    # names, which is what `ViewModel.overlay_draft/2`'s documentation says
    # a consumer wanting them does - that function is the values half and
    # states no opinion about whether a draft validates.
    #
    # Both halves of the expectation are asked of the declaration rather
    # than written down: the label off `config_schema/1` and the message off
    # `validate_config/1`, so a type that rewords either is a change this
    # case follows instead of one it goes red on for the wrong reason.
    #
    # Sabotage: pointed `route_findings/3`'s field map at `&1.key` on the
    # findings map instead of `Map.get(by_key, field.key, [])`, so every
    # field got every finding; the "one field named" assertion went red.
    # Reverted from a copy.
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
        |> element("#plan-form-#{@block_id}")
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
             |> element(~s(li[data-block-id="#{@block_id}"] button), "Discard edits")
             |> render_click() =~ escaped(message)
    end
  end

  describe "a composite as a row" do
    # `RQ-SF037-3` at the page: a composite exposes no slot, so it is ONE
    # row - the declaration's sentence with this block's params in it - and
    # the arrangement `subtree/1` describes is drawn nowhere. The expanded
    # ids are asked of `Composite.expand/2` rather than written down, so an
    # expansion that reshaped is still refuted by the same case.
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

        assert rows_in(html) == 2, "#{key}: a composite and its root are two rows"
        assert occurrences(html, ~s(data-block-id="#{block_id}")) == 1
        assert html =~ escaped(sentence)

        {members, _params} = Composite.expand(block_in(key, block_id), module)

        for %Block{id: expanded} <- Composite.flatten(members) do
          refute html =~ ~s(data-block-id="#{expanded}"),
                 "#{key}: #{expanded} is an expanded block and was drawn"
        end
      end
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
      refute selected =~ "plan-form-#{@block_id}"
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

  # ----------------------------------------------------------------- helpers

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
