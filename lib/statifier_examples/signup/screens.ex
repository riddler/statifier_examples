defmodule StatifierExamples.Signup.Screens do
  @moduledoc """
  The signup wizard's **element documents**: what a screen shows, as opposed
  to what the chart does.

  A Path is a `statifier_blocks` document plus one element document per
  screen (Riddler R10a). `priv/fixtures/signup_wizard.json` is this domain's
  block document and says when a screen is reached; this module reads
  `priv/fixtures/signup_screens.json`, which says what is on it. The two are
  deliberately separate files: a screen gains a paragraph without the chart's
  content hash - and therefore its chart identity - moving.

  ## The four element types

  This is the walking skeleton's whole vocabulary (`se-e68`), and it is
  small on purpose:

  | `type` | Renders | Carries |
  |---|---|---|
  | `heading` | a title | `level` (1 or 2), `text` |
  | `text` | a paragraph | `text`, which may hold text slots |
  | `text_question` | a labelled text input | `label`, `placeholder`, `required` |
  | `button` | a button that ends the screen | `label`, `outcome` |

  Every node carries a `key`. For a `text_question` the key is also where
  the answer lives: answers are keyed by element key, `answers.<key>`
  (Riddler R10d), so the document never has to say a second time where a
  question writes to. For the other three types the key is an identifier and
  nothing more, which is one field carrying two meanings - a finding this
  skeleton records rather than fixes (`docs/spikes/SF040-signup-skeleton.md`).

  ## Resolving a screen

  `resolve/2` takes a screen and a datamodel map and returns only the nodes a
  reader should see, with their text slots filled. Two things happen:

    * **Conditions.** A node may carry `condition`, predicator source
      evaluated against the datamodel. The node is kept only when the
      expression evaluates to `true`. Predicator answers `{:ok, :undefined}`
      for a path the datamodel does not hold, so a question that has not been
      answered yet hides whatever depends on it rather than raising - which
      is the behaviour a first screen needs, since on the way in the
      datamodel is empty. A node with no condition is always kept.

    * **Text slots.** A `heading` or `text` node's text may hold
      `{{ answers.first_name }}`. `fill_slots/2` is the two-line stand-in for
      the templating subset: one regex, one lookup. It is **not** a Liquid
      implementation and this app does not depend on one - the subset is
      Riddler R9's to define, and a library added here would quietly become
      the definition.

  A slot whose path the datamodel does not hold renders as the empty string.
  A half-written sentence is a visible bug; a raised exception on a screen
  whose questions have not been answered yet is a broken app.
  """

  alias StatifierExamples.Signup.Screens

  @fixture "signup_screens.json"

  @typedoc "One element node, as it appears in the document."
  @type node_doc :: %{required(String.t()) => term()}

  @typedoc "One screen: a key, a title, and a flat list of nodes."
  @type screen :: %{key: String.t(), title: String.t(), nodes: [node_doc()]}

  # `{{ answers.first_name }}`: the delimiters, any surrounding whitespace,
  # and a dotted path of word characters between them.
  @slot ~r/\{\{\s*([\w.]+)\s*\}\}/

  @doc """
  Every screen in the element document, in the order the wizard shows them.

  Read from disk on every call, for the reason the block fixtures are
  (`StatifierExamples.Signup.fixtures/0`): a file that can be edited and
  reloaded is worth more to an example app than the microseconds.
  """
  @spec screens() :: [screen()]
  def screens do
    document()
    |> Map.fetch!("screens")
    |> Enum.map(fn screen ->
      %{
        key: Map.fetch!(screen, "key"),
        title: Map.fetch!(screen, "title"),
        nodes: Map.fetch!(screen, "nodes")
      }
    end)
  end

  @doc """
  The screen keyed `key`, or `nil`.
  """
  @spec screen(String.t()) :: screen() | nil
  def screen(key) when is_binary(key), do: Enum.find(screens(), &(&1.key == key))

  @doc """
  The nodes of `screen` a reader should see, with their text slots filled.

  `datamodel` is the map conditions are evaluated against and slots are read
  from - `%{"answers" => %{"first_name" => "Ada"}}` for the documents this
  app ships.

  ## Examples

      iex> screen = StatifierExamples.Signup.Screens.screen("account")
      iex> nodes = StatifierExamples.Signup.Screens.resolve(screen, %{})
      iex> Enum.any?(nodes, &(&1["key"] == "account_greeting"))
      false
  """
  @spec resolve(screen(), map()) :: [node_doc()]
  def resolve(%{nodes: nodes}, datamodel) when is_map(datamodel) do
    nodes
    |> Enum.filter(&shown?(&1, datamodel))
    |> Enum.map(&fill_node(&1, datamodel))
  end

  @doc """
  Whether `node_doc`'s condition holds against `datamodel`.

  A node with no condition is shown. A node whose condition evaluates to
  anything other than `true` - `false`, `:undefined` for a path the
  datamodel does not hold, or an error from source that does not parse - is
  hidden.
  """
  @spec shown?(node_doc(), map()) :: boolean()
  def shown?(node_doc, datamodel) when is_map(datamodel) do
    case Map.get(node_doc, "condition") do
      nil -> true
      source -> Predicator.evaluate(source, datamodel) == {:ok, true}
    end
  end

  @doc """
  Substitutes `{{ path }}` slots in `text` from `datamodel`.

  The two-line stand-in for the templating subset. An unresolved path becomes
  the empty string, and so does one naming something with no sensible string
  of its own - a map or a list, as `{{ answers }}` would be. Raising inside a
  paragraph is not a behaviour a screen can recover from.

  ## Examples

      iex> StatifierExamples.Signup.Screens.fill_slots(
      ...>   "Hello, {{ answers.first_name }}.",
      ...>   %{"answers" => %{"first_name" => "Ada"}}
      ...> )
      "Hello, Ada."
  """
  @spec fill_slots(String.t(), map()) :: String.t()
  def fill_slots(text, datamodel) when is_binary(text) and is_map(datamodel) do
    Regex.replace(@slot, text, fn _whole, path -> stringify(lookup(datamodel, path)) end)
  end

  @doc """
  The outcome names `screen`'s buttons declare, in document order.

  Every button ends the screen by naming an outcome; `se-19h` turns that list
  into the Composite's outcome slots.
  """
  @spec outcomes(screen()) :: [String.t()]
  def outcomes(%{nodes: nodes}) do
    for %{"type" => "button"} = node_doc <- nodes, do: Map.fetch!(node_doc, "outcome")
  end

  @doc """
  The element keys `screen`'s questions write answers under, in document
  order. `answers.<key>` is where each one lands (Riddler R10d).
  """
  @spec answer_keys(screen()) :: [String.t()]
  def answer_keys(%{nodes: nodes}) do
    for %{"type" => "text_question"} = node_doc <- nodes, do: Map.fetch!(node_doc, "key")
  end

  @doc """
  The element document itself, decoded.
  """
  @spec document() :: map()
  def document do
    [Application.app_dir(:statifier_examples), "priv", "fixtures", @fixture]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
  end

  # Only the two types that carry prose have slots to fill; a label or a
  # placeholder holding one would be a fifth thing the renderer has to know
  # about, and no screen here needs it.
  @spec fill_node(node_doc(), map()) :: node_doc()
  defp fill_node(%{"type" => type} = node_doc, datamodel) when type in ["heading", "text"] do
    Map.update!(node_doc, "text", &Screens.fill_slots(&1, datamodel))
  end

  defp fill_node(node_doc, _datamodel), do: node_doc

  # `to_string/1` has no implementation for a map or a list of mixed terms,
  # and a slot naming a whole subtree is a document mistake rather than a
  # reason to raise while rendering a paragraph.
  @spec stringify(term()) :: String.t()
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_number(value) or is_atom(value), do: to_string(value)
  defp stringify(_not_a_scalar), do: ""

  @spec lookup(map(), String.t()) :: term()
  defp lookup(datamodel, path) do
    path
    |> String.split(".")
    |> Enum.reduce(datamodel, fn
      segment, %{} = acc -> Map.get(acc, segment)
      _segment, _absent -> nil
    end)
  end
end
