defmodule StatifierExamples.Signup.Screens do
  @moduledoc """
  The signup wizard's **element documents**: what a screen shows, as opposed
  to what the chart does.

  A Path is a `statifier_blocks` document plus one element document per screen
  (ruled by the operator for Riddler, 2026-09-12).
  `priv/fixtures/signup_wizard.json` is this domain's block document and says
  when a screen is reached; this module reads
  `priv/fixtures/signup_screens.json`, which says what is on it. The two are
  deliberately separate files: a screen gains a paragraph without the chart's
  content hash - and therefore its chart identity - moving.

  ## The four element types

  This is the walking skeleton's whole vocabulary, and it is
  small on purpose:

  | `type` | Renders | Carries |
  |---|---|---|
  | `heading` | a title | `level` (1 or 2), `text` |
  | `text` | a paragraph | `text`, which may hold text slots |
  | `text_question` | a labelled text input | `label`, `placeholder`, `required` |
  | `button` | a button that ends the screen | `label`, `outcome` |

  Every node carries a `key`. For a `text_question` the key is also where the
  response lives: responses are keyed by element key, `responses.<key>` (ruled
  by the operator for Riddler, 2026-09-12), so the document never has to say a
  second time where a question writes to. For the other three types the key is
  an identifier and nothing more, which is one field carrying two meanings - a
  finding this skeleton records rather than fixes
  (`docs/spikes/signup-skeleton-spike.md`).

  ## Resolving a screen

  `resolve/2` takes a screen and a datamodel map and returns only the nodes a
  reader should see, with their templates rendered. It does not do either
  itself: it hands the screen to `Riddler.Screens.resolve_screen/3`, which
  owns both rules, and answers the nodes riddler resolved, string-keyed as
  the document writes them. The datamodel is the root riddler reads: its
  `"responses"` and `"context"` and nothing else.

    * **Conditions.** A node may carry `condition`, predicator source
      evaluated against the root. The node is kept only when the expression
      evaluates to `true`. A path the root does not hold, an operand of the
      wrong type and source that does not parse all hide the node rather
      than raising - which is the behaviour a first screen needs, since on
      the way in the datamodel is empty. A node with no condition is always
      kept, and a kept node carries no `condition` any more: riddler
      resolves it away.

    * **Templates.** A `heading` or `text` node's text, and a question's
      `label` and `placeholder`, are templates in riddler's subset, so
      `{{ responses.first_name }}` reads the response. A variable the root
      does not hold renders as the empty string.

  `fill_slots/2` is not that renderer. It is the regex this module used to
  fill slots with before riddler did, kept because it is public and its
  answers are pinned: for a slot naming a whole subtree it answers the
  empty string, where riddler's renderer writes the subtree out.

  ## A screens document other than the fixture

  Every function that reads the element document has a form that takes
  one: `screens/1` and `screen/2` read a decoded screens document a caller
  supplies, and `admit/1` is the check that one is a document riddler
  admits with no findings. The zero-argument forms read the fixture.
  """

  alias Riddler.Screens.Document

  @fixture "signup_screens.json"

  # The envelope a screen is wrapped in when it is resolved on its own. The
  # id is never read back; it is only what makes the wrapper a document.
  @single_screen_id "edoc_one_screen"

  @typedoc "One element node, as it appears in the document."
  @type node_doc :: %{required(String.t()) => term()}

  @typedoc "One screen: a key, a title, and a flat list of nodes."
  @type screen :: %{key: String.t(), title: String.t(), nodes: [node_doc()]}

  # `{{ responses.first_name }}`: the delimiters, any surrounding whitespace,
  # and a dotted path of word characters between them.
  @slot ~r/\{\{\s*([\w.]+)\s*\}\}/

  @doc """
  Every screen in the element document, in the order the wizard shows them.

  Read from disk on every call, for the reason the block fixtures are
  (`StatifierExamples.Signup.fixtures/0`): a file that can be edited and
  reloaded is worth more to an example app than the microseconds.
  """
  @spec screens() :: [screen()]
  def screens, do: screens(document())

  @doc """
  Every screen in `document`, a decoded screens document, in its order.
  """
  @spec screens(map()) :: [screen()]
  def screens(document) when is_map(document) do
    document
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
  def screen(key) when is_binary(key), do: screen(document(), key)

  @doc """
  The screen of `document` keyed `key`, or `nil`.
  """
  @spec screen(map(), String.t()) :: screen() | nil
  def screen(document, key) when is_map(document) and is_binary(key),
    do: Enum.find(screens(document), &(&1.key == key))

  @doc """
  The nodes of `screen` a reader should see, resolved by
  `Riddler.Screens.resolve_screen/3`.

  `datamodel` is the root conditions are evaluated against and templates
  are read from - `%{"responses" => %{"first_name" => "Ada"}}` for the
  documents this app ships. Raises `ArgumentError` for a screen riddler does
  not admit as a document's screen.

  ## Examples

      iex> screen = StatifierExamples.Signup.Screens.screen("account")
      iex> nodes = StatifierExamples.Signup.Screens.resolve(screen, %{})
      iex> Enum.any?(nodes, &(&1["key"] == "account_greeting"))
      false
  """
  @spec resolve(screen(), map()) :: [node_doc()]
  def resolve(%{key: key, title: title, nodes: nodes}, datamodel) when is_map(datamodel) do
    document = admit_screen!(key, title, nodes)
    {:ok, resolved, _diagnostics} = Riddler.Screens.resolve_screen(document, key, datamodel)

    Enum.map(resolved.nodes, &to_node_doc/1)
  end

  @doc """
  Whether `node_doc`'s condition holds against `datamodel`.

  A node with no condition is shown. A node whose condition evaluates to
  anything other than `true` - `false`, a path the datamodel does not hold,
  or source that does not parse - is hidden. The answer is
  `Riddler.Screens.resolve_screen/3`'s for a screen holding that node alone.
  """
  @spec shown?(node_doc(), map()) :: boolean()
  def shown?(node_doc, datamodel) when is_map(node_doc) and is_map(datamodel) do
    probe = %{"type" => "text", "key" => "shown", "text" => ""}

    probe =
      case Map.fetch(node_doc, "condition") do
        {:ok, condition} -> Map.put(probe, "condition", condition)
        :error -> probe
      end

    case Document.admit(envelope("shown", "shown", [probe])) do
      nil ->
        false

      document ->
        match?(
          {:ok, %{nodes: [_shown]}, _},
          Riddler.Screens.resolve_screen(document, "shown", datamodel)
        )
    end
  end

  @doc """
  Substitutes `{{ path }}` slots in `text` from `datamodel`.

  Not what `resolve/2` renders with: riddler's template subset does that.
  This is the regex the module filled slots with before, kept for the
  answers it is pinned to. An unresolved path becomes the empty string, and
  so does one naming something with no sensible string of its own - a map
  or a list, as `{{ responses }}` would be.

  ## Examples

      iex> StatifierExamples.Signup.Screens.fill_slots(
      ...>   "Hello, {{ responses.first_name }}.",
      ...>   %{"responses" => %{"first_name" => "Ada"}}
      ...> )
      "Hello, Ada."
  """
  @spec fill_slots(String.t(), map()) :: String.t()
  def fill_slots(text, datamodel) when is_binary(text) and is_map(datamodel) do
    Regex.replace(@slot, text, fn _whole, path -> stringify(lookup(datamodel, path)) end)
  end

  @doc """
  The outcome names `screen`'s buttons declare, in document order.

  Every button ends the screen by naming an outcome; the screen Composite
  turns that list into its outcome slots.
  """
  @spec outcomes(screen()) :: [String.t()]
  def outcomes(%{nodes: nodes}) do
    for %{"type" => "button"} = node_doc <- nodes, do: Map.fetch!(node_doc, "outcome")
  end

  @doc """
  The element keys `screen`'s questions write responses under, in document
  order. `responses.<key>` is where each one lands (ruled by the operator for
  Riddler, 2026-09-12).
  """
  @spec response_keys(screen()) :: [String.t()]
  def response_keys(%{nodes: nodes}) do
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

  @doc """
  `document`, a decoded screens document, admitted by
  `Riddler.Screens.Document.admit/1` and validated by
  `Riddler.Screens.Document.validate/1`.

  `{:ok, admitted}` when riddler admits it with no findings;
  `{:error, :not_a_screens_document}` when `admit/1` answers `nil`, and
  `{:error, findings}` with riddler's findings otherwise.
  """
  @spec admit(term()) ::
          {:ok, Document.t()}
          | {:error, :not_a_screens_document}
          | {:error, [Riddler.Finding.t()]}
  def admit(document) do
    case Document.admit(document) do
      nil -> {:error, :not_a_screens_document}
      admitted -> Document.validate(admitted)
    end
  end

  # One screen, wrapped in an envelope riddler admits. `Document.admit/1`
  # answers `nil` only for a spine that is not a document's; a node that is
  # wrong rather than absent is admitted, so this raises only for a screen no
  # document could hold.
  @spec admit_screen!(String.t(), String.t(), [node_doc()]) :: Document.t()
  defp admit_screen!(key, title, nodes) do
    case Document.admit(envelope(key, title, nodes)) do
      nil -> raise ArgumentError, "screen #{inspect(key)} is not one riddler admits"
      document -> document
    end
  end

  @spec envelope(String.t(), String.t(), [node_doc()]) :: map()
  defp envelope(key, title, nodes) do
    %{
      "schema_version" => 1,
      "id" => @single_screen_id,
      "screens" => [%{"key" => key, "title" => title, "nodes" => nodes}]
    }
  end

  # Riddler resolves to atom-keyed nodes; a node here is string-keyed, as the
  # document writes it and as every page and check in this app reads it. The
  # values are the document's own JSON values, so only the keys move, and a
  # choice question's options are maps of their own.
  @spec to_node_doc(map()) :: node_doc()
  defp to_node_doc(node) when is_map(node) do
    Map.new(node, fn {field, value} -> {to_string(field), to_node_value(value)} end)
  end

  defp to_node_value(list) when is_list(list), do: Enum.map(list, &to_node_value/1)
  defp to_node_value(%{} = map) when not is_struct(map), do: to_node_doc(map)
  defp to_node_value(value), do: value

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
