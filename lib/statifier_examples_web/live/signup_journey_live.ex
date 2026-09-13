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
    {:noreply, load(socket, params["execution"])}
  end

  @impl Phoenix.LiveView
  def handle_event("start", _params, socket) do
    case Journey.start() do
      {:ok, execution_id} ->
        {:noreply, push_patch(socket, to: ~p"/signup-journey?execution=#{execution_id}")}

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

  def handle_event("outcome", %{"outcome" => outcome}, %{assigns: assigns} = socket) do
    case Journey.submit(assigns.view.execution_id, outcome, assigns.draft) do
      {:ok, view} -> {:noreply, assign(socket, view: view, draft: %{}, error: nil)}
      {:invalid, view} -> {:noreply, assign(socket, view: view, error: nil)}
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
            run {@view.execution_id} - {@view.status}
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

          <form :if={@view.screen} id="journey-responses" phx-change="response" class="contents">
            <SignupElements.screen
              title={@view.screen.title}
              nodes={@view.nodes}
              responses={@view.responses}
            />
          </form>

          <p :if={is_nil(@view.screen)} id="no-screen" class="text-base-content/70">
            {off_screen(@view.status)}
          </p>

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
    case Journey.current(execution_id) do
      {:ok, view} -> socket |> watch(execution_id) |> assign(view: view, draft: %{}, error: nil)
      {:error, reason} -> assign(socket, view: nil, error: reason)
    end
  end

  defp load(socket, _absent), do: socket

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
