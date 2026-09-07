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
  | labels a row | `ViewModel.Node.sentence`, `ViewModel.title/1` |
  | draws a field | `StatifierBlocks.Editor.Field.field/1` |
  | reads a form back | `StatifierBlocks.Editor.ConfigForm.decode/3` |
  | writes to the document | `StatifierBlocks.Edit.History.commit/4` |
  | steps back and forward | `Edit.History.undo/3`, `redo/3` |
  | says which types fit a gap | `StatifierBlocks.Edit.Targets.droppable_slots_for/4` |
  | builds an inserted block | `StatifierBlocks.Palette.new_block/2` |

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
  out. That is decision 9's treatment, simplified in one way this module
  states rather than hides - the package's editor re-derives per-field
  findings from the draft and this page does not, so a refused draft here
  says that nothing is stored and not which field the refusal was about.
  A host wanting the second sentence has `StatifierBlocks.BlockType`'s
  `validate_config/1` to ask, exactly as the package's editor does.

  ## Read-only

  `?readonly=1` renders values and no controls. It is one parameter rather
  than a second page because it is the same view: the rows, the sentences,
  the sections and the indentation are all unchanged, and what goes away is
  every gesture. Fields render through the same `Editor.Field.field/1` with
  the field's own `readonly?` flag raised, which is `sb-21gm`'s second flag
  used as a host would use it - the package draws the value, and this page
  does not grow a second field renderer to draw one.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Block
  alias StatifierBlocks.BlockType
  alias StatifierBlocks.Document
  alias StatifierBlocks.Edit
  alias StatifierBlocks.Edit.History
  alias StatifierBlocks.Edit.Targets
  alias StatifierBlocks.Editor.ConfigForm
  alias StatifierBlocks.Editor.Field
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
       palette: Charts.palette(),
       fixtures: Charts.fixtures(),
       history: History.new(),
       selected_id: nil,
       drafts: %{},
       inserting: nil,
       last_error: nil
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
  def handle_event(event, _params, %{assigns: %{readonly?: true}} = socket)
      when event in ~w(config-change discard-draft field-list-add field-list-remove
                       insert-open insert-close insert move remove undo redo) do
    {:noreply, socket}
  end

  def handle_event("config-change", %{"block-id" => id} = params, socket) do
    config = ConfigForm.decode(fields_for(socket, id), params, effective_config(socket, id))

    {:noreply, change_config(socket, id, config)}
  end

  def handle_event("discard-draft", %{"block-id" => id}, socket) do
    {:noreply, socket |> update(:drafts, &Map.delete(&1, id)) |> rebuild()}
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
         {:ok, %Block{} = block} <- Palette.new_block(socket.assigns.palette, type) do
      socket =
        socket
        |> assign(:inserting, nil)
        |> commit({:insert, target, block})

      {:noreply, socket}
    else
      _no_gap_or_type -> {:noreply, assign(socket, :inserting, nil)}
    end
  end

  def handle_event("move", %{"block-id" => id, "dir" => dir}, socket) do
    step = if dir == "up", do: -1, else: 1

    case position(socket, id) do
      {parent_id, slot, index} when index + step >= 0 ->
        {:noreply, commit(socket, {:move, id, {parent_id, slot, index + step}})}

      _at_the_top_or_unplaced ->
        {:noreply, socket}
    end
  end

  def handle_event("remove", %{"block-id" => id}, socket) do
    {:noreply, socket |> assign(:selected_id, nil) |> commit({:remove, id})}
  end

  def handle_event("undo", _params, socket) do
    {:noreply, step(socket, &History.undo/3)}
  end

  def handle_event("redo", _params, socket) do
    {:noreply, step(socket, &History.redo/3)}
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
              revision {@document.revision} &middot; {@document.id}
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
            disabled={not History.can_undo?(@history)}
          >
            Undo
          </button>

          <button
            :if={not @readonly?}
            class="myapp-header__button"
            type="button"
            phx-click="redo"
            disabled={not History.can_redo?(@history)}
          >
            Redo
          </button>

          <.link class="myapp-header__button" navigate={editor_path(@fixture.key, @theme)}>
            Open in editor
          </.link>

          <span :if={@last_error} class="myapp-header__verdict" data-plan-error="true">
            {error_sentence(@last_error)}
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
              drafted?={Map.has_key?(@drafts, node.block_id)}
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
                drafted?={Map.has_key?(@drafts, node.block_id)}
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
                drafted?={Map.has_key?(@drafts, node.block_id)}
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
          {sentence(@node)}
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
          Nothing is stored yet.
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

        <div :if={@readonly?} class="myapp-plan__fields">
          <Field.field
            :for={field <- shown_fields(@node)}
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
          <Field.field :for={field <- shown_fields(@node)} field={field} target={nil} />
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

  # A row's words. `Node.sentence` is the block type's own line of prose
  # (`sb-w37s`), and `ViewModel.title/1` is the fallback the view model
  # already uses for a block whose type declares no `sentence/1` - so a
  # nil here is a block this page still names, never a blank row.
  @spec sentence(ViewModel.Node.t()) :: String.t()
  defp sentence(%ViewModel.Node{sentence: sentence}) when is_binary(sentence) and sentence != "",
    do: sentence

  defp sentence(%ViewModel.Node{} = node), do: ViewModel.title(node)

  # `sb-21gm`'s first flag, used the way ADR-0002 decision 7's amendment
  # says a host uses it: the view model lists every declared field and the
  # surface filters. `Field.field/1` renders nothing for a hidden field
  # either, and neither of the two is load-bearing alone.
  @spec shown_fields(ViewModel.Node.t()) :: [ViewModel.Field.t()]
  defp shown_fields(%ViewModel.Node{form: %ViewModel.Form{fields: fields}}),
    do: Enum.reject(fields, & &1.hidden?)

  defp shown_fields(%ViewModel.Node{}), do: []

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

    socket
    |> assign(:fixture, fixture)
    |> assign(:document, document)
    |> assign(:page_title, fixture.name)
    |> assign(:selected_id, nil)
    |> assign(:drafts, %{})
    |> assign(:inserting, nil)
  end

  # The one place a command reaches the document, so the gate, the undo
  # stack and the store have one caller each rather than one per gesture.
  @spec commit(Phoenix.LiveView.Socket.t(), Edit.t()) :: Phoenix.LiveView.Socket.t()
  defp commit(socket, command) do
    %{history: history, palette: palette, document: document} = socket.assigns

    case History.commit(history, palette, document, command) do
      {:ok, new_history, new_document} ->
        socket
        |> assign(history: new_history, document: new_document, last_error: nil)
        |> store()
        |> rebuild()

      {:error, reason} ->
        socket |> assign(:last_error, reason) |> rebuild()
    end
  end

  # A config change differs from every other command in one way: a refusal
  # is the author's bytes rather than an error, so it is held as a draft and
  # the document keeps what it had.
  @spec change_config(Phoenix.LiveView.Socket.t(), Block.id(), Block.config()) ::
          Phoenix.LiveView.Socket.t()
  defp change_config(socket, id, config) do
    %{history: history, palette: palette, document: document} = socket.assigns

    case History.commit(history, palette, document, {:update_config, id, config}) do
      {:ok, new_history, new_document} ->
        socket
        |> assign(history: new_history, document: new_document, last_error: nil)
        |> update(:drafts, &Map.delete(&1, id))
        |> store()
        |> rebuild()

      {:error, {:invalid_config, ^id, _findings}} ->
        socket |> update(:drafts, &Map.put(&1, id, config)) |> rebuild()

      {:error, reason} ->
        socket |> assign(:last_error, reason) |> rebuild()
    end
  end

  @spec step(Phoenix.LiveView.Socket.t(), fun()) :: Phoenix.LiveView.Socket.t()
  defp step(socket, move) do
    %{history: history, palette: palette, document: document} = socket.assigns

    case move.(history, palette, document) do
      {:ok, new_history, new_document} ->
        socket
        |> assign(history: new_history, document: new_document, last_error: nil)
        |> store()
        |> rebuild()

      {:error, reason} ->
        socket |> assign(:last_error, reason) |> rebuild()
    end
  end

  # `key` is the field's identity and the value's address is its
  # `value_path`, so the rows are read and written where the form's other
  # writes go. A key naming no field in the selected block edits nothing,
  # which is the same crafted-payload guard `ConfigForm.decode/3` applies.
  @spec update_list(Phoenix.LiveView.Socket.t(), String.t(), :add | {:remove, integer()}) ::
          Phoenix.LiveView.Socket.t()
  defp update_list(socket, key, gesture) do
    with id when is_binary(id) <- socket.assigns.selected_id,
         %ViewModel.Field{} = field <- Enum.find(fields_for(socket, id), &(&1.key == key)) do
      config = effective_config(socket, id)
      path = ViewModel.Field.value_path(field)

      rows =
        case BlockType.fetch_value(config, path) do
          {:ok, value} -> List.wrap(value)
          :error -> []
        end

      change_config(socket, id, BlockType.put_value(config, path, apply_gesture(rows, gesture)))
    else
      _no_selection_or_field -> socket
    end
  end

  @spec apply_gesture([term()], :add | {:remove, integer()}) :: [term()]
  defp apply_gesture(rows, :add), do: rows ++ [""]
  defp apply_gesture(rows, {:remove, index}), do: List.delete_at(rows, index)

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
    :ok = Documents.put(socket.assigns.fixture.key, socket.assigns.document)
    socket
  end

  # ------------------------------------------------------------- projection

  # Everything the render reads, derived once per change rather than per
  # render. `positions` is the one thing here the package does not answer:
  # `outline/1` says what order the blocks are in and `Targets` says which
  # slots accept a block, but where a given block sits - its parent, its
  # slot and its index - is a question a host asks of the tree it was
  # handed, so it is asked once here off the same public slots.
  @spec rebuild(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp rebuild(socket) do
    %{document: document, palette: palette} = socket.assigns

    view_model = ViewModel.build(document, palette, [])
    outline = view_model |> ViewModel.outline() |> Enum.map(&overlay_draft(&1, socket))

    socket
    |> assign(:view_model, view_model)
    |> assign(:positions, positions(view_model.root))
    |> assign(:plan, Enum.filter(outline, fn {_node, _depth, kind} -> kind in [:step, :arm] end))
    |> assign(:rails, Enum.filter(outline, fn {_node, _depth, kind} -> kind == :rail end))
    |> assign(:trays, Enum.filter(outline, fn {_node, _depth, kind} -> kind == :tray end))
    |> assign_insertable()
  end

  # The author's keystrokes, back on screen. Values only: the findings a
  # draft would carry are the package editor's second half of decision 9's
  # treatment, and this page states in its moduledoc that it does not draw
  # them rather than deriving a second set of them here.
  @spec overlay_draft(
          {ViewModel.Node.t(), non_neg_integer(), atom()},
          Phoenix.LiveView.Socket.t()
        ) ::
          {ViewModel.Node.t(), non_neg_integer(), atom()}
  defp overlay_draft({%ViewModel.Node{form: nil}, _depth, _kind} = entry, _socket), do: entry

  defp overlay_draft({%ViewModel.Node{} = node, depth, kind} = entry, socket) do
    case Map.fetch(socket.assigns.drafts, node.block_id) do
      :error ->
        entry

      {:ok, draft} ->
        fields = Enum.map(node.form.fields, &drafted_field(&1, draft))
        {%{node | form: %{node.form | fields: fields}}, depth, kind}
    end
  end

  # One field, showing the draft's value where the draft has one. A field
  # the draft says nothing about keeps the document's, which is what makes
  # a partially typed form show one changed row rather than a blank set.
  @spec drafted_field(ViewModel.Field.t(), Block.config()) :: ViewModel.Field.t()
  defp drafted_field(%ViewModel.Field{} = field, draft) do
    case BlockType.fetch_value(draft, ViewModel.Field.value_path(field)) do
      {:ok, value} -> %{field | value: value}
      :error -> field
    end
  end

  # The palette entries the armed gap accepts, asked of the package's own
  # drop check rather than of a rule written here: an unconfigured block of
  # each type is offered to `Targets.droppable_slots_for/4`, and the types
  # whose answer contains this gap's slot are the ones drawn. Recipes are
  # not offered - a recipe is the palette's other namespace and inserting
  # one is more than one command, which is a seam this page does not need.
  @spec assign_insertable(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_insertable(%{assigns: %{inserting: nil}} = socket),
    do: assign(socket, :insertable, [])

  defp assign_insertable(socket) do
    assign(socket, :insertable, insertable(socket, gap_target(socket, socket.assigns.inserting)))
  end

  @spec insertable(Phoenix.LiveView.Socket.t(), Edit.target() | nil) :: [map()]
  defp insertable(_socket, nil), do: []

  defp insertable(socket, {parent_id, slot, _index}) do
    %{document: document, palette: palette, fixture: fixture} = socket.assigns
    ctx = assignability_context(fixture)

    socket.assigns.view_model.palette_groups
    |> Enum.flat_map(& &1.entries)
    |> Enum.filter(&(&1.kind == :type and fits?(&1, document, palette, {parent_id, slot}, ctx)))
  end

  # Whether one palette entry's type would land in one slot, asked of the
  # package: an unconfigured block of the type - the same value the editor's
  # own insert builds - offered to the drop check, and the slot looked for in
  # the answer.
  @spec fits?(map(), Document.t(), Palette.t(), {Block.id(), Block.slot_name()}, map()) ::
          boolean()
  defp fits?(entry, document, palette, slot_ref, ctx) do
    case Palette.new_block(palette, entry.name) do
      {:ok, probe} -> slot_ref in Targets.droppable_slots_for(document, palette, probe, ctx)
      :error -> false
    end
  end

  # The host's datamodel document and nothing else, which is the context
  # the package's own editor asks its data-flow questions with. Two views
  # asking the same question with different contexts would be two answers.
  @spec assignability_context(Charts.Fixture.t()) :: map()
  defp assignability_context(%{datamodel: nil}), do: %{}
  defp assignability_context(%{datamodel: datamodel}), do: %{datamodel: datamodel}

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
    with %ViewModel.Node{} = node <- find_node(root, id),
         [%ViewModel.Slot{name: name} | _rest] <- ViewModel.body_slots(node) do
      {id, name, 0}
    else
      _no_node_or_body_slot -> nil
    end
  end

  # Where every block sits, as `Edit.target/0`s. The root has no position,
  # which is what makes moving and deleting it refuse rather than raise -
  # `Edit.apply/2` refuses `{:remove, root}` too, and this is the same
  # refusal one step earlier so the row draws no button that cannot work.
  @spec positions(ViewModel.Node.t()) :: %{Block.id() => Edit.target()}
  defp positions(%ViewModel.Node{} = root), do: positions(root, %{})

  @spec positions(ViewModel.Node.t(), %{Block.id() => Edit.target()}) ::
          %{Block.id() => Edit.target()}
  defp positions(%ViewModel.Node{block_id: parent_id, slots: slots}, acc) do
    Enum.reduce(slots, acc, fn slot, slot_acc ->
      slot.children
      |> Enum.with_index()
      |> Enum.reduce(slot_acc, fn {child, index}, child_acc ->
        child_acc
        |> Map.put(child.block_id, {parent_id, slot.name, index})
        |> then(&positions(child, &1))
      end)
    end)
  end

  @spec fields_for(Phoenix.LiveView.Socket.t(), Block.id()) :: [ViewModel.Field.t()]
  defp fields_for(socket, id) do
    case find_node(socket.assigns.view_model.root, id) do
      %ViewModel.Node{form: %ViewModel.Form{fields: fields}} -> fields
      _no_node_or_form -> []
    end
  end

  @spec find_node(ViewModel.Node.t(), Block.id()) :: ViewModel.Node.t() | nil
  defp find_node(%ViewModel.Node{block_id: id} = node, id), do: node

  defp find_node(%ViewModel.Node{slots: slots}, id) do
    slots
    |> Enum.flat_map(& &1.children)
    |> Enum.find_value(fn child -> find_node(child, id) end)
  end

  @spec effective_config(Phoenix.LiveView.Socket.t(), Block.id()) :: Block.config()
  defp effective_config(socket, id) do
    case Map.fetch(socket.assigns.drafts, id) do
      {:ok, draft} -> draft
      :error -> committed_config(socket.assigns.document, id)
    end
  end

  @spec committed_config(Document.t(), Block.id()) :: Block.config()
  defp committed_config(document, id) do
    case Enum.find(Document.blocks(document), &(&1.id == id)) do
      %Block{config: config} -> config
      nil -> %{}
    end
  end

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
