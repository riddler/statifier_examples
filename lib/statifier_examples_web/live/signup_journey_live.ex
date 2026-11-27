defmodule StatifierExamplesWeb.SignupJourneyLive do
  @moduledoc """
  `/signup-journey` - the walking skeleton with the chart underneath it: one
  durable execution of the signup Path, one screen at a time.

  `StatifierExamplesWeb.SignupScreensLive` is this page's predecessor and they
  are worth reading together. That one draws the same element documents with
  the responses in its own socket and an outcome it only displays; this one
  holds **no authoritative execution state**. Every press goes to
  `StatifierExamples.Signup.Journey` carrying no execution state but the id - the
  outcome pressed and the responses typed travel with it, and nothing else
  does - and `Journey` loads the execution from storage, raises the outcome as
  an event carrying what the form collected, and answers with the screen the
  execution moved to. Reload the page, kill the server, open the same URL on
  another machine: the execution is where it was, because the only thing that
  had to survive was the id in `?execution=`.

  ## The screen is riddler_live_view's

  The screen itself - the form, its questions and buttons, the findings of
  a refused press, the Back control - is drawn by `RiddlerLiveView.Journey`,
  which draws what `Riddler.Journey.present/3` answers and hands back what
  the reader submits. `StatifierExamplesWeb.JourneyHost` is its host: the
  component asks it where the Journey is, hands it each submit and back
  request, and asks it to present the screen again with what the reader
  has typed and not sent, which is what makes the plan screen's two plan
  buttons appear as the seat count is typed. The component types the
  form's values the way riddler validates them: a boolean question's
  posting becomes `true` or `false`, and a choice question under `"many"`
  with nothing ticked sends `[]`. This app's own per-kind renderer,
  `StatifierExamplesWeb.SignupElements`, no longer draws this page; the
  screens page and the screen editor's preview still use it.

  The access module the component asks before it shows or steps a Journey
  is `StatifierExamplesWeb.JourneyAccess`, which is interim: every Journey
  here is answered under one fixed scope (`JourneyHost.scope/0`).

  ## What the socket holds, and why none of it is the execution

  The **view** `Journey` last answered with - a screen, the datamodel, the
  responses, a status. It is a copy of execution state and it can be stale
  between redraws; the page draws from it only what it shows beside the
  component: the execution id, a press that did not land, why an execution
  waits and what it finished with. It is loaded with the page, and the host
  sends the page each view a press or a back request steps to (the host's
  "Telling the page"). No press reads it: the host loads the execution from
  storage on every call, so a second person pressing the same execution is
  refused by `Journey` against the stored position rather than raced here.

  What a reader has typed and not sent is in the browser's form and in the
  screen the component last drew, never in this page's socket.

  ## Why it subscribes

  A durable execution moves without a press. The Path's business arm rests on the
  asynchronous company-details call and an Oban job answers it; the
  reminder and each screen's deadline are stored jobs too. `Durable`
  broadcasts every out-of-band advance on `Durable.topic/1`, so the page
  redraws when the execution moves rather than showing a screen the execution has left,
  and asks the component to ask the host again.

  ## What the page draws is the view's state

  The page draws by `state`, riddler's word for where the execution is, and
  never by whether the view names a screen. A `"screen"` view is the form. A
  `"waiting"` view says why the execution waits and when to ask again - the
  view's `reason` and `retry_after_ms` - and that the page redraws by itself
  when the call answers. A `"done"` view says the execution finished, names
  the screen it stopped on when it rests on one, and shows what it finished
  with: the named fields of the create-account receipt `receipt/1` lists,
  never the whole receipt, so a field added to the receipt later is not
  drawn until it is listed here. A done execution that rests on a screen
  therefore draws the finished line and not a bare screen title with nothing
  under it.

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
  this page runs (`StatifierExamplesWeb.JourneyHost.path_options/1`):
  `patron_registration_steps`, `StatifierExamples.Library.RegistrationSteps`;
  `patron_registration`, the patron registration the screen editor's
  document authors, run on the Path its Try derives, with its boolean and
  many-choice questions; and the three branch library setups
  `StatifierExamples.Library.Setups` lists, each three `myapp.step` blocks.
  `StatifierExamplesWeb.SettingsLive` starts a setup
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
  plan screen. The component's Back control sends riddler's back request,
  `%{"screen" => key, "back" => true}`, which the host hands to
  `Journey.back/3`. What was typed on the screen left is dropped with it,
  and the screen gone back to is drawn with what the chart holds for it,
  so pressing Continue there without retyping sends what the reader gave
  before. A secret question is the exception: its text is never held, so
  it is typed again.

  ## The branch onboarding: a press goes to the active child

  `?path=branch_onboarding` runs `StatifierExamples.Library.Onboarding`,
  whose setups run as durable child executions of the onboarding
  execution. The URL keeps the onboarding execution's id, and the page
  asks `StatifierExamples.Library.Onboarding.focus/1` which execution to
  present: the active child, read through statifier_persistence's
  active-children reader, while a setup runs, and the onboarding
  execution itself otherwise. The host asks the same on every call, so
  every press and every back request goes to that execution with its own
  options, and it asks again after each press, because the press that
  finishes a setup moves the onboarding execution on to the next setup or
  to its closing screen. Back inside a
  setup goes back between that setup's steps; the setup's first step
  offers none, so Back never crosses into or out of a setup.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.{JourneyAccess, JourneyHost}

  # The component's id, which is also the prefix of every id its markup
  # derives.
  @component "journey"

  # The receipt fields the done section draws, in order, each with its
  # label (the moduledoc's "What the page draws is the view's state").
  @receipt_fields [{"email", "Account for"}, {"collected", "Responses collected"}]

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       view: nil,
       error: nil,
       topic: nil,
       path: nil,
       opts: [],
       root: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    case JourneyHost.path_options(params["path"]) do
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

  # A change, a submit or a back request that reached the page rather than
  # the component. The component's form and Back control target the
  # component, and it is drawn only inside the `:if={@view}` block, so no
  # reader reaches this; an event sent to the page anyway steps nothing. A
  # page with no execution says so, and a refusal already on screen is the
  # more informative one, so it stays.
  def handle_event(event, _params, %{assigns: %{view: nil}} = socket)
      when event in ["change", "submit", "back"] do
    {:noreply, assign(socket, error: socket.assigns.error || :no_execution)}
  end

  def handle_event(event, _params, socket) when event in ["change", "submit", "back"],
    do: {:noreply, socket}

  # The execution moved without a press: a job answered the company-details call,
  # or a deadline elapsed. The broadcast carries a reading, and this page
  # deliberately does not use it - it re-resolves from storage instead, so
  # what it draws is the position rather than someone else's view of it -
  # and asks the component to ask the host again.
  @impl Phoenix.LiveView
  def handle_info({:execution_advanced, execution_id, _driven}, socket) do
    socket = load(socket, execution_id)

    if socket.assigns.view,
      do: send_update(RiddlerLiveView.Journey, id: @component, refresh: true)

    {:noreply, socket}
  end

  # The host's word after a press or a back request (its moduledoc's
  # "Telling the page"): the view the Journey stepped to, or why it did not.
  def handle_info({JourneyHost, {:view, view}}, socket),
    do: {:noreply, assign(socket, view: view, error: nil)}

  def handle_info({JourneyHost, {:error, reason}}, socket),
    do: {:noreply, assign(socket, error: reason)}

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns = assign(assigns, component: @component)

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

          <.live_component
            module={RiddlerLiveView.Journey}
            id={@component}
            journey={JourneyHost.journey(@path, @root)}
            host={JourneyHost}
            access={JourneyAccess}
            re_present={&JourneyHost.re_present/2}
            waiting_text="The execution is between screens - it is resting on a call this app runs as a job. This page redraws when the job answers."
            done_text="Nothing more to fill in."
            class="flex flex-col gap-4"
          />

          <div :if={@view.state == "waiting"} id="journey-waiting" class="flex flex-col gap-2">
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
            <div :if={receipt(@view.result) != []} class="text-sm">
              What it finished with:
              <dl id="journey-result" class="grid grid-cols-2 gap-1">
                <%= for {label, value} <- receipt(@view.result) do %>
                  <dt class="opacity-70">{label}</dt>
                  <dd>{value}</dd>
                <% end %>
              </dl>
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

  @doc """
  What the done section draws of a done view's `result`: the
  create-account receipt's fields this page names, each with its label, in
  the page's order, and nothing else the receipt carries. `[]` for a result
  with no receipt, an execution that stopped before the call answered.

      iex> StatifierExamplesWeb.SignupJourneyLive.receipt(%{
      ...>   "created" => %{"created" => true, "email" => "ada@example.com", "collected" => 4}
      ...> })
      [{"Account for", "ada@example.com"}, {"Responses collected", "4"}]
      iex> StatifierExamplesWeb.SignupJourneyLive.receipt(%{})
      []
  """
  @spec receipt(map() | nil) :: [{String.t(), String.t()}]
  def receipt(%{"created" => created}) when is_map(created) do
    for {field, label} <- @receipt_fields,
        Map.has_key?(created, field),
        do: {label, to_string(Map.fetch!(created, field))}
  end

  def receipt(_result), do: []

  # Load the execution named in the URL and subscribe to its advances. An execution id
  # nobody stored shows the refusal rather than an empty page, for
  # `StatifierExamplesWeb.EditorLive`'s reason: a page that quietly showed
  # nothing would be hiding the storage guard doing its job.
  @spec load(Phoenix.LiveView.Socket.t(), String.t() | nil) :: Phoenix.LiveView.Socket.t()
  defp load(socket, execution_id) when is_binary(execution_id) do
    %{path: path, opts: opts} = socket.assigns

    with {:ok, {presented, presented_opts}} <- JourneyHost.focus(path, execution_id, opts),
         {:ok, view} <- Journey.current(presented, presented_opts) do
      socket |> watch(execution_id) |> assign(view: view, error: nil)
    else
      {:error, reason} -> assign(socket, view: nil, error: reason)
    end
  end

  # A URL that names no execution draws none: the component is drawn only
  # for the execution the URL names.
  defp load(socket, _absent), do: assign(socket, view: nil)

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

  @spec journey_url(String.t() | nil, String.t()) :: String.t()
  defp journey_url(nil, execution_id), do: ~p"/signup-journey?#{[execution: execution_id]}"

  defp journey_url(path, execution_id),
    do: ~p"/signup-journey?#{[path: path, execution: execution_id]}"

  # The retry hint in words: whole seconds where it is a whole number of
  # them, milliseconds otherwise.
  @spec retry_after(non_neg_integer()) :: String.t()
  defp retry_after(1_000), do: "1 second"
  defp retry_after(ms) when rem(ms, 1_000) == 0 and ms > 0, do: "#{div(ms, 1_000)} seconds"
  defp retry_after(ms), do: "#{ms} ms"
end
