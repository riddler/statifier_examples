defmodule StatifierExamplesWeb.ScreenEditorHost do
  @moduledoc """
  A test-only page mounting `StatifierBlocks.Editor` the way the screen
  editor will: `StatifierExamples.ScreenEditor`'s palette, profile and
  field candidates over an empty patron registration document, a
  `core.sequence` root whose `body` holds the screens.

  Every document the editor answers is sent to the test process named in
  the session's `"test"` key, so a test reads what an insert produced.
  """

  use StatifierExamplesWeb, :live_view

  alias StatifierBlocks.Block
  alias StatifierBlocks.Document
  alias StatifierBlocks.Editor
  alias StatifierExamples.ScreenEditor
  alias StatifierExamplesWeb.Icons

  @impl Phoenix.LiveView
  def mount(_params, %{"test" => test}, socket) do
    parent = self()

    root = Block.new("core.sequence", id: "blk_pr_root")

    {:ok,
     assign(socket,
       document: Document.new(root, id: "doc_patron_registration"),
       on_change: fn document -> send(parent, {:document_changed, document}) end,
       test: test
     )}
  end

  @impl Phoenix.LiveView
  def handle_info({:document_changed, document}, socket) do
    send(socket.assigns.test, {:document_changed, document})
    {:noreply, assign(socket, :document, document)}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <.live_component
      module={Editor}
      id="screen-editor"
      document={@document}
      palette={ScreenEditor.palette()}
      profile={ScreenEditor.profile()}
      field_candidates={ScreenEditor.field_candidates()}
      icon={&Icons.icon/1}
      on_change={@on_change}
    />
    """
  end
end
