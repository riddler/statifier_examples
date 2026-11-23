defmodule StatifierExamplesWeb.SignupJourneyLive do
  @moduledoc """
  `/signup-journey` - the walking skeleton with the chart underneath it: one
  durable execution of the signup Path, one screen at a time.

  `StatifierExamplesWeb.SignupScreensLive` is this page's predecessor and they
  are worth reading together. That one draws the same element documents with
  the responses in its own socket and an outcome it only displays; this one
  holds **no authoritative execution state**. Every press goes to
  `StatifierExamples.Signup.Journey` carrying no execution state but the id - the
  outcome pressed and the draft typed travel with it, and nothing else does -
  and `Journey` loads the execution from storage, raises the outcome as an event
  carrying what the form collected, and answers with the screen the execution moved
  to. Reload the page, kill the server, open the same URL on another machine:
  the execution is where it was, because the only thing that had to survive was the
  id in `?execution=`.

  ## What the socket holds, and why none of it is the execution

  Two things, and neither of them is authoritative execution state.

  The **view** `Journey` last answered with - a screen, its resolved nodes,
  the datamodel, the responses, a status. That is a copy of execution state and it
  can be stale between redraws, which is why every press re-reads: the only
  thing `handle_event("outcome", ...)` takes out of it is `execution_id`, so a
  second person pressing the same execution is refused by `Journey` against the
  stored position rather than raced here. The stale copy is read for one
  other purpose, and it is a presentational one:
  `handle_event("response", ...)` re-resolves the screen it holds against the
  draft, so what a keystroke redraws is decided from the view. Nothing is
  sent, nothing is stored, and the next press corrects the drawing from
  storage anyway.

  The **draft**: what a reader has typed and not sent. It is not in the chart
  because it has not been submitted, and a page that persisted every keystroke
  would be writing an execution's datamodel on behalf of a reader who may still press
  Back. It matters for more than the input values - `Journey.resolve/2`
  re-resolves the screen against it, which is what makes the plan screen's two
  plan buttons appear as the seat count is typed.

  ## Why it subscribes

  A durable execution moves without a press. The Path's business arm rests on the
  asynchronous company-details call and an Oban job answers it; the
  reminder and each screen's deadline are stored jobs too. `Durable`
  broadcasts every out-of-band advance on `Durable.topic/1`, so the page
  redraws when the execution moves rather than showing a screen the execution has left.

  ## What the page draws is the view's state

  The page draws by `state`, riddler's word for where the execution is, and
  never by whether the view names a screen. A `"screen"` view is the form. A
  `"waiting"` view says why the execution waits and when to ask again - the
  view's `reason` and `retry_after_ms` - and that the page redraws by itself
  when the call answers. A `"done"` view says the execution finished, names
  the screen it stopped on when it rests on one, and shows what it finished
  with, the view's `result`, when that is not empty. A done execution that
  rests on a screen therefore draws the finished line and not a bare screen
  title with nothing under it.

  ## A press that did not land

  An execution stopped somewhere else - abandoned, or finished - takes no
  more events, and a press that reaches it is refused. `Journey` answers
  that with the last settled position and a `discarded` key, and the
  position is the screen the reader was already on. Drawn alone it would
  read as a press that did nothing, so the page says in words that the
  press was not recorded. The notice is worded for the person filling in
  the form rather than for a developer: the reason `Journey` carries is
  the execution's status, which the line above it already shows.

  ## Another Path, and Back

  `?path=` names a Path other than the signup one, from the short list
  this page runs: `patron_registration_steps`,
  `StatifierExamples.Library.RegistrationSteps`, and the three branch
  library setups `StatifierExamples.Library.Setups` lists, each three
  `myapp.step` blocks. `StatifierExamplesWeb.SettingsLive` starts a setup
  and sends the reader here with its key and the new execution's id.
  The page hands that Path and its screens document to every `Journey`
  call, as the screen editor's Try does, and carries the key in the URL
  beside the execution id. A key the list does not hold is refused on the
  page.

  The Back control is drawn where the view's `back` is `true`, and nowhere
  else: whether Back is offered is statifier_blocks' Back reader's answer,
  which `Journey` puts in riddler's moves, so the page never decides it
  from which Path it runs. The signup Path's reader answers `false` on
  every screen, and that Path keeps its own authored Back button on the
  plan screen. Pressing the control sends riddler's back request,
  `%{"screen" => key, "back" => true}`, to `Journey.back/3`. The draft is
  dropped with the screen it was typed on, and the screen gone back to
  starts its draft from what the chart holds for it, so pressing Continue
  there without retyping sends what the reader gave before. A secret
  question is the exception: its text is never held, so it is typed again.

  ## The branch onboarding: a press goes to the active child

  `?path=branch_onboarding` runs `StatifierExamples.Library.Onboarding`,
  whose setups run as durable child executions of the onboarding
  execution. The URL keeps the onboarding execution's id, and the page
  asks `StatifierExamples.Library.Onboarding.focus/1` which execution to
  present: the active child, read through statifier_persistence's
  active-children reader, while a setup runs, and the onboarding
  execution itself otherwise. Every press and every back request goes to
  that execution with its own options, and the page asks again after each
  press, because the press that finishes a setup moves the onboarding
  execution on to the next setup or to its closing screen. Back inside a
  setup goes back between that setup's steps; the setup's first step
  offers none, so Back never crosses into or out of a setup.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Library.{Onboarding, RegistrationSteps, Setups}
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.SignupElements

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       view: nil,
       draft: %{},
       error: nil,
       topic: nil,
       path: nil,
       opts: [],
       root: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    case path_options(params["path"]) do
      {:ok, opts} ->
        {:noreply,
         socket
         |> assign(path: params["path"], opts: opts, root: params["execution"])
         |> load(params["execution"])}

      :error ->
        {:noreply,
         assign(socket, view: nil, path: nil, opts: [], error: {:unknown_path, params["path"]})}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("start", _params, %{assigns: %{error: {:unknown_path, _key}}} = socket),
    do: {:noreply, socket}

  def handle_event("start", _params, socket) do
    case Journey.start(Durable.new_execution_id(), socket.assigns.opts) do
      {:ok, execution_id} ->
        {:noreply, push_patch(socket, to: journey_url(socket.assigns.path, execution_id))}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason)}
    end
  end

  # A keystroke with no view to re-resolve. The form is drawn only inside the
  # `:if={@view}` block and only under `:if={@view.screen}`, so no reader
  # reaches this - but `Journey.resolve/2` takes a view and both its clauses
  # want a map with a `:screen`, so an event arriving from a page whose execution
  # has since been refused would raise rather than refuse. It takes the
  # refusal the rest of the page already uses, and a refusal already on
  # screen is the more informative one, so it stays.
  def handle_event("response", _params, %{assigns: %{view: nil}} = socket) do
    {:noreply, assign(socket, error: socket.assigns.error || :no_execution)}
  end

  def handle_event("response", %{"responses" => responses}, socket) do
    draft = Map.merge(socket.assigns.draft, responses)

    {:noreply, assign(socket, draft: draft, view: Journey.resolve(socket.assigns.view, draft))}
  end

  # The same refusal, for the same reason: the outcome buttons are drawn inside
  # the `:if={@view}` block, so no reader reaches this - but this clause reads
  # `assigns.view.execution_id`, and an event arriving from a page whose
  # execution has since been refused would raise on a nil view rather than
  # refuse. It takes the refusal the rest of the page already uses, and a
  # refusal already on screen is the more informative one, so it stays.
  def handle_event("outcome", _params, %{assigns: %{view: nil}} = socket) do
    {:noreply, assign(socket, error: socket.assigns.error || :no_execution)}
  end

  def handle_event("outcome", %{"outcome" => outcome}, %{assigns: assigns} = socket) do
    with {:ok, {execution_id, opts}} <- target(socket),
         {:ok, view} <- Journey.submit(execution_id, outcome, assigns.draft, opts) do
      {:noreply, socket |> assign(view: view, draft: %{}, error: nil) |> refocus()}
    else
      {:invalid, view} -> {:noreply, assign(socket, view: view, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
    end
  end

  # Back, from a page whose execution has since been refused: the same
  # refusal as the two clauses above, for the same reason.
  def handle_event("back", _params, %{assigns: %{view: nil}} = socket) do
    {:noreply, assign(socket, error: socket.assigns.error || :no_execution)}
  end

  # The control sends the screen it was drawn on; the page sends riddler's
  # back request for it (the moduledoc's "Another Path, and Back").
  def handle_event("back", %{"screen" => key}, socket) do
    request = %{"screen" => key, "back" => true}

    with {:ok, {execution_id, opts}} <- target(socket),
         {:ok, view} <- Journey.back(execution_id, request, opts) do
      {:noreply, assign(socket, view: view, draft: held(view), error: nil)}
    else
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
    end
  end

  # The execution moved without a press: a job answered the company-details call,
  # or a deadline elapsed. The broadcast carries a reading, and this page
  # deliberately does not use it - it re-resolves from storage instead, so
  # what it draws is the position rather than someone else's view of it.
  @impl Phoenix.LiveView
  def handle_info({:execution_advanced, execution_id, _driven}, socket) do
    {:noreply, load(socket, execution_id)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex max-w-xl flex-col gap-6 p-6">
        <header class="flex items-center justify-between gap-4">
          <h1 class="text-sm font-semibold uppercase tracking-wide opacity-60">Signup journey</h1>
          <button id="start-journey" type="button" class="btn btn-sm" phx-click="start">
            Start a new execution
          </button>
        </header>

        <p :if={@error} id="journey-error" class="alert alert-error text-sm">
          {inspect(@error)}
        </p>

        <p :if={is_nil(@view)} id="no-execution" class="text-base-content/70">
          No execution yet. Press <em>Start a new execution</em>
          and the Path begins at its first screen.
        </p>

        <div :if={@view} class="flex flex-col gap-6">
          <p id="execution-id" class="font-mono text-xs opacity-60">
            execution {@view.execution_id} - {@view.status}
          </p>

          <p
            :if={@root && @view.execution_id != @root}
            id="presented-child"
            class="text-xs opacity-60"
          >
            A setup of the onboarding execution <span class="font-mono">{@root}</span>.
          </p>

          <p
            :if={Map.has_key?(@view, :discarded)}
            id="press-discarded"
            role="status"
            class="alert alert-warning text-sm"
          >
            This signup had already ended, so your last press was not recorded.
            The page shows where it stopped.
          </p>

          <ul
            :if={@view.findings != []}
            id="findings"
            class="alert alert-warning flex-col items-start text-sm"
          >
            <li :for={{key, message} <- @view.findings} id={"finding-#{key}"}>
              {label_for(@view.nodes, key)} {message}
            </li>
          </ul>

          <form
            :if={@view.state == "screen"}
            id="journey-responses"
            phx-change="response"
            class="contents"
          >
            <SignupElements.screen
              title={@view.screen.title}
              nodes={@view.nodes}
              responses={@view.responses}
            />
          </form>

          <button
            :if={@view.state == "screen" and @view.back}
            id="journey-back"
            type="button"
            class="btn btn-ghost btn-sm self-start"
            phx-click="back"
            phx-value-screen={@view.screen.key}
          >
            Back
          </button>

          <div :if={@view.state == "waiting"} id="journey-waiting" class="flex flex-col gap-2">
            <p class="text-base-content/70">
              The execution is between screens - it is resting on a call this app runs as a job.
              This page redraws when the job answers.
            </p>
            <p :if={@view.reason} id="waiting-reason" class="text-sm">
              Waiting on <code>{@view.reason}</code>.
            </p>
            <p :if={@view.retry_after_ms} id="waiting-retry" class="text-sm">
              Ask again in {retry_after(@view.retry_after_ms)}.
            </p>
          </div>

          <div :if={@view.state == "done"} id="journey-done" class="flex flex-col gap-2">
            <p id="journey-finished" class="text-base-content/70">
              The execution finished: {@view.status}.
            </p>
            <p :if={@view.screen} id="journey-stopped-on" class="text-sm">
              It stopped on <em>{@view.screen.title}</em>.
            </p>
            <div :if={@view.result not in [nil, %{}]} class="text-sm">
              What it finished with: <pre id="journey-result" class="whitespace-pre-wrap">{inspect(@view.result, pretty: true)}</pre>
            </div>
          </div>

          <details class="text-xs opacity-70">
            <summary>What the chart has collected</summary>
            <pre id="collected" class="whitespace-pre-wrap">{inspect(@view.responses, pretty: true)}</pre>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Load the execution named in the URL and subscribe to its advances. An execution id
  # nobody stored shows the refusal rather than an empty page, for
  # `StatifierExamplesWeb.EditorLive`'s reason: a page that quietly showed
  # nothing would be hiding the storage guard doing its job.
  @spec load(Phoenix.LiveView.Socket.t(), String.t() | nil) :: Phoenix.LiveView.Socket.t()
  defp load(socket, execution_id) when is_binary(execution_id) do
    with {:ok, {presented, opts}} <- focus(socket, execution_id),
         {:ok, view} <- Journey.current(presented, opts) do
      socket |> watch(execution_id) |> assign(view: view, draft: %{}, error: nil)
    else
      {:error, reason} -> assign(socket, view: nil, error: reason)
    end
  end

  defp load(socket, _absent), do: socket

  # Which execution the page presents for the one `?execution=` names, and
  # the options a call over it takes: the onboarding's focus (the
  # moduledoc's "The branch onboarding"), and the named execution with the
  # page's options for every other Path.
  @spec focus(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:ok, {String.t(), keyword()}} | {:error, term()}
  defp focus(socket, execution_id) do
    if onboarding?(socket),
      do: Onboarding.focus(execution_id),
      else: {:ok, {execution_id, socket.assigns.opts}}
  end

  # Where a press or a back request goes: the onboarding's focus, asked
  # again at the moment of the press, and the execution on the page for
  # every other Path.
  @spec target(Phoenix.LiveView.Socket.t()) :: {:ok, {String.t(), keyword()}} | {:error, term()}
  defp target(%{assigns: %{root: root}} = socket) when is_binary(root),
    do: focus(socket, root)

  defp target(socket), do: {:ok, {socket.assigns.view.execution_id, socket.assigns.opts}}

  # After a press in the onboarding the page presents whatever the focus
  # now is: the press that finishes a setup moves the onboarding on.
  @spec refocus(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refocus(socket) do
    if onboarding?(socket), do: load(socket, socket.assigns.root), else: socket
  end

  @spec onboarding?(Phoenix.LiveView.Socket.t()) :: boolean()
  defp onboarding?(socket), do: socket.assigns.path == Onboarding.key()

  @spec watch(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp watch(socket, execution_id) do
    topic = Durable.topic(execution_id)

    cond do
      socket.assigns.topic == topic ->
        socket

      not connected?(socket) ->
        socket

      true ->
        if socket.assigns.topic do
          Phoenix.PubSub.unsubscribe(StatifierExamples.PubSub, socket.assigns.topic)
        end

        Phoenix.PubSub.subscribe(StatifierExamples.PubSub, topic)

        assign(socket, topic: topic)
    end
  end

  # The options every Journey call takes for the Path `?path=` names: none
  # for the signup Path, the listed Path's otherwise (the moduledoc's
  # "Another Path, and Back"); `:error` for a key no list holds.
  @spec path_options(String.t() | nil) :: {:ok, keyword()} | :error
  defp path_options(nil), do: {:ok, []}

  defp path_options(key) do
    cond do
      key == RegistrationSteps.key() -> {:ok, RegistrationSteps.options()}
      key == Onboarding.key() -> {:ok, Onboarding.options()}
      true -> Setups.options(key)
    end
  end

  @spec journey_url(String.t() | nil, String.t()) :: String.t()
  defp journey_url(nil, execution_id), do: ~p"/signup-journey?#{[execution: execution_id]}"

  defp journey_url(path, execution_id),
    do: ~p"/signup-journey?#{[path: path, execution: execution_id]}"

  # The draft a screen gone back to starts from: each presented question's
  # `value`, which riddler draws from what the chart holds, as the screen
  # editor's Try starts its draft. A secret question is presented with no
  # value, so it starts with none.
  @spec held(Journey.view()) :: %{optional(String.t()) => term()}
  defp held(%{nodes: nodes}),
    do: for(%{"key" => key, "value" => value} <- nodes, into: %{}, do: {key, value})

  # A finding names an element key; a reader knows the question by its
  # label. The nodes are already resolved, so the label is the one on the
  # screen rather than one read a second time out of the document.
  @spec label_for([map()], String.t()) :: String.t()
  defp label_for(nodes, key) do
    case Enum.find(nodes, &(&1["key"] == key)) do
      %{"label" => label} -> label
      _no_label -> key
    end
  end

  # The retry hint in words: whole seconds where it is a whole number of
  # them, milliseconds otherwise.
  @spec retry_after(non_neg_integer()) :: String.t()
  defp retry_after(1_000), do: "1 second"
  defp retry_after(ms) when rem(ms, 1_000) == 0 and ms > 0, do: "#{div(ms, 1_000)} seconds"
  defp retry_after(ms), do: "#{ms} ms"
end
