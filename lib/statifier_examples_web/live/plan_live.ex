defmodule StatifierExamplesWeb.PlanLive do
  @moduledoc """
  A second view of the same document, as a list of steps:
  `/plan?doc=<key>&theme=<light|dark|brand>&readonly=1`.

  `docs/decisions.md` D16 says components promote and layouts do not: a
  second way to lay a document out is a host's page, not a mode inside the
  package editor. This module is the reference for that claim, and the
  claim is only worth anything if the page is built from the package's
  **public** APIs and nothing else. It is:

  | What the page does | The public API it does it with |
  |---|---|
  | reads the document | `StatifierBlocks.ViewModel.build/3` |
  | orders the rows | `StatifierBlocks.ViewModel.outline/1` |
  | labels a row | `ViewModel.sentence/1` |
  | picks a row's fields | `ViewModel.shown_fields/1`, `ViewModel.fields_for/2` |
  | finds a block, and where it sits | `ViewModel.find_node/2`, `ViewModel.positions/1` |
  | reads a block's config | `StatifierBlocks.Document.committed_config/2`, `effective_config/3` |
  | draws a field | `StatifierBlocks.Editor.Field.field/1` |
  | reads a form back | `StatifierBlocks.Editor.ConfigForm.decode/3` |
  | writes to the document | `StatifierBlocks.Edit.Session.commit/2`, `change_config/3` |
  | edits a list field | `Edit.Session.update_list/4` |
  | steps back and forward | `Edit.Session.step/2` |
  | shows a refused draft | `ViewModel.overlay_draft/2`, `ViewModel.overlay_findings/2` |
  | says which types fit a gap | `StatifierBlocks.Edit.Targets.accepted_types/4` |
  | names the data-flow context | `StatifierBlocks.Assignability.context/1` |
  | builds an inserted block | `StatifierBlocks.Palette.new_block/2` |

  `se-avi` is where that table stopped being an aspiration. The page used
  to hold its own copy of fourteen of these - a `find_node/2`, a
  `positions/1`, a commit funnel, a draft treatment, a fit filter - written
  against the same document the package's editor was written against and
  free to drift from it. `statifier_blocks` promoted them, and this module
  deleted its copies. What is left below the render is this app's: the
  store, the page's own parameter reading, the crafted-payload guards, and
  the wording of a refusal.

  There is no drag anywhere on this page, which is the point rather than an
  omission. A plan is a list, a list is reordered with two buttons, and the
  gesture the canvas needs a pointer for is the gesture this view does not
  have. Every other question - what a block is called, which types a slot
  accepts, whether a config is valid - is asked of the package, because a
  second answer to any of them is how two views of one document start
  disagreeing about it.

  ## What `outline/1` hands over, and what this page does with it

  `outline/1` is a pre-order walk: one `{node, depth, kind}` per block,
  every block exactly once, `kind` saying how the block is reached rather
  than which blocks are worth listing. This page partitions on `kind`:

    * `:step` and `:arm` are the plan itself, indented by `depth`. An arm
      row carries its slot's condition where the type declared one, so the
      reader can see which way the document branches without a canvas;
    * `:rail` rows fold into one **If something goes wrong** section, under
      the plan rather than beside it, because a failure path read in line
      with the happy path is a plan nobody can skim;
    * `:tray` rows sit in a footer, which is where the canvas draws them
      too.

  Nothing is dropped. A row this page did not know how to draw would be a
  block a reader cannot see, and a plan you cannot trust to be the document
  is worth less than no plan.

  ## Editing

  A row is selected by clicking it, and a selected row expands to its
  config fields - the ones `sb-21gm` did not flag `hidden?`, drawn with the
  package's own `Editor.Field.field/1` so the control an author types into
  here is the control they type into on the canvas. `target={nil}` is what
  points the form's events at this LiveView instead of at a component that
  is not on the page.

  A refused value is held as a **draft**: the author's bytes stay on
  screen, the document keeps what it had, and `Discard edits` is the way
  out. That is decision 9's treatment, and it is the package's rather than
  a re-implementation - `Edit.Session.change_config/3` is what decides that
  an `{:invalid_config, id, findings}` refusal becomes a draft and every
  other refusal becomes an error.

  The values come back on screen through `ViewModel.overlay_draft/2` and
  the findings beside them through `ViewModel.overlay_findings/2`: the
  first puts the author's bytes back on the fields, the second routes the
  refusal's own per-field findings onto them, with anything routing
  nowhere drawn above the form. A refused draft names the field it was
  about.

  `se-f4a` derived those findings here instead, by re-running
  `BlockType.validate_config/1` over the draft, because the funnel
  discarded the findings its own refusal carried. That was this page's one
  standing piece of residue against the package and `sb-8fa8` closed it:
  `change_config/3` keeps them in the session's `draft_findings`, so the
  form draws what the refusal said rather than a second derivation of it.
  Two host functions went with the residue.

  ## Read-only

  `?readonly=1` renders values and no controls. It is one parameter rather
  than a second page because it is the same view: the rows, the sentences,
  the sections and the indentation are all unchanged, and what goes away is
  every gesture. Fields render through the same `Editor.Field.field/1` with
  the field's own `readonly?` flag raised, which is `sb-21gm`'s second flag
  used as a host would use it - the package draws the value, and this page
  does not grow a second field renderer to draw one.

  `se-4v1` asked whether the package's own `read_only?` profile
  (`statifier_blocks` 0.24.0) replaces this. It does not, for two reasons
  the package states itself. `profile` is an assign on the
  `StatifierBlocks.Editor` live component, and this page mounts no editor;
  and `docs/profiles.md` says `read_only?` "is not an authorization
  boundary... If you must prevent a write, enforce that where you handle
  the write, not by trusting a rendering." So the write gate below stays a
  `handle_event/3` clause, and what the package's read-only treatment owns
  here is the rendering: the field, drawn as a value.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Assignability
  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Edit
  alias StatifierBlocks.Edit.History
  alias StatifierBlocks.Edit.Session
  alias StatifierBlocks.Edit.Targets
  alias StatifierBlocks.Editor.ConfigForm
  alias StatifierBlocks.Editor.Field
  alias StatifierBlocks.Finding
  alias StatifierBlocks.Palette
  alias StatifierBlocks.ViewModel
  alias StatifierExamples.Charts
  alias StatifierExamples.Documents

  @default_theme :light

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Plan",
       fixtures: Charts.fixtures(),
       session: nil,
       selected_id: nil,
       inserting: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:theme, theme_param(params))
      |> assign(:readonly?, readonly_param(params))
      |> load_document(document_param(socket, params))
      |> rebuild()

    {:noreply, socket}
  end

  # --------------------------------------------------------------- gestures

  @impl Phoenix.LiveView
  def handle_event("select-document", %{"doc" => key}, socket) do
    {:noreply, push_patch(socket, to: plan_path(key, socket.assigns.theme, socket.assigns))}
  end

  def handle_event("select-row", %{"block-id" => id}, socket) do
    selected = if socket.assigns.selected_id == id, do: nil, else: id

    {:noreply, socket |> assign(selected_id: selected, inserting: nil) |> rebuild()}
  end

  # Every gesture below writes, so each one is refused outright when the
  # page is read-only. The guard is a clause rather than a check inside
  # each handler: a read-only page draws no control that could send these,
  # and what this defends against is a crafted payload rather than a
  # button.
  #
  # `se-4v1` asked for this clause to go once the package had its own
  # `read_only?` profile. It stays, and the package's own guide is why:
  # `docs/profiles.md` says in as many words that `read_only?` "is not an
  # authorization boundary... If you must prevent a write, enforce that
  # where you handle the write, not by trusting a rendering." A profile is
  # also an assign on the `StatifierBlocks.Editor` live component, and this
  # page mounts no editor - it draws its own rows around
  # `Editor.Field.field/1` - so there is no profile for it to pass. What
  # the package's read-only treatment does own here is the FIELD: each one
  # is drawn with its own `readonly?` raised, which is the same
  # value-not-control rendering clause 3 of that guide describes. Two
  # answers to "may this write" would be one too many if both were
  # renderings; one of these is a write gate and the other is a drawing,
  # and a host needs both.
  def handle_event(event, _params, %{assigns: %{readonly?: true}} = socket)
      when event in ~w(config-change discard-draft field-list-add field-list-remove
                       insert-open insert-close insert move remove undo redo) do
    {:noreply, socket}
  end

  def handle_event("config-change", %{"block-id" => id} = params, socket) do
    %{session: session} = socket.assigns

    config =
      ConfigForm.decode(
        fields_for(socket, id),
        params,
        Document.effective_config(session.document, id, session.drafts)
      )

    {:noreply, apply_session(socket, Session.change_config(session, id, config))}
  end

  def handle_event("discard-draft", %{"block-id" => id}, socket) do
    %{session: session} = socket.assigns

    {:noreply,
     socket
     |> assign(:session, %{session | drafts: Map.delete(session.drafts, id)})
     |> rebuild()}
  end

  def handle_event("field-list-add", %{"key" => key}, socket) do
    {:noreply, update_list(socket, key, :add)}
  end

  def handle_event("field-list-remove", %{"key" => key, "index" => index}, socket) do
    {:noreply, update_list(socket, key, {:remove, to_index(index)})}
  end

  # The "+" between two rows: arming it is what asks the assignability
  # question, and it is asked here rather than on every render because the
  # answer costs one drop check per palette type and a plan has many gaps.
  def handle_event("insert-open", %{"block-id" => id}, socket) do
    {:noreply, socket |> assign(:inserting, id) |> assign_insertable()}
  end

  def handle_event("insert-close", _params, socket) do
    {:noreply, socket |> assign(:inserting, nil) |> assign_insertable()}
  end

  def handle_event("insert", %{"block-id" => id, "type" => type}, socket) do
    with {_parent_id, _slot, _index} = target <- gap_target(socket, id),
         {:ok, %Block{} = block} <- Palette.new_block(socket.assigns.session.palette, type) do
      socket =
        socket
        |> assign(:inserting, nil)
        |> apply_session(Session.commit(socket.assigns.session, {:insert, target, block}))

      {:noreply, socket}
    else
      _no_gap_or_type -> {:noreply, assign(socket, :inserting, nil)}
    end
  end

  def handle_event("move", %{"block-id" => id, "dir" => dir}, socket) do
    step = if dir == "up", do: -1, else: 1

    case position(socket, id) do
      {parent_id, slot, index} when index + step >= 0 ->
        {:noreply,
         apply_session(
           socket,
           Session.commit(socket.assigns.session, {:move, id, {parent_id, slot, index + step}})
         )}

      _at_the_top_or_unplaced ->
        {:noreply, socket}
    end
  end

  def handle_event("remove", %{"block-id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:selected_id, nil)
     |> apply_session(Session.commit(socket.assigns.session, {:remove, id}))}
  end

  def handle_event("undo", _params, socket) do
    {:noreply, apply_session(socket, Session.step(socket.assigns.session, :undo))}
  end

  def handle_event("redo", _params, socket) do
    {:noreply, apply_session(socket, Session.step(socket.assigns.session, :redo))}
  end

  # ----------------------------------------------------------------- render

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div
      class="myapp-page myapp-page--plan"
      data-theme={@theme}
      data-readonly={if @readonly?, do: "true"}
    >
      <div class="sb-editor myapp-plan">
        <div class="myapp-header">
          <div class="myapp-header__identity">
            <span class="myapp-header__title">{@fixture.name}</span>
            <span class="myapp-header__meta">
              revision {@session.document.revision} &middot; {@session.document.id}
            </span>
          </div>

          <form id="document-switcher" class="myapp-header__control" phx-change="select-document">
            <label class="myapp-header__label" for="doc-select">Document</label>
            <select class="myapp-header__select" id="doc-select" name="doc">
              <option
                :for={fixture <- @fixtures}
                value={fixture.key}
                selected={fixture.key == @fixture.key}
              >
                {fixture.name}
              </option>
            </select>
          </form>

          <button
            :if={not @readonly?}
            class="myapp-header__button"
            type="button"
            phx-click="undo"
            disabled={not History.can_undo?(@session.history)}
          >
            Undo
          </button>

          <button
            :if={not @readonly?}
            class="myapp-header__button"
            type="button"
            phx-click="redo"
            disabled={not History.can_redo?(@session.history)}
          >
            Redo
          </button>

          <.link class="myapp-header__button" navigate={editor_path(@fixture.key, @theme)}>
            Open in editor
          </.link>

          <span :if={@session.last_error} class="myapp-header__verdict" data-plan-error="true">
            {error_sentence(@session.last_error)}
          </span>
        </div>

        <div class="myapp-plan__body">
          <ol class="myapp-plan__list" data-plan-section="plan">
            <.row
              :for={{node, depth, kind} <- @plan}
              node={node}
              depth={depth}
              kind={kind}
              selected_id={@selected_id}
              inserting={@inserting}
              insertable={@insertable}
              readonly?={@readonly?}
              drafted?={Map.has_key?(@session.drafts, node.block_id)}
            />
          </ol>

          <section :if={@rails != []} class="myapp-plan__section" data-plan-section="rails">
            <h2 class="myapp-plan__section-title">If something goes wrong</h2>
            <ol class="myapp-plan__list">
              <.row
                :for={{node, depth, kind} <- @rails}
                node={node}
                depth={depth}
                kind={kind}
                selected_id={@selected_id}
                inserting={@inserting}
                insertable={@insertable}
                readonly?={@readonly?}
                drafted?={Map.has_key?(@session.drafts, node.block_id)}
              />
            </ol>
          </section>

          <footer :if={@trays != []} class="myapp-plan__section" data-plan-section="trays">
            <h2 class="myapp-plan__section-title">Kept to one side</h2>
            <ol class="myapp-plan__list">
              <.row
                :for={{node, depth, kind} <- @trays}
                node={node}
                depth={depth}
                kind={kind}
                selected_id={@selected_id}
                inserting={@inserting}
                insertable={@insertable}
                readonly?={@readonly?}
                drafted?={Map.has_key?(@session.drafts, node.block_id)}
              />
            </ol>
          </footer>
        </div>
      </div>
    </div>
    """
  end

  attr(:node, ViewModel.Node, required: true)
  attr(:depth, :integer, required: true)
  attr(:kind, :atom, required: true)
  attr(:selected_id, :string, default: nil)
  attr(:inserting, :string, default: nil)
  attr(:insertable, :list, default: [])
  attr(:readonly?, :boolean, default: false)
  attr(:drafted?, :boolean, default: false)

  # One outline entry. The indentation is `depth` and nothing else -
  # `outline/1`'s depth is block nesting depth, so a rail's blocks sit at
  # the same indent as the body blocks of the container they hang off, and
  # the section they are in is what says they are a rail.
  defp row(assigns) do
    ~H"""
    <li
      class={["myapp-plan__row", @selected_id == @node.block_id && "myapp-plan__row--selected"]}
      style={"--plan-depth: #{@depth}"}
      data-block-id={@node.block_id}
      data-depth={@depth}
      data-kind={@kind}
    >
      <div class="myapp-plan__line">
        <button
          class="myapp-plan__sentence"
          type="button"
          phx-click="select-row"
          phx-value-block-id={@node.block_id}
        >
          {ViewModel.sentence(@node)}
        </button>

        <span :if={@node.findings_count > 0} class="myapp-plan__findings">
          {@node.findings_count}
        </span>

        <span :if={not @readonly? and @node.block_id != @selected_id} class="myapp-plan__controls">
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="move"
            phx-value-block-id={@node.block_id}
            phx-value-dir="up"
          >
            Move up
          </button>
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="move"
            phx-value-block-id={@node.block_id}
            phx-value-dir="down"
          >
            Move down
          </button>
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="remove"
            phx-value-block-id={@node.block_id}
          >
            Delete
          </button>
        </span>
      </div>

      <div :if={@selected_id == @node.block_id and @node.form} class="myapp-plan__form">
        <p :if={@drafted?} class="myapp-plan__pending">
          Nothing is stored yet{refused_fields(@node)}.
          <button
            :if={not @readonly?}
            class="myapp-plan__control"
            type="button"
            phx-click="discard-draft"
            phx-value-block-id={@node.block_id}
          >
            Discard edits
          </button>
        </p>

        <p
          :for={finding <- unrouted_findings(@node)}
          class="myapp-plan__pending"
          data-plan-unrouted="true"
        >
          {finding.message}
        </p>

        <div :if={@readonly?} class="myapp-plan__fields">
          <Field.field
            :for={field <- ViewModel.shown_fields(@node)}
            field={%{field | readonly?: true}}
            target={nil}
          />
        </div>

        <form
          :if={not @readonly?}
          id={"plan-form-" <> @node.block_id}
          class="myapp-plan__fields"
          phx-change="config-change"
          phx-submit="config-change"
        >
          <input type="hidden" name="block-id" value={@node.block_id} />
          <Field.field :for={field <- ViewModel.shown_fields(@node)} field={field} target={nil} />
        </form>

        <span :if={not @readonly?} class="myapp-plan__controls">
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="move"
            phx-value-block-id={@node.block_id}
            phx-value-dir="up"
          >
            Move up
          </button>
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="move"
            phx-value-block-id={@node.block_id}
            phx-value-dir="down"
          >
            Move down
          </button>
          <button
            class="myapp-plan__control"
            type="button"
            phx-click="remove"
            phx-value-block-id={@node.block_id}
          >
            Delete
          </button>
        </span>
      </div>

      <div :if={not @readonly?} class="myapp-plan__gap">
        <button
          :if={@inserting != @node.block_id}
          class="myapp-plan__add"
          type="button"
          phx-click="insert-open"
          phx-value-block-id={@node.block_id}
        >
          +
        </button>

        <div :if={@inserting == @node.block_id} class="myapp-plan__picker" data-plan-picker="open">
          <p :if={@insertable == []} class="myapp-plan__picker-empty">
            Nothing this palette carries fits here.
          </p>
          <button
            :for={entry <- @insertable}
            class="myapp-plan__control"
            type="button"
            phx-click="insert"
            phx-value-block-id={@node.block_id}
            phx-value-type={entry.name}
          >
            {entry.entry.label}
          </button>
          <button class="myapp-plan__control" type="button" phx-click="insert-close">
            Cancel
          </button>
        </div>
      </div>
    </li>
    """
  end

  # What a refused draft is about, as the tail of the pending sentence.
  # `se-f4a`: "Nothing is stored yet" on its own says a refusal happened
  # and not what it was about, and the field it was about is the one the
  # author is looking at.
  @spec refused_fields(ViewModel.Node.t()) :: String.t()
  defp refused_fields(%ViewModel.Node{form: %ViewModel.Form{fields: fields}}) do
    case fields |> Enum.reject(&(&1.findings == [])) |> Enum.map(& &1.label) do
      [] -> ""
      labels -> ": " <> Enum.join(labels, ", ")
    end
  end

  defp refused_fields(%ViewModel.Node{}), do: ""

  # The draft's findings that name no field of this form. The view model's
  # own routing table puts them in `form.unrouted` for a committed config
  # and this page draws the same place for a drafted one, because a
  # refusal a surface routes nowhere is a refusal the author never reads.
  @spec unrouted_findings(ViewModel.Node.t()) :: [Finding.t()]
  defp unrouted_findings(%ViewModel.Node{form: %ViewModel.Form{unrouted: unrouted}}), do: unrouted
  defp unrouted_findings(%ViewModel.Node{}), do: []

  # ------------------------------------------------------------- parameters

  @spec document_param(Phoenix.LiveView.Socket.t(), map()) :: Charts.Fixture.t()
  defp document_param(socket, params) do
    with key when is_binary(key) <- params["doc"],
         {:ok, fixture} <- Charts.fixture(key) do
      fixture
    else
      _absent_or_unknown -> hd(socket.assigns.fixtures)
    end
  end

  @spec theme_param(map()) :: atom()
  defp theme_param(params) do
    Enum.find(Charts.themes(), @default_theme, &(Atom.to_string(&1) == params["theme"]))
  end

  # One spelling, `1`, rather than a truthiness rule over whatever arrives.
  # A parameter that has to be read out of a bug report is one somebody
  # types, and "which of `true`, `yes` and `on` did we accept" is a question
  # a reader should not have to ask.
  @spec readonly_param(map()) :: boolean()
  defp readonly_param(params), do: params["readonly"] == "1"

  @spec plan_path(String.t(), atom(), map()) :: String.t()
  defp plan_path(key, theme, %{readonly?: true}),
    do: ~p"/plan?#{[doc: key, theme: to_string(theme), readonly: "1"]}"

  defp plan_path(key, theme, _assigns), do: ~p"/plan?#{[doc: key, theme: to_string(theme)]}"

  # The other view of the same document, at the URL that view reads. This is
  # the link the "one document, two views" claim rests on: it carries the
  # key, so what opens there is what is being edited here.
  @spec editor_path(String.t(), atom()) :: String.t()
  defp editor_path(key, theme), do: ~p"/editor?#{[doc: key, theme: to_string(theme)]}"

  # ---------------------------------------------------------------- editing

  @spec load_document(Phoenix.LiveView.Socket.t(), Charts.Fixture.t()) ::
          Phoenix.LiveView.Socket.t()
  defp load_document(socket, fixture) do
    document = Documents.get(fixture.key, fixture.document)

    session = %Session{
      palette: Charts.palette(),
      document: document,
      history: History.new()
    }

    socket
    |> assign(:fixture, fixture)
    |> assign(:session, session)
    |> assign(:page_title, fixture.name)
    |> assign(:selected_id, nil)
    |> assign(:inserting, nil)
  end

  # Every write on this page is a `StatifierBlocks.Edit.Session` call, and
  # this is what the page does with the answer: the session is the new
  # state either way, and a session whose document moved is stored. The
  # gate, the undo stack, the draft treatment and the refusal vocabulary
  # are all the package's - what stays here is the store, which is this
  # app's.
  @spec apply_session(Phoenix.LiveView.Socket.t(), {:ok, Session.t()} | {:error, Session.t()}) ::
          Phoenix.LiveView.Socket.t()
  defp apply_session(socket, {:ok, %Session{} = session}),
    do: socket |> assign(:session, session) |> store() |> rebuild()

  defp apply_session(socket, {:error, %Session{} = session}),
    do: socket |> assign(:session, session) |> rebuild()

  # `key` is the field's identity, and a key naming no field in the
  # selected block edits nothing - the same crafted-payload guard
  # `ConfigForm.decode/3` applies. What the gesture then MEANS is
  # `Session.update_list/4`'s: it reads the rows off the effective config
  # at the field's own `value_path/1`, applies the gesture, and commits
  # through the draft treatment, so a list edit that leaves the config
  # invalid is held like any other refused config rather than lost.
  @spec update_list(Phoenix.LiveView.Socket.t(), String.t(), Session.list_gesture()) ::
          Phoenix.LiveView.Socket.t()
  defp update_list(socket, key, gesture) do
    with id when is_binary(id) <- socket.assigns.selected_id,
         %ViewModel.Field{} = field <- Enum.find(fields_for(socket, id), &(&1.key == key)) do
      apply_session(socket, Session.update_list(socket.assigns.session, id, field, gesture))
    else
      _no_selection_or_field -> socket
    end
  end

  @spec to_index(term()) :: integer()
  defp to_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {number, ""} -> number
      _not_a_number -> -1
    end
  end

  defp to_index(_index), do: -1

  @spec store(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp store(socket) do
    :ok = Documents.put(socket.assigns.fixture.key, socket.assigns.session.document)
    socket
  end

  # ------------------------------------------------------------- projection

  # Everything the render reads, derived once per change rather than per
  # render. Every question in here is the package's: `outline/1` orders the
  # rows, `positions/1` says where each block sits, and `overlay_draft/2`
  # with `overlay_findings/2` puts a refused draft's bytes and its findings
  # back on the fields.
  @spec rebuild(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp rebuild(socket) do
    %Session{document: document, palette: palette, drafts: drafts, draft_findings: findings} =
      socket.assigns.session

    view_model = ViewModel.build(document, palette, [])

    outline =
      view_model
      |> ViewModel.outline()
      |> Enum.map(&overlay_draft(&1, drafts, findings))

    socket
    |> assign(:view_model, view_model)
    |> assign(:positions, ViewModel.positions(view_model))
    |> assign(:plan, Enum.filter(outline, fn {_node, _depth, kind} -> kind in [:step, :arm] end))
    |> assign(:rails, Enum.filter(outline, fn {_node, _depth, kind} -> kind == :rail end))
    |> assign(:trays, Enum.filter(outline, fn {_node, _depth, kind} -> kind == :tray end))
    |> assign_insertable()
  end

  # One outline entry with its draft over it, where a draft is held. Both
  # halves are the package's now: `ViewModel.overlay_draft/2` puts the
  # refused bytes back on the fields, and `ViewModel.overlay_findings/2`
  # routes the refusal's own per-field findings onto them.
  #
  # `se-f4a` derived those findings here, by re-running the type's
  # `validate_config/1` over the draft, because `Edit.Session` threw away
  # the `{:invalid_config, id, findings}` it had already been handed. That
  # was this page's residue and it is `sb-8fa8`'s answer now: a refused
  # `Session.change_config/3` keeps them in `draft_findings` under the
  # block's id, so what reaches the form is what the funnel actually said
  # rather than a second derivation that could disagree with it.
  @spec overlay_draft(
          {ViewModel.Node.t(), non_neg_integer(), atom()},
          Session.drafts(),
          Session.draft_findings()
        ) :: {ViewModel.Node.t(), non_neg_integer(), atom()}
  defp overlay_draft({%ViewModel.Node{} = node, depth, kind} = entry, drafts, findings) do
    case Map.fetch(drafts, node.block_id) do
      :error ->
        entry

      {:ok, draft} ->
        overlaid =
          node
          |> ViewModel.overlay_draft(draft)
          |> ViewModel.overlay_findings(Map.get(findings, node.block_id, []))

        {overlaid, depth, kind}
    end
  end

  # The palette entries the armed gap accepts, asked of the package's one
  # answer to the question: `Targets.accepted_types/4` probes every type in
  # the palette with the entry's own `default_config` merged in and answers
  # with the type NAMES that fit, and this filters the entry list the page
  # is already drawing by membership. Recipes are not offered - a recipe is
  # the palette's other namespace and inserting one is more than one
  # command, which is a seam this page does not need.
  @spec assign_insertable(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_insertable(%{assigns: %{inserting: nil}} = socket),
    do: assign(socket, :insertable, [])

  defp assign_insertable(socket) do
    assign(socket, :insertable, insertable(socket, gap_target(socket, socket.assigns.inserting)))
  end

  @spec insertable(Phoenix.LiveView.Socket.t(), Edit.target() | nil) :: [map()]
  defp insertable(_socket, nil), do: []

  defp insertable(socket, {parent_id, slot, _index}) do
    %Session{document: document, palette: palette} = socket.assigns.session

    accepted =
      Targets.accepted_types(
        document,
        palette,
        {parent_id, slot},
        Assignability.context(socket.assigns.fixture)
      )

    socket.assigns.view_model.palette_groups
    |> Enum.flat_map(& &1.entries)
    |> Enum.filter(&(&1.kind == :type and MapSet.member?(accepted, &1.name)))
  end

  @spec position(Phoenix.LiveView.Socket.t(), Block.id() | nil) :: Edit.target() | nil
  defp position(_socket, nil), do: nil
  defp position(socket, id), do: Map.get(socket.assigns.positions, id)

  # Where the "+" under a row inserts. Under an ordinary row that is the
  # next place in the slot the row sits in, which is what "add after this
  # line" means in a list. The root has no such place - it sits in no slot -
  # so its own "+" means the other thing the reader could mean by it: the
  # first step inside the plan. A root with no body slot at all offers
  # nothing, which is the empty-list answer every other refusal here gives.
  @spec gap_target(Phoenix.LiveView.Socket.t(), Block.id() | nil) :: Edit.target() | nil
  defp gap_target(_socket, nil), do: nil

  defp gap_target(socket, id) do
    case position(socket, id) do
      {parent_id, slot, index} -> {parent_id, slot, index + 1}
      nil -> first_body_target(socket.assigns.view_model.root, id)
    end
  end

  # The gap a block that sits in no slot offers: the head of its own first
  # body slot. Only the root reaches this, and only because the root is the
  # one row whose "+" cannot mean "after me".
  @spec first_body_target(ViewModel.Node.t(), Block.id()) :: Edit.target() | nil
  defp first_body_target(root, id) do
    with %ViewModel.Node{} = node <- ViewModel.find_node(root, id),
         [%ViewModel.Slot{name: name} | _rest] <- ViewModel.body_slots(node) do
      {id, name, 0}
    else
      _no_node_or_body_slot -> nil
    end
  end

  # The selected block's declared fields, off the view model the render
  # was built from. `ViewModel.fields_for/2` is `find_node/2` and the form
  # in one call, which is exactly what the form decoder needs.
  @spec fields_for(Phoenix.LiveView.Socket.t(), Block.id()) :: [ViewModel.Field.t()]
  defp fields_for(socket, id), do: ViewModel.fields_for(socket.assigns.view_model, id)

  # A refused command in one line. The reasons are `Edit.apply/2`'s own
  # union and this app renders them rather than swallowing them: a Delete
  # that did nothing with no sentence beside it is the bug report this
  # page exists to make unnecessary.
  @spec error_sentence(term()) :: String.t()
  defp error_sentence({:cannot_remove_root, _id}), do: "The root block cannot be deleted."
  defp error_sentence({:index_out_of_range, _target}), do: "There is nowhere to move it."
  defp error_sentence(:nothing_to_undo), do: "There is nothing to undo."
  defp error_sentence(:nothing_to_redo), do: "There is nothing to redo."
  defp error_sentence(_other), do: "That change was refused."
end
