defmodule StatifierExamplesWeb.ScreenEditorLive do
  @moduledoc """
  `/screen-editor` - the blocks editor as a full-size screen editor, with a
  Try action that runs what is on the canvas as a Journey.

  The editor is `StatifierBlocks.Editor` mounted with
  `StatifierExamples.ScreenEditor`'s palette, profile and field candidates
  over a patron registration document: a `core.sequence` root whose `body`
  holds the screens. It opens empty, and every edit the editor commits
  comes back through `on_change` and is held in this page's assigns. Nothing
  is written anywhere else: there is no file and no stored draft.

  ## Try

  The header's Try button hands the document the editor last committed to
  `StatifierExamples.ScreenEditor.Try.start/1`, which walks it into a screen
  document, derives a Path for it and starts a Journey over the two. The
  page then draws the Journey under the editor as
  `StatifierExamplesWeb.SignupJourneyLive` draws the signup Journey: the
  current screen, the findings a refused press answers, and what the
  Journey has collected. The screen document and the Path are held in the
  assigns beside the execution id and passed to every `Journey` call, so
  the Journey runs on the document as it stood when Try was pressed;
  pressing Try again starts a new Journey on the document as it stands now.

  ## What the page shows when Try cannot start

  The editor's own findings pane compiles the document with the screen
  palette, and a screen block means nothing to a chart, so it is not where
  a screen document's mistakes are reported. When Try cannot start, the
  page lists why under the header: each block the walk refused, each
  finding riddler answers for the walked document, or each text question
  naming a format the Journey's check has no message for. That last one is
  refused before a Journey starts, because the check raises on it at the
  first press and the authored document lives only in this page.

  ## What a typed response becomes

  A form posts strings. A boolean question's tick is posted as `"true"` or
  `"false"` and becomes the boolean, and a choice question of many drops
  the blank its renderer posts ahead of its boxes, before the draft is
  resolved or submitted.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Editor
  alias StatifierExamples.ScreenEditor
  alias StatifierExamples.ScreenEditor.Try
  alias StatifierExamples.Signup.Journey
  alias StatifierExamplesWeb.Icons
  alias StatifierExamplesWeb.SignupElements

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    parent = self()
    root = Block.new("core.sequence", id: "blk_pr_root")

    {:ok,
     assign(socket,
       document: Document.new(root, id: "doc_patron_registration"),
       on_change: fn document -> send(parent, {:document_changed, document}) end,
       try: nil,
       view: nil,
       draft: %{},
       refusals: [],
       error: nil
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:document_changed, document}, socket) do
    {:noreply, assign(socket, :document, document)}
  end

  @impl Phoenix.LiveView
  def handle_event("try", _params, socket) do
    with {:ok, try} <- Try.start(socket.assigns.document),
         {:ok, view} <- Journey.current(try.execution_id, try.opts) do
      {:noreply, assign(socket, try: try, view: view, draft: %{}, refusals: [], error: nil)}
    else
      {:error, reason} ->
        {:noreply, assign(socket, try: nil, view: nil, draft: %{}, refusals: refusals(reason))}
    end
  end

  def handle_event("response", _params, %{assigns: %{view: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("response", %{"responses" => responses}, socket) do
    draft = Map.merge(socket.assigns.draft, typed(socket.assigns.view.nodes, responses))

    {:noreply, assign(socket, draft: draft, view: Journey.resolve(socket.assigns.view, draft))}
  end

  def handle_event("outcome", _params, %{assigns: %{try: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("outcome", %{"outcome" => outcome}, %{assigns: assigns} = socket) do
    case Journey.submit(assigns.try.execution_id, outcome, assigns.draft, assigns.try.opts) do
      {:ok, view} -> {:noreply, assign(socket, view: view, draft: %{}, error: nil)}
      {:invalid, view} -> {:noreply, assign(socket, view: view, error: nil)}
      {:error, reason} -> {:noreply, assign(socket, error: reason)}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <div class="myapp-page">
      <.live_component
        module={Editor}
        id="screen-editor"
        document={@document}
        palette={ScreenEditor.palette()}
        profile={ScreenEditor.profile()}
        field_candidates={ScreenEditor.field_candidates()}
        fit={:width}
        icon={&Icons.icon/1}
        on_change={@on_change}
      >
        <:header>
          <div class="myapp-header">
            <div class="myapp-header__identity">
              <span class="myapp-header__title">Screen editor</span>
              <span class="myapp-header__meta">
                revision {@document.revision} &middot; {@document.id}
              </span>
            </div>

            <button id="try" class="myapp-header__button" type="button" phx-click="try">
              Try
            </button>
          </div>
        </:header>
      </.live_component>

      <ul
        :if={@refusals != []}
        id="try-refusals"
        class="alert alert-error flex-col items-start text-sm"
      >
        <li :for={refusal <- @refusals}>{refusal}</li>
      </ul>

      <section :if={@view} id="try-journey" class="mx-auto flex max-w-xl flex-col gap-6 p-6">
        <p id="try-execution" class="font-mono text-xs opacity-60">
          execution {@view.execution_id} - {@view.state}
        </p>

        <p :if={@error} id="try-error" class="alert alert-error text-sm">{inspect(@error)}</p>

        <ul
          :if={@view.findings != []}
          id="try-findings"
          class="alert alert-warning flex-col items-start text-sm"
        >
          <li :for={{key, message} <- @view.findings} id={"try-finding-#{key}"}>
            {label_for(@view.nodes, key)} {message}
          </li>
        </ul>

        <form :if={@view.state == "screen"} id="try-responses" phx-change="response" class="contents">
          <SignupElements.screen
            title={@view.screen.title}
            nodes={@view.nodes}
            responses={@view.responses}
          />
        </form>

        <p :if={@view.state == "done"} id="try-done" class="text-base-content/70">
          The Journey is done.
        </p>

        <details class="text-xs opacity-70">
          <summary>What the Journey has collected</summary>
          <pre id="try-collected" class="whitespace-pre-wrap">{inspect(@view.responses, pretty: true)}</pre>
        </details>
      </section>
    </div>
    """
  end

  # Why Try could not start, one line per block or finding.
  @spec refusals(term()) :: [String.t()]
  defp refusals({:walk, refusals}),
    do: Enum.map(refusals, fn {block_id, message} -> "#{block_id}: #{message}" end)

  defp refusals({:screens_document, findings}) when is_list(findings),
    do: Enum.map(findings, &finding/1)

  defp refusals({:screens_document, :not_a_screens_document}),
    do: ["The walked document is not a screen document."]

  defp refusals({:unsupported_format, keys}),
    do: Enum.map(keys, &"#{&1}: this page has no check for the format this question names")

  defp refusals(reason), do: [inspect(reason)]

  @spec finding(Riddler.Finding.t()) :: String.t()
  defp finding(%Riddler.Finding{node_key: nil, code: code, message: message}),
    do: "#{code}: #{message}"

  defp finding(%Riddler.Finding{node_key: key, code: code, message: message}),
    do: "#{key} - #{code}: #{message}"

  # The responses a form posted, turned into what the questions on the
  # screen hold (the moduledoc's "What a typed response becomes").
  @spec typed([map()], map()) :: map()
  defp typed(nodes, responses) do
    types = Map.new(nodes, &{&1["key"], &1["type"]})

    Map.new(responses, fn {key, value} -> {key, typed_value(types[key], value)} end)
  end

  defp typed_value("boolean_question", value) when value in ["true", "false"],
    do: value == "true"

  defp typed_value("choice_question", values) when is_list(values),
    do: Enum.reject(values, &(&1 == ""))

  defp typed_value(_type, value), do: value

  # A finding names a node key; a reader knows the question by its label.
  @spec label_for([map()], String.t()) :: String.t()
  defp label_for(nodes, key) do
    case Enum.find(nodes, &(&1["key"] == key)) do
      %{"label" => label} -> label
      _no_label -> key
    end
  end
end
