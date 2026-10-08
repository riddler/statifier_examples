defmodule StatifierExamples.TypedSendStep do
  @moduledoc """
  `myapp.typed_send`: a leaf step that writes one `<send>` with a literal
  `type`, a literal `target` and a literal `event`, and optionally hands
  the receiver the values at a list of datamodel paths.

  The block vocabulary `statifier_blocks` ships has no step that writes a
  `<send>` with a `type`: `core.send` names an event and a delay and
  nothing else, and this app's other types are invokes. A host that hands
  events to its own send processors - the router's among them - writes a
  step like this one for its own palette, and this is this app's, registered
  in `StatifierExamples.Charts.palette/0` beside the core vocabulary. The
  author sets all three of `type`, `target` and `event`; none of them is an
  expression, so the host's publish step can judge every one before the
  document runs (`StatifierExamples.Publish`'s `:send_types` and `:routes`
  stages read exactly these attributes).

  ## What the compiled `<send>` carries

  It compiles to a compound state whose entry sends and immediately goes
  final, the shape `core.send` compiles to. With no `payload` - the key
  absent, `null` or `[]` - the `<send>` carries the three attributes and
  nothing else:

      <state id="s_blk_X" initial="s_blk_X__done">
        <onentry>
          <send event="loan.overdue" target="overdue_notices" type="myapp:sink"/>
        </onentry>
        <final id="s_blk_X__done"/>
      </state>

  With a `payload`, the `<send>` carries one `<param>` per path, in the
  order the author listed them, each named by its path and reading the
  value at it - SCXML's own shape for a send's data, so the receiver finds
  each value in the event's data under the path it was read from:

      <send event="loan.overdue" target="overdue_notices" type="myapp:sink">
        <param expr="loan.id" name="loan.id"/>
      </send>

  ## What the payload admits

  `payload` is a list of datamodel paths: dotted identifiers such as
  `loan.id`, each named once. `validate_config/1` refuses an entry that is
  not one, and a duplicate. It names paths and never literal values: what
  reaches the receiver is whatever the chart's datamodel holds at those
  paths, so a chart that holds only ids sends only ids, and the receiver
  reads the rest by them.

  Whether a path is *declared* in the document's datamodel is not
  something this type can refuse: `validate_config/1` is handed the
  config and nothing else, and `emit/2` is handed no datamodel either.
  The family's own answer to an undeclared path is `statifier_blocks`'
  undeclared-path advisory, which informs and never refuses, and which
  today reads a path field and not a path inside a list.
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission
  alias StatifierBlocks.InvokeStep
  alias StatifierExamples.Charts.Step

  @type_name "myapp.typed_send"

  @keys ["type", "target", "event"]

  @payload "payload"

  @path ~r/\A[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*\z/

  @doc "The name this app registers the type under."
  @spec type_name() :: String.t()
  def type_name, do: @type_name

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def palette_entry do
    %{
      label: "Typed send",
      group: "Messaging",
      description: "Sends one event to a named target through a send processor.",
      icon: "paper-airplane",
      keywords: ["send", "event", "target", "type"],
      order: 1,
      accent_token: Step.accent_token()
    }
  end

  @impl true
  def explain do
    "Sends one event, named by the author, to a target the author names, " <>
      "through the send processor the author names by its type, then " <>
      "finishes; it can hand the receiver the values at a list of datamodel paths."
  end

  # The `label` field every host type in this app puts first, which titles
  # the block's card; see `StatifierExamples.Charts.StepLabelTest`.
  @impl true
  def config_schema(_config) do
    fields =
      for key <- @keys do
        %{key: key, type: :string, label: String.capitalize(key), required?: true, default: ""}
      end

    [InvokeStep.label_field() | fields] ++
      [
        %{
          key: @payload,
          type: {:list, {:path, %{}}},
          label: "Send along",
          required?: false,
          default: []
        }
      ]
  end

  @impl true
  def validate_config(config) do
    findings =
      for(key <- @keys, not filled?(Map.get(config, key)), do: {key, "must not be empty"}) ++
        payload_findings(Map.get(config, @payload))

    case findings do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @impl true
  def io(_config), do: %{kinds: [:step]}

  @impl true
  def emit(%Block{config: config}, context) do
    done = Context.done_id(context)

    send_element =
      Emission.element(
        "send",
        [
          {"event", config["event"]},
          {"target", config["target"]},
          {"type", config["type"]}
        ],
        config |> Map.get(@payload) |> paths() |> Enum.map(&param/1)
      )

    onentry = Emission.element("onentry", [], [send_element])

    {:ok, Emit.state(context.state_id, done, [onentry, Emit.final(done)])}
  end

  @spec param(String.t()) :: Emission.t()
  defp param(path) do
    "param"
    |> Emission.element([{"expr", path}, {"name", path}])
    |> Emission.from_config(@payload)
  end

  @spec paths(term()) :: [String.t()]
  defp paths(payload) when is_list(payload), do: payload
  defp paths(_absent), do: []

  @spec payload_findings(term()) :: [{String.t(), String.t()}]
  defp payload_findings(nil), do: []

  defp payload_findings(payload) when is_list(payload) do
    cond do
      not Enum.all?(payload, &path?/1) ->
        [{@payload, "every entry must be a datamodel path, like loan.id"}]

      length(Enum.uniq(payload)) != length(payload) ->
        [{@payload, "names a path more than once"}]

      true ->
        []
    end
  end

  defp payload_findings(_other), do: [{@payload, "must be a list of datamodel paths"}]

  defp path?(value), do: is_binary(value) and Regex.match?(@path, value)

  defp filled?(value), do: is_binary(value) and value != ""
end
