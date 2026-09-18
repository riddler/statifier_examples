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
    * routing an edit to where the documents live, which since `se-1cl` is
      `StatifierExamples.Documents` rather than this process' assigns. A
      second view over the same documents - `StatifierExamplesWeb.PlanLive` -
      is a second LiveView, so a map held here is one that page cannot see.
      An edit now survives a document switch AND a reload, and still does not
      survive a restart: what this app stores is *executions*, not drafts;
    * the execution id, which is a query parameter for the same reason the other
      two are. A durable execution outlives the process that started it, so the
      page needs a name for the one it is showing, and a name in the URL is
      one a reader can come back to after the server was killed. See
      `StatifierExamples.Charts.Durable`;
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
  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Charts.Execution
  alias StatifierExamples.Charts.Replay
  alias StatifierExamples.Documents
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
       drawer_height: nil,
       run: nil,
       durable: nil,
       execution_topic: nil,
       run_error: nil,
       proposed_step: nil,
       on_change: fn document -> send(parent, {:document_changed, document}) end,
       on_collapse: fn declaration -> send(parent, {:step_proposed, declaration}) end,
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
      |> restore_execution(params["execution"])
      |> push_run()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("run-start", _params, socket) do
    socket = start_run(socket)

    {:noreply, socket |> push_run() |> patch_to_run()}
  end

  def handle_event("run-stop", _params, socket) do
    socket = stop_run(socket)

    {:noreply, socket |> push_run() |> patch_to_run()}
  end

  def handle_event("run-send", %{"event" => event}, socket) do
    {:noreply, socket |> send_run_event(event) |> push_run()}
  end

  def handle_event("select-document", %{"doc" => key}, socket) do
    {:noreply, push_patch(socket, to: editor_path(key, socket.assigns.theme, nil))}
  end

  def handle_event("select-theme", %{"theme" => theme}, socket) do
    {:noreply,
     push_patch(socket, to: editor_path(socket.assigns.fixture.key, theme, execution_id(socket)))}
  end

  def handle_event("compile", _params, socket) do
    {:noreply, compile(socket)}
  end

  @impl Phoenix.LiveView
  def handle_info({:document_changed, %Document{} = document}, socket) do
    :ok = Documents.put(socket.assigns.fixture.key, document)

    socket =
      socket
      |> assign(:document, document)
      |> compile()

    {:noreply, socket}
  end

  # The other seam out of the editor, and the one that is not a change.
  # "Save as a step" hands this page the declaration standing for the
  # arrangement the author selected - `StatifierBlocks.Composite.Collapse`'s
  # proposal, sb ADR-0005 part (iii) as amended 2026-09-07, clauses `15E` to
  # `20E`. The document is NOT edited by it and the package persists
  # nothing, so nothing is written to `Documents` here and no recompile is
  # run: what a host does with the map - which table, which tenant, whether
  # it is stored at all - is the host's, and what this reference embedder
  # does is show that it arrived.
  #
  # It stays in the socket rather than going anywhere, deliberately.
  # Naming the type is the host's act (`15E`) and storing it is `R5`'s;
  # neither is what this app is a reference for, and a demo that quietly
  # minted a type name would be demonstrating the one thing the record
  # refuses.
  def handle_info({:step_proposed, declaration}, socket) do
    {:noreply, assign(socket, :proposed_step, declaration)}
  end

  def handle_info({:drawer_resized, height}, socket) do
    {:noreply, assign(socket, :drawer_height, height)}
  end

  # A durable execution that moved without this page pressing anything: a
  # reminder timer fired in an Oban job, drove the stored execution, and
  # announced it on the execution's topic (`StatifierExamples.Charts.Durable`'s
  # `deliver/2`). The page is one of possibly several showing this execution and
  # is not the driver, so it adopts the reading the drive produced rather
  # than deriving a second one - which is also why the feed opens with the
  # resume row: the reading came from storage, exactly as it does after a
  # reload, and this app would rather show that seam than hide it.
  #
  # The id check is not paranoia. A page that patched to a different execution
  # between the broadcast and its delivery is still subscribed for one
  # more message.
  def handle_info(
        {:execution_advanced, execution_id, {%Durable{} = durable, %Execution{} = run}},
        socket
      ) do
    if execution_id(socket) == execution_id do
      {:noreply, socket |> adopt({:ok, {durable, run}}) |> push_run()}
    else
      {:noreply, socket}
    end
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
        invoke_types={Charts.invoke_types()}
        datamodel={@fixture.datamodel}
        declare={@fixture.declare}
        compile_options={compile_options(@fixture)}
        on_change={@on_change}
        on_collapse={@on_collapse}
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

            <button
              :for={event <- Execution.event_names(@document)}
              class="myapp-header__button myapp-header__button--event"
              type="button"
              disabled={is_nil(@run) or @run.status != :running}
              phx-click="run-send"
              phx-value-event={event}
            >
              {event}
            </button>

            <span :if={@run} class="myapp-header__verdict" data-run-status={@run.status}>
              {@run.status}
            </span>

            <span :if={@run_error} class="myapp-header__verdict" data-run-error={@run_error}>
              {@run_error}
            </span>

            <span
              :if={@proposed_step}
              class="myapp-header__verdict"
              data-proposed-step={Enum.map_join(@proposed_step["params"], ",", & &1["key"])}
            >
              Step proposed: {length(@proposed_step["params"])} values
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
  @spec editor_path(String.t(), atom() | String.t(), String.t() | nil) :: String.t()
  defp editor_path(key, theme, nil), do: ~p"/editor?#{[doc: key, theme: to_string(theme)]}"

  defp editor_path(key, theme, execution_id),
    do: ~p"/editor?#{[doc: key, theme: to_string(theme), execution: execution_id]}"

  # ---------------------------------------------------------------- editing

  @spec load_document(Phoenix.LiveView.Socket.t(), Charts.Fixture.t()) ::
          Phoenix.LiveView.Socket.t()
  defp load_document(socket, fixture) do
    document = Documents.get(fixture.key, fixture.document)

    socket
    |> end_run_on_switch(fixture)
    |> assign(:fixture, fixture)
    |> assign(:document, document)
    |> assign(:page_title, fixture.name)
  end

  # An execution is an execution OF a document, so opening a different one stops showing
  # it. The editor clears its own marks on a document switch for the same
  # reason, and a host that kept the execution would be holding marks the editor
  # has already dropped and a feed about a chart nobody is looking at.
  #
  # Stops *showing*, not stops: the execution is durable, so forgetting it here
  # loses a page's worth of assigns and nothing else. Coming back to the
  # same URL picks it up again, which is the whole point of the execution id
  # being in the URL.
  @spec end_run_on_switch(Phoenix.LiveView.Socket.t(), Charts.Fixture.t()) ::
          Phoenix.LiveView.Socket.t()
  defp end_run_on_switch(socket, fixture) do
    if Map.get(socket.assigns, :fixture) == fixture do
      socket
    else
      forget_run(socket)
    end
  end

  # --------------------------------------------------------------- running

  # The Run press. Every execution this page starts is durable: the position is
  # in SQLite after every step, the execution id goes into the URL, and the page
  # holds no more of the execution than a reader is looking at. Pressing Run
  # while one is showing starts a second execution rather than replacing a
  # process, because there is no process - the one already stored keeps
  # whatever it had reached, and the URL now names the new one.
  @spec start_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp start_run(%{assigns: %{compiled: nil}} = socket), do: socket

  defp start_run(socket) do
    socket = forget_run(socket)
    execution_id = Durable.new_execution_id()

    adopt(
      socket,
      Durable.start(
        socket.assigns.compiled,
        socket.assigns.document,
        execution_id,
        socket.assigns.fixture.key
      )
    )
  end

  # The Stop press: the host's own terminal transition (ADR-0004 decision
  # 6), so the stored record says a host stopped this execution rather than the
  # chart finishing it.
  @spec stop_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp stop_run(%{assigns: %{durable: %Durable{} = durable}} = socket) do
    :ok = Durable.abandon(durable)

    forget_run(socket)
  end

  defp stop_run(socket), do: forget_run(socket)

  @spec forget_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp forget_run(socket) do
    socket
    |> watch_run(nil)
    |> assign(:run, nil)
    |> assign(:durable, nil)
    |> assign(:run_error, nil)
  end

  # Which execution's out-of-band advances this page is listening for. A page
  # subscribes because a durable execution can move without it: the wizard's
  # reminder fires in a job, not in a click, and a feed that only ever
  # redrew on a press would sit there stale while the execution went on without
  # it.
  #
  # Keyed on the topic rather than on "have I subscribed", so switching
  # documents or starting a second execution leaves exactly one subscription
  # behind and no page ever receives another execution's advances.
  @spec watch_run(Phoenix.LiveView.Socket.t(), String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp watch_run(socket, execution_id) do
    current = socket.assigns[:execution_topic]
    next = execution_id && Durable.topic(execution_id)

    if current == next do
      socket
    else
      if current, do: Phoenix.PubSub.unsubscribe(StatifierExamples.PubSub, current)

      if not is_nil(next) and connected?(socket) do
        Phoenix.PubSub.subscribe(StatifierExamples.PubSub, next)
      end

      assign(socket, :execution_topic, next)
    end
  end

  @spec send_run_event(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp send_run_event(
         %{assigns: %{durable: %Durable{} = durable, run: %Execution{status: :running} = run}} =
           socket,
         event
       ) do
    adopt(socket, Durable.send_event(durable, run, event))
  end

  defp send_run_event(socket, _event), do: socket

  # Picking a stored execution back up, which is what a reload after a `kill -9`
  # is. Three cases and they are all ordinary: the page is already showing
  # this execution (a patch this page itself pushed), the document does not
  # compile so there is no machine to resume onto, or the execution is genuinely
  # somewhere in storage and this is the first the process has heard of it.
  #
  # The third case resumes by execution id alone (`Durable.resume/1`) rather than
  # with the compile on this page's canvas, and that is what lets the page
  # open a **durable subchart child**. A child execution's stored identity is
  # keyed on the child compile of its document and the canvas holds the root
  # compile of the same document, so resuming with this page's own would be
  # refused on identity - correctly and uselessly. Which recipe a stored execution
  # wants is a fact about the record, and `Durable.resume/1` reads it there.
  @spec restore_execution(Phoenix.LiveView.Socket.t(), String.t() | nil) ::
          Phoenix.LiveView.Socket.t()
  defp restore_execution(socket, execution_id) when is_binary(execution_id) do
    cond do
      execution_id(socket) == execution_id ->
        socket

      is_nil(socket.assigns.compiled) ->
        socket

      true ->
        adopt(socket, resumed(execution_id))
    end
  end

  defp restore_execution(socket, _absent), do: socket

  @spec resumed(String.t()) :: {:ok, Durable.driven()} | {:error, term()}
  defp resumed(execution_id) do
    case Durable.resume(execution_id) do
      {:ok, {driven, _document}} -> {:ok, driven}
      {:error, _reason} = error -> error
    end
  end

  # A refusal is shown rather than swallowed. `{:identity_mismatch, _, _}`
  # is the one a reader will actually meet - it means the document was
  # edited after the execution started - and a page that quietly showed no execution
  # would be hiding the guard doing its job.
  @spec adopt(
          Phoenix.LiveView.Socket.t(),
          {:ok, Durable.driven()} | {:discarded, term()} | {:error, term()}
        ) :: Phoenix.LiveView.Socket.t()
  defp adopt(socket, {:ok, {durable, run}}) do
    socket
    |> watch_run(durable.execution_id)
    |> assign(:durable, durable)
    |> assign(:run, run)
    |> assign(:run_error, nil)
  end

  # A send the chart would not take. The page keeps the execution it is
  # showing - the driver's position is still what storage holds, and
  # forgetting it would blank a reading the reader can still read - and adds
  # why the press did nothing. `{:error, _}` below forgets instead, because
  # there the execution itself could not be loaded.
  #
  # It RE-RESUMES rather than keeping the assigns untouched, and that is the
  # whole of it: the reason a send is refused is that the execution went
  # terminal somewhere else, so the `running` this socket last heard is
  # precisely the stale fact. Nothing broadcasts an out-of-band abandon, so
  # a page that kept its assigns would sit on `running` for good - and
  # because `send_run_event/2` guards on `status: :running`, every later
  # press would re-send and be discarded again. One storage read on a path
  # that is already the rare one buys the header the truth.
  #
  # The re-resume goes through this function's own `{:ok, _}` clause, which
  # clears `run_error`, so the discard message is assigned after it rather
  # than before.
  defp adopt(socket, {:discarded, reason}) do
    socket
    |> readopt(execution_id(socket))
    |> assign(:run_error, "event discarded: #{inspect(reason)}")
  end

  defp adopt(socket, {:error, reason}) do
    socket
    |> forget_run()
    |> assign(:run_error, "execution refused: #{inspect(reason)}")
  end

  # The re-read a discard needs, and the one place a failed re-read is not
  # worth reporting: the page already has a position to show and a reason to
  # show beside it, so a storage refusal on a read nobody asked for leaves
  # the reading the page had rather than blanking it. `adopt/2`'s
  # `{:error, _}` clause forgets the execution, which is right when a reader
  # asked for one and wrong here.
  @spec readopt(Phoenix.LiveView.Socket.t(), String.t() | nil) :: Phoenix.LiveView.Socket.t()
  defp readopt(socket, execution_id) when is_binary(execution_id) do
    case resumed(execution_id) do
      {:ok, driven} -> adopt(socket, {:ok, driven})
      {:error, _reason} -> socket
    end
  end

  defp readopt(socket, _absent), do: socket

  @spec execution_id(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  defp execution_id(%{assigns: %{durable: %Durable{execution_id: execution_id}}}),
    do: execution_id

  defp execution_id(_socket), do: nil

  # The URL is where the execution id lives, so every press that changes which
  # execution the page is showing ends in a patch. Pressing Run and then reading
  # the address bar is how a reader gets a link they can come back to.
  @spec patch_to_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp patch_to_run(socket) do
    push_patch(socket,
      to: editor_path(socket.assigns.fixture.key, socket.assigns.theme, execution_id(socket))
    )
  end

  # ------------------------------------------------------------- the seams

  # The one assign the editor takes from a host that is executing the open
  # document: the execution itself, as the `StatifierUI.Live.State` the package's
  # Run pane reads, pushed with `send_update/3`.
  #
  # This used to be three assigns and a drawer tab, and what replaced them
  # is one reading rather than a smaller version of the same idea. The page
  # painted `active_marks` and `invoke_mark` from its own in-memory
  # `StatifierExamples.Charts.Execution`, which knew only what the current
  # process had watched happen; and it rendered its own event feed into a
  # host drawer tab, which a resumed execution opened with a single row saying it
  # had been resumed, because effects are not stored. Seating the execution
  # itself moves both readings onto the stored log: the pane derives the
  # marks from the execution's own selected macrostep against the provenance the
  # editor recompiles (which is what `compile_options` in `render/1` is
  # for), so scrubbing back moves them, and the log is the execution's whole
  # history rather than this process's share of it.
  #
  # Pushed and not passed in the component call, because that is the door
  # the package documents for a host reacting to an execution event it received
  # out of band - which is exactly what a subscriber message is - and
  # because `run` is held as editor state behind a `Map.has_key?/2` guard,
  # so a parent re-render that does not name the key leaves it alone.
  #
  # An execution that cannot be read back is not a blank pane: `run_error` carries
  # the refusal to the header, beside the one a refused resume writes,
  # because a page showing no execution for an execution that exists is the one reading
  # this seam must not produce.
  @spec push_run(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp push_run(socket) do
    case replayed(socket) do
      {:ok, state} ->
        send_update(Editor, id: "editor", run: state)
        socket

      :none ->
        send_update(Editor, id: "editor", run: nil)
        socket

      {:error, reason} ->
        send_update(Editor, id: "editor", run: nil)
        assign(socket, :run_error, inspect(reason))
    end
  end

  # The stored execution, read back through the input log. `:none` when the page
  # is showing no execution at all, or no compiled chart to read one over - both
  # of which are ordinary states and neither of which is an error.
  @spec replayed(Phoenix.LiveView.Socket.t()) ::
          {:ok, StatifierUI.Live.State.t()} | :none | {:error, term()}
  defp replayed(%{assigns: %{durable: nil}}), do: :none
  defp replayed(%{assigns: %{compiled: nil}}), do: :none

  defp replayed(socket) do
    Replay.state(execution_id(socket), socket.assigns.compiled)
  end

  # The rest of the option list this page compiles with, for the editor's
  # own provenance recompile - the one the Run pane resolves an execution's state
  # ids through. It is assembled here from the same three values
  # `StatifierExamples.Charts.Durable.compile/3` passes rather than read
  # back off `@compiled`: the pane's marks are in the right places only
  # while the chart the editor recompiles is byte-for-byte the one the execution
  # executed, and `terminate: true` in particular is what puts the
  # top-level finals in it that a completed execution's last configuration sits
  # on.
  #
  # `:declare` is not in the list even though the execution compiles with it: the
  # package takes that key from the `declare` assign whatever this list
  # says, which is why the assign is passed beside it in `render/1` and why
  # the two cannot disagree.
  @spec compile_options(map()) :: keyword()
  defp compile_options(fixture) do
    [
      terminate: true,
      known_invoke_types: Charts.invoke_types(),
      datamodel: fixture.datamodel
    ]
  end

  # -------------------------------------------------------------- compiling

  # The strict compile, run on every document the page loads and again on
  # every edit, so the findings pane is never showing an answer to a document
  # that is no longer on the canvas. Compile is still a button because a host
  # whose compile is expensive wants one, and this page is what such a host
  # copies - but the button re-runs a pass that is already current rather than
  # being the only thing that runs it.
  #
  # `:declare` comes off the FIXTURE rather than off the document on the
  # canvas, and it still has to, though no longer for the reason it once
  # did. The document declares the roots its own guards read - sb ADR-0001
  # decision 11's top-level `datamodel` key, which every fixture this app
  # ships uses - and the compiler reads that off the document it is handed.
  # `:declare` is the other surface: what a *deployment* adds over the
  # document, leading the emitted `<datamodel>` where both name a root.
  # This app adds nothing, so every fixture's list is empty (see
  # `StatifierExamples.Charts.Fixture`), and the list still belongs to the
  # fixture because what a deployment adds is a fact about that pairing
  # rather than about the tree an author edits. An edit on the canvas
  # changes the document, never what the host declares over it.
  #
  # The rest of the recipe - `terminate: true`, the palette, the known
  # invoke types - is `StatifierExamples.Charts.Durable.compile/3`'s and
  # deliberately not spelled here. Those options change the generated
  # bytes, so they change the content hash chart identity is keyed on, and
  # a page holding its own copy of them is a page that can silently
  # disagree with the background job that rebuilds the same chart when a
  # timer fires. There is one call; that moduledoc has the reasoning.
  @spec compile(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp compile(socket) do
    result =
      Durable.compile(
        socket.assigns.document,
        socket.assigns.fixture.declare,
        socket.assigns.fixture.datamodel
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

  # The artifact an execution needs and the findings pane does not: the generated
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
      Editor.findings_count(socket.assigns.document, socket.assigns.palette,
        findings: findings,
        datamodel: socket.assigns.fixture.datamodel
      )

    "#{Shell.drawer_title(:findings)} #{count}"
  end

  @spec theme_label(atom()) :: String.t()
  defp theme_label(theme) do
    theme |> Atom.to_string() |> String.capitalize()
  end
end
