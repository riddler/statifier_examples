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
  what lets the screen Composite wire the same markup to its outcome slots
  without the renderer learning anything about the chart.
  """

  use Phoenix.Component

  alias StatifierExamples.Signup.Screens

  @doc """
  Draws a whole screen from its resolved nodes.
  """
  attr :title, :string, required: true
  attr :nodes, :list, required: true, doc: "nodes from `Screens.resolve/2`"
  attr :responses, :map, default: %{}, doc: "current responses, keyed by element key"

  def screen(assigns) do
    ~H"""
    <section class="flex flex-col gap-4" data-screen-title={@title}>
      <.element :for={node <- @nodes} node={node} responses={@responses} />
    </section>
    """
  end

  @doc """
  Draws one element node, dispatching on its `"type"`.
  """
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

  def element(%{node: %{"type" => "heading"}} = assigns), do: heading(assigns)
  def element(%{node: %{"type" => "text"}} = assigns), do: text(assigns)
  def element(%{node: %{"type" => "text_question"}} = assigns), do: text_question(assigns)
  def element(%{node: %{"type" => "choice_question"}} = assigns), do: choice_question(assigns)
  def element(%{node: %{"type" => "boolean_question"}} = assigns), do: boolean_question(assigns)
  def element(%{node: %{"type" => "button"}} = assigns), do: button(assigns)

  def element(%{node: node}) do
    raise ArgumentError,
          "no renderer for element type #{inspect(Map.get(node, "type"))} " <>
            "(node #{inspect(Map.get(node, "key"))})"
  end

  @doc "A screen's title, or a subtitle within it."
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

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
  attr :responses, :map, default: %{}

  def text(assigns) do
    ~H"""
    <p id={@node["key"]} class="text-base-content/80">{@node["text"]}</p>
    """
  end

  @doc "A labelled text input, writing to `responses.<key>`."
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

  def text_question(assigns) do
    ~H"""
    <label id={@node["key"]} class="flex flex-col gap-1">
      <span class="text-sm font-medium">
        {@node["label"]}<span :if={@node["required"]} class="text-error" aria-hidden="true">*</span>
      </span>
      <input
        type="text"
        name={"responses[#{@node["key"]}]"}
        value={Map.get(@responses, @node["key"], "")}
        placeholder={@node["placeholder"]}
        required={@node["required"] == true}
        class="input input-bordered w-full"
      />
    </label>
    """
  end

  @doc """
  A labelled set of options, writing to `responses.<key>`: radio buttons
  for a `select` of one, posting the chosen value, and checkboxes for a
  `select` of many, posting the chosen values as a list.

  The `style` hint is not read: radio buttons and checkboxes are what this
  renderer draws for every option count. A select of many posts a blank
  value ahead of its checkboxes, so clearing every box still posts the key;
  the page drops the blank.
  """
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

  def choice_question(assigns) do
    assigns = assign(assigns, many?: assigns.node["select"] == "many")

    ~H"""
    <fieldset id={@node["key"]} class="flex flex-col gap-1">
      <legend class="text-sm font-medium">
        {@node["label"]}<span :if={@node["required"]} class="text-error" aria-hidden="true">*</span>
      </legend>
      <input :if={@many?} type="hidden" name={"responses[#{@node["key"]}][]"} value="" />
      <label :for={option <- @node["answer_options"]} class="flex items-center gap-2">
        <input
          type={if @many?, do: "checkbox", else: "radio"}
          name={if @many?, do: "responses[#{@node["key"]}][]", else: "responses[#{@node["key"]}]"}
          value={option["value"]}
          checked={chosen?(@responses, @node["key"], option["value"])}
          class={if @many?, do: "checkbox", else: "radio"}
        />
        <span>{option["label"]}</span>
      </label>
    </fieldset>
    """
  end

  @doc """
  A lone checkbox, writing `true` or `false` to `responses.<key>`. A blank
  `false` is posted ahead of it, so an unticked box still posts the key.
  """
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

  def boolean_question(assigns) do
    ~H"""
    <label id={@node["key"]} class="flex items-center gap-2">
      <input type="hidden" name={"responses[#{@node["key"]}]"} value="false" />
      <input
        type="checkbox"
        name={"responses[#{@node["key"]}]"}
        value="true"
        checked={Map.get(@responses, @node["key"]) in [true, "true"]}
        class="checkbox"
      />
      <span class="text-sm font-medium">
        {@node["label"]}<span :if={@node["required"]} class="text-error" aria-hidden="true">*</span>
      </span>
    </label>
    """
  end

  @doc "A button that ends the screen by naming an outcome."
  attr :node, :map, required: true
  attr :responses, :map, default: %{}

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

  # Whether `value` is among what the reader chose for `key`: the one value
  # of a select of one, or one of the list a select of many holds.
  @spec chosen?(map(), String.t(), String.t()) :: boolean()
  defp chosen?(responses, key, value) do
    case Map.get(responses, key) do
      values when is_list(values) -> value in values
      chosen -> chosen == value
    end
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
        responses: Map.get(assigns.datamodel, "responses", %{})
      )

    ~H"""
    <.screen title={@screen.title} nodes={@nodes} responses={@responses} />
    """
  end
end
