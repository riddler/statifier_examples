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
  alias StatifierExamplesWeb.Icons

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

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
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
    |> assign(:fixture, fixture)
    |> assign(:document, document)
    |> assign(:page_title, fixture.name)
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
    raw =
      socket.assigns.document
      |> Compiler.compile(socket.assigns.palette, known_invoke_types: Charts.invoke_types())
      |> compiler_findings()

    # A finding that names no block has nowhere in the editor to land, so the
    # adapter hands those back separately rather than dropping them.
    {anchored, _refused} = Finding.from_compiler_all(raw)

    socket
    |> assign(:findings, anchored)
    |> assign(:verdict, verdict(socket, anchored))
  end

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
