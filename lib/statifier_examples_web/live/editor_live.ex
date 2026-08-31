defmodule StatifierExamplesWeb.EditorLive do
  @moduledoc """
  The editor host page: `/editor?doc=<key>&theme=<light|dark|brand>`.

  This is the reference embedder's reference page. ADR-0005's shell amendment
  splits the editing surface from the document chrome - the package ships the
  first and the host ships the second - and this module is the second half,
  written the way a host would write it rather than the way a package would.

  ## Why the URL carries the state

  Both selections are query parameters and `handle_params/3` is the only place
  they are read. That is not REST piety: a headless capture, a browser loop
  and a bug report all name a screen by URL, and a page whose document lives
  only in a `phx-click` cannot be named at all. Both fall back rather than
  refuse - an unknown document is the first fixture and an unknown theme is
  light - because the parameters arrive from a query string, where a name
  nobody registered is an ordinary thing to receive.

  ## What the host owns here

    * the header, in the package's `:header` slot: the document's identity,
      the DOCUMENT switcher, the THEME control and Compile. Undo and redo are
      deliberately **not** here - they are the package's toolbar, and a second
      pair in the header would be two controls over one history;
    * the documents themselves, which live in this process' assigns and
      nowhere else. There is no database in this app yet, so an edit survives
      a document switch and does not survive a reload, and that is the whole
      persistence story until a later campaign gives it one;
    * the compile, which is the host's call to make and the host's findings to
      route back in;
    * the drawer height, per ADR-0005 2A: the package hands each new height
      out through `on_drawer_resize` and reads back whatever the host stored.

  ## The themes are CSS, not the `theme` assign

  `docs/theming.md` in the package offers two seams and they differ in reach
  rather than in power: the `theme` assign for values that are computed - a
  tenant's brand colour out of a database - and a stylesheet for a theme that
  is static, "which is the ordinary case". This app's three themes are static,
  so they are three `[data-theme=...] .sb-editor` blocks in `assets/css/app.css`
  and the page root carries the `data-theme`. Restating them as an inline
  style map would be the same values written twice, and the second copy is the
  one that goes stale.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Compiler
  alias StatifierBlocks.Document
  alias StatifierBlocks.Editor
  alias StatifierBlocks.Finding
  alias StatifierBlocks.Shell
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.Run
  alias StatifierExamplesWeb.Icons
  alias StatifierExamplesWeb.RunFeed

  @default_theme :light

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    parent = self()

    {:ok,
     assign(socket,
       page_title: "Editor",
       palette: Charts.palette(),
       fixtures: Charts.fixtures(),
       documents: %{},
       drawer_height: nil,
       run: nil,
       on_change: fn document -> send(parent, {:document_changed, document}) end,
       on_drawer_resize: fn height -> send(parent, {:drawer_resized, height}) end
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:theme, theme_param(params))
      |> load_document(document_param(socket, params))
      |> compile()
      |> push_run()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("run-start", _params, socket) do
    {:noreply, socket |> start_run() |> push_run()}
  end

  def handle_event("run-stop", _params, socket) do
    {:noreply, socket |> stop_run() |> push_run()}
  end

  def handle_event("run-send", %{"event" => event}, socket) do
    {:noreply, socket |> update(:run, &send_run_event(&1, event)) |> push_run()}
  end

  def handle_event("select-document", %{"doc" => key}, socket) do
    {:noreply, push_patch(socket, to: editor_path(key, socket.assigns.theme))}
  end

  def handle_event("select-theme", %{"theme" => theme}, socket) do
    {:noreply, push_patch(socket, to: editor_path(socket.assigns.fixture.key, theme))}
  end

  def handle_event("compile", _params, socket) do
    {:noreply, compile(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:document_changed, %Document{} = document}, socket) do
    socket =
      socket
      |> assign(:document, document)
      |> update(:documents, &Map.put(&1, socket.assigns.fixture.key, document))
      |> compile()

    {:noreply, socket}
  end

  def handle_info({:drawer_resized, height}, socket) do
    {:noreply, assign(socket, :drawer_height, height)}
  end

  # The one subscriber stream, folded by `Run.absorb/2`. The guard is what
  # keeps a message from a session this page has already replaced out of the
  # run it is showing: a stopped session's last effects can still be in this
  # mailbox when the next Run press has already installed a new one.
  def handle_info({:statifier, session_id, message}, %{assigns: %{run: %Run{} = run}} = socket)
      when run.session_id == session_id do
    {:noreply, socket |> assign(:run, Run.absorb(run, message)) |> push_run()}
  end

  def handle_info({:statifier, _session_id, _message}, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="myapp-page" data-theme={@theme}>
      <.live_component
        module={Editor}
        id="editor"
        document={@document}
        palette={@palette}
        findings={@findings}
        fit={:width}
        icon={&Icons.icon/1}
        invoke_types={Charts.invoke_types()}
        on_change={@on_change}
        on_drawer_resize={@on_drawer_resize}
        drawer_height={@drawer_height}
      >
        <:header>
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

            <form id="theme-switcher" class="myapp-header__control" phx-change="select-theme">
              <label class="myapp-header__label" for="theme-select">Theme</label>
              <select class="myapp-header__select" id="theme-select" name="theme">
                <option :for={theme <- Charts.themes()} value={theme} selected={theme == @theme}>
                  {theme_label(theme)}
                </option>
              </select>
            </form>

            <button class="myapp-header__button" type="button" phx-click="compile">
              Compile
            </button>
            <span class="myapp-header__verdict">{@verdict}</span>

            <button
              :if={is_nil(@run) or @run.status != :running}
              class="myapp-header__button"
              type="button"
              disabled={is_nil(@compiled)}
              phx-click="run-start"
            >
              Run
            </button>

            <button
              :if={@run && @run.status == :running}
              class="myapp-header__button"
              type="button"
              phx-click="run-stop"
            >
              Stop
            </button>

            <span :if={@run} class="myapp-header__verdict" data-run-status={@run.status}>
              {@run.status}
            </span>
          </div>
        </:header>
      </.live_component>
    </div>
    """
  end

  # ------------------------------------------------------------- parameters

  # An unknown key is the first fixture rather than a 404: `?doc=` is a name
  # somebody typed or a link that outlived a rename, and the page it should
  # land on is the one the switcher opens on.
  @spec document_param(Phoenix.LiveView.Socket.t(), map()) :: Charts.Fixture.t()
  defp document_param(socket, params) do
    with key when is_binary(key) <- params["doc"],
         {:ok, fixture} <- Charts.fixture(key) do
      fixture
    else
      _absent_or_unknown -> hd(socket.assigns.fixtures)
    end
  end

  # Existing-atom lookup, never `String.to_atom/1`: the value is attacker
  # controlled and the atom table is not garbage collected.
  @spec theme_param(map()) :: atom()
  defp theme_param(params) do
    Enum.find(Charts.themes(), @default_theme, &(Atom.to_string(&1) == params["theme"]))
  end

  # Named `editor_path` rather than `path`: `Phoenix.VerifiedRoutes` imports a
  # `path/2` macro, and a private function of the same arity does not shadow
  # an imported macro - the macro wins and fails to expand.
  @spec editor_path(String.t(), atom() | String.t()) :: String.t()
  defp editor_path(key, theme), do: ~p"/editor?#{[doc: key, theme: to_string(theme)]}"

  # ---------------------------------------------------------------- editing

  @spec load_document(Phoenix.LiveView.Socket.t(), Charts.Fixture.t()) ::
          Phoenix.LiveView.Socket.t()
  defp load_document(socket, fixture) do
    document = Map.get(socket.assigns.documents, fixture.key, fixture.document)

    socket
    |> end_run_on_switch(fixture)
    |> assign(:fixture, fixture)
    |> assign(:document, document)
    |> assign(:page_title, fixture.name)
  end

  # A run is a run OF a document, so opening a different one ends it. The
  # editor clears its own marks on a document switch for the same reason,
  # and a host that kept the run would be holding marks the editor has
  # already dropped and a feed about a chart nobody is looking at.
  @spec end_run_on_switch(Phoenix.LiveView.Socket.t(), Charts.Fixture.t()) ::
          Phoenix.LiveView.Socket.t()
  defp end_run_on_switch(socket, fixture) do
    if Map.get(socket.assigns, :fixture) == fixture do
      socket
    else
      stop_run(socket)
    end
  end

  # --------------------------------------------------------------- running

  # The Run press. `Run.start/3` links the session to this LiveView, so the
  # run's lifetime is the page's and closing the tab ends it - which is the
  # whole of what "in memory" buys and costs. A press while one is already
  # running replaces it, because two sessions over one document would be two
  # sets of marks for one canvas.
  @spec start_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp start_run(%{assigns: %{compiled: nil}} = socket), do: socket

  defp start_run(socket) do
    socket = stop_run(socket)

    case Run.start(socket.assigns.compiled, socket.assigns.document, self()) do
      {:ok, run} -> assign(socket, :run, run)
      {:error, _reason} -> socket
    end
  end

  @spec stop_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp stop_run(%{assigns: %{run: %Run{} = run}} = socket) do
    Run.stop(run)
    assign(socket, :run, nil)
  end

  defp stop_run(socket), do: socket

  @spec send_run_event(Run.t() | nil, String.t()) :: Run.t() | nil
  defp send_run_event(%Run{status: :running} = run, event), do: Run.send_event(run, event)
  defp send_run_event(run, _event), do: run

  # ------------------------------------------------------------- the seams

  # The three assigns the editor takes from a host that is executing the
  # open document, each read off the same run and each empty when there is
  # none, pushed with `send_update/3`.
  #
  # Pushed and not passed in the component call, and the difference is not
  # stylistic. Both spellings reach the component's `update/3` and both write
  # the assigns; what only the push does is redraw the drawer's panel. The
  # host tab's `content` is a closure the package calls while rendering the
  # panel, and on an ordinary parent re-render that subtree is not re-entered
  # even though the descriptor list it came from changed - the feed stops at
  # whatever row it held when the tab was opened. Pushing is also what the
  # package's own moduledoc shows for a host reacting to a run event it
  # received out of band, which is exactly what a subscriber message is.
  @spec push_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp push_run(socket) do
    run = socket.assigns.run

    send_update(Editor,
      id: "editor",
      active_marks: if(run, do: run.active, else: []),
      invoke_mark: run && run.invoke,
      drawer_tabs: drawer_tabs(run, socket.assigns.document)
    )

    socket
  end

  # One descriptor, whose `content` closes over the run this render is
  # showing. A fresh closure each render is what makes the feed live: the
  # package holds the descriptors as component state and redraws the panel
  # when they change, and a closure over a host assign is only ever read
  # through one it was handed.
  @spec drawer_tabs(Run.t() | nil, Document.t()) :: [map()]
  defp drawer_tabs(run, document) do
    entries = if run, do: Run.entries(run), else: []
    events = Run.event_names(document)

    [
      %{
        id: "runs",
        title: "Runs",
        count: length(entries),
        # `assign/2` and not `Map.merge/2`: the package calls `content` with
        # `%{id:, count:}`, so the run reaches the panel through this
        # closure rather than through the assigns, and a merge would leave
        # change tracking believing nothing inside the panel moved. See
        # `StatifierExamplesWeb.RunFeed`'s moduledoc.
        content: fn assigns -> RunFeed.panel(assign(assigns, run: run, events: events)) end
      }
    ]
  end

  # -------------------------------------------------------------- compiling

  # The strict compile, run on every document the page loads and again on
  # every edit, so the findings pane is never showing an answer to a document
  # that is no longer on the canvas. Compile is still a button because a host
  # whose compile is expensive wants one, and this page is what such a host
  # copies - but the button re-runs a pass that is already current rather than
  # being the only thing that runs it.
  @spec compile(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp compile(socket) do
    result =
      Compiler.compile(socket.assigns.document, socket.assigns.palette,
        known_invoke_types: Charts.invoke_types()
      )

    raw = compiler_findings(result)

    # A finding that names no block has nowhere in the editor to land, so the
    # adapter hands those back separately rather than dropping them.
    {anchored, _refused} = Finding.from_compiler_all(raw)

    socket
    |> assign(:compiled, compiled(result))
    |> assign(:findings, anchored)
    |> assign(:verdict, verdict(socket, anchored))
  end

  # The artifact a run needs and the findings pane does not: the generated
  # bytes to start a session on, and the provenance that turns a state id
  # back into the block to mark. A document that does not compile has none,
  # and `nil` is what makes Run refuse rather than the button being hidden -
  # a Run press on a broken document should say why.
  @spec compiled({:ok, StatifierBlocks.Compiled.t()} | {:error, [Compiler.Finding.t()]}) ::
          StatifierBlocks.Compiled.t() | nil
  defp compiled({:ok, compiled}), do: compiled
  defp compiled({:error, _findings}), do: nil

  @spec compiler_findings({:ok, StatifierBlocks.Compiled.t()} | {:error, [Compiler.Finding.t()]}) ::
          [Compiler.Finding.t()]
  defp compiler_findings({:ok, compiled}), do: compiled.warnings
  defp compiler_findings({:error, findings}), do: findings

  # There is one findings number on this page and it is the package's, which
  # is the whole of what `Editor.findings_count/3` exists to settle: the
  # compiler reports what it found, the editor's view model derives findings
  # of its own on top of whatever the host hands in, and a header rendering
  # the first beside a drawer rendering the second is a page disagreeing with
  # itself about one fact. The seam takes the assigns rather than the
  # component's state precisely so the host can read it before the first
  # render, and the arguments here are the SAME ones the component is given
  # above - a `datamodel` added to that call and not to this one is exactly
  # how the two would come apart again.
  #
  # The wording is the package's too, and read out of it rather than
  # transcribed: `Shell.drawer_title/1` is what titles the drawer's strip and
  # its tab. The package prints a bare integer beside that title, with no
  # singular form and no word for zero, so this prints a bare integer beside
  # the same title. "clean" retired with the count that produced it.
  @spec verdict(Phoenix.LiveView.Socket.t(), [Finding.t()]) :: String.t()
  defp verdict(socket, findings) do
    count =
      Editor.findings_count(socket.assigns.document, socket.assigns.palette, findings: findings)

    "#{Shell.drawer_title(:findings)} #{count}"
  end

  @spec theme_label(atom()) :: String.t()
  defp theme_label(theme) do
    theme |> Atom.to_string() |> String.capitalize()
  end
end
