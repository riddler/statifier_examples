defmodule StatifierExamplesWeb.SignupElements do
  @moduledoc """
  Function components that draw a resolved signup screen.

  `StatifierExamples.Signup.Screens` decides what a reader sees - conditions
  evaluated, text slots filled - and this module decides what it looks like.
  The split is the point of the skeleton: the renderer takes nodes that are
  already resolved, so it holds no datamodel, evaluates no expression, and
  cannot disagree with the resolver about whether a node is on the screen.

  One component per element type, plus `screen/1`, which dispatches over
  `"type"` and is the only entry point a page needs. A node whose type this
  module does not know is a document the app cannot draw: it raises rather
  than rendering nothing, because a silently dropped element is a screen that
  lies about the document.

  Buttons post `phx-click="outcome"` with the outcome name the document
  declares. Naming the outcome here rather than a screen-specific event is
  what lets `se-19h` wire the same markup to the Composite's outcome slots
  without the renderer learning anything about the chart.
  """

  use Phoenix.Component

  alias StatifierExamples.Signup.Screens

  @doc """
  Draws a whole screen from its resolved nodes.
  """
  attr :title, :string, required: true
  attr :nodes, :list, required: true, doc: "nodes from `Screens.resolve/2`"
  attr :answers, :map, default: %{}, doc: "current answers, keyed by element key"

  def screen(assigns) do
    ~H"""
    <section class="flex flex-col gap-4" data-screen-title={@title}>
      <.element :for={node <- @nodes} node={node} answers={@answers} />
    </section>
    """
  end

  @doc """
  Draws one element node, dispatching on its `"type"`.
  """
  attr :node, :map, required: true
  attr :answers, :map, default: %{}

  def element(%{node: %{"type" => "heading"}} = assigns), do: heading(assigns)
  def element(%{node: %{"type" => "text"}} = assigns), do: text(assigns)
  def element(%{node: %{"type" => "text_question"}} = assigns), do: text_question(assigns)
  def element(%{node: %{"type" => "button"}} = assigns), do: button(assigns)

  def element(%{node: node}) do
    raise ArgumentError,
          "no renderer for element type #{inspect(Map.get(node, "type"))} " <>
            "(node #{inspect(Map.get(node, "key"))})"
  end

  @doc "A screen's title, or a subtitle within it."
  attr :node, :map, required: true
  attr :answers, :map, default: %{}

  def heading(assigns) do
    ~H"""
    <h1 :if={@node["level"] == 1} id={@node["key"]} class="text-2xl font-semibold">
      {@node["text"]}
    </h1>
    <h2 :if={@node["level"] != 1} id={@node["key"]} class="text-lg font-semibold">
      {@node["text"]}
    </h2>
    """
  end

  @doc "A paragraph. Its text slots are already filled."
  attr :node, :map, required: true
  attr :answers, :map, default: %{}

  def text(assigns) do
    ~H"""
    <p id={@node["key"]} class="text-base-content/80">{@node["text"]}</p>
    """
  end

  @doc "A labelled text input, writing to `answers.<key>`."
  attr :node, :map, required: true
  attr :answers, :map, default: %{}

  def text_question(assigns) do
    ~H"""
    <label id={@node["key"]} class="flex flex-col gap-1">
      <span class="text-sm font-medium">
        {@node["label"]}<span :if={@node["required"]} class="text-error" aria-hidden="true">*</span>
      </span>
      <input
        type="text"
        name={"answers[#{@node["key"]}]"}
        value={Map.get(@answers, @node["key"], "")}
        placeholder={@node["placeholder"]}
        required={@node["required"] == true}
        class="input input-bordered w-full"
      />
    </label>
    """
  end

  @doc "A button that ends the screen by naming an outcome."
  attr :node, :map, required: true
  attr :answers, :map, default: %{}

  def button(assigns) do
    ~H"""
    <button
      id={@node["key"]}
      type="button"
      class="btn btn-primary w-fit"
      phx-click="outcome"
      phx-value-outcome={@node["outcome"]}
      data-outcome={@node["outcome"]}
    >
      {@node["label"]}
    </button>
    """
  end

  @doc """
  Convenience for a page: resolve `screen` against `datamodel` and draw it.
  """
  attr :screen, :map, required: true, doc: "a screen from `Screens.screens/0`"
  attr :datamodel, :map, required: true

  def resolved_screen(assigns) do
    assigns =
      assign(assigns,
        nodes: Screens.resolve(assigns.screen, assigns.datamodel),
        answers: Map.get(assigns.datamodel, "answers", %{})
      )

    ~H"""
    <.screen title={@screen.title} nodes={@nodes} answers={@answers} />
    """
  end
end
