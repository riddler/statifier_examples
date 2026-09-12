defmodule StatifierExamplesWeb.SignupJourneyLive do
  @moduledoc """
  `/signup-journey` - the walking skeleton with the chart underneath it: one
  durable run of the signup Path, one screen at a time.

  `StatifierExamplesWeb.SignupScreensLive` is this page's predecessor and they
  are worth reading together. That one draws the same element documents with
  the answers in its own socket and an outcome it only displays; this one
  holds **no authoritative run state**. Every press goes to
  `StatifierExamples.Signup.Journey` with a run id and nothing else, and
  `Journey` loads the run from storage, raises the outcome as an event
  carrying what the form collected, and answers with the screen the run moved
  to. Reload the page, kill the server, open the same URL on another machine:
  the run is where it was, because the only thing that had to survive was the
  id in `?run=`.

  ## What the socket holds, and why none of it is the run

  Two things, and neither is decided from.

  The **view** `Journey` last answered with - a screen, its resolved nodes,
  the datamodel, the answers, a status. That is a copy of run state and it
  can be stale between redraws, which is why every press re-reads: the only
  thing `handle_event("outcome", ...)` takes out of it is `run_id`, so a
  second person pressing the same run is refused by `Journey` against the
  stored position rather than raced here.

  The **draft**: what a reader has typed and not sent. It is not in the chart
  because it has not been submitted, and a page that persisted every keystroke
  would be writing a run's datamodel on behalf of a reader who may still press
  Back. It matters for more than the input values - `Journey.resolve/2`
  re-resolves the screen against it, which is what makes the plan screen's two
  plan buttons appear as the seat count is typed.

  ## Why it subscribes

  A durable run moves without a press. The Path's business arm rests on the
  asynchronous company-details call and an Oban job answers it; the
  reminder and each screen's deadline are stored jobs too. `Durable`
  broadcasts every out-of-band advance on `Durable.topic/1`, so the page
  redraws when the run moves rather than showing a screen the run has left.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierExamples.Charts.Durable
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.SignupElements

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, assign(socket, view: nil, draft: %{}, error: nil, topic: nil)}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    {:noreply, load(socket, params["run"])}
  end

  @impl Phoenix.LiveView
  def handle_event("start", _params, socket) do
    case Journey.start() do
      {:ok, run_id} -> {:noreply, push_patch(socket, to: ~p"/signup-journey?run=#{run_id}")}
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
    end
  end

  def handle_event("answer", %{"answers" => answers}, socket) do
    draft = Map.merge(socket.assigns.draft, answers)

    {:noreply, assign(socket, draft: draft, view: Journey.resolve(socket.assigns.view, draft))}
  end

  def handle_event("outcome", %{"outcome" => outcome}, %{assigns: assigns} = socket) do
    case Journey.submit(assigns.view.run_id, outcome, assigns.draft) do
      {:ok, view} -> {:noreply, assign(socket, view: view, draft: %{}, error: nil)}
      {:invalid, view} -> {:noreply, assign(socket, view: view, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
    end
  end

  # The run moved without a press: a job answered the company-details call,
  # or a deadline elapsed. The broadcast carries a reading, and this page
  # deliberately does not use it - it re-resolves from storage instead, so
  # what it draws is the position rather than someone else's view of it.
  @impl Phoenix.LiveView
  def handle_info({:run_advanced, run_id, _driven}, socket) do
    {:noreply, load(socket, run_id)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto flex max-w-xl flex-col gap-6 p-6">
        <header class="flex items-center justify-between gap-4">
          <h1 class="text-sm font-semibold uppercase tracking-wide opacity-60">Signup journey</h1>
          <button id="start-journey" type="button" class="btn btn-sm" phx-click="start">
            Start a new run
          </button>
        </header>

        <p :if={@error} id="journey-error" class="alert alert-error text-sm">
          {inspect(@error)}
        </p>

        <p :if={is_nil(@view)} id="no-run" class="text-base-content/70">
          No run yet. Press <em>Start a new run</em> and the Path begins at its first screen.
        </p>

        <div :if={@view} class="flex flex-col gap-6">
          <p id="run-id" class="font-mono text-xs opacity-60">
            run {@view.run_id} - {@view.status}
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

          <form :if={@view.screen} id="journey-answers" phx-change="answer" class="contents">
            <SignupElements.screen
              title={@view.screen.title}
              nodes={@view.nodes}
              answers={@view.answers}
            />
          </form>

          <p :if={is_nil(@view.screen)} id="no-screen" class="text-base-content/70">
            {off_screen(@view.status)}
          </p>

          <details class="text-xs opacity-70">
            <summary>What the chart has collected</summary>
            <pre id="collected" class="whitespace-pre-wrap">{inspect(@view.answers, pretty: true)}</pre>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Load the run named in the URL and subscribe to its advances. A run id
  # nobody stored shows the refusal rather than an empty page, for
  # `StatifierExamplesWeb.EditorLive`'s reason: a page that quietly showed
  # nothing would be hiding the storage guard doing its job.
  @spec load(Phoenix.LiveView.Socket.t(), String.t() | nil) :: Phoenix.LiveView.Socket.t()
  defp load(socket, run_id) when is_binary(run_id) do
    case Journey.current(run_id) do
      {:ok, view} -> socket |> watch(run_id) |> assign(view: view, draft: %{}, error: nil)
      {:error, reason} -> assign(socket, view: nil, error: reason)
    end
  end

  defp load(socket, _absent), do: socket

  @spec watch(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp watch(socket, run_id) do
    topic = Durable.topic(run_id)

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

  @spec off_screen(atom()) :: String.t()
  defp off_screen(:running),
    do:
      "The run is between screens - it is resting on a call this app runs as a job. " <>
        "This page redraws when the job answers."

  defp off_screen(status), do: "The run finished: #{status}."
end
