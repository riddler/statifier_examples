defmodule StatifierExamples.TypedSendStep do
  @moduledoc """
  A test-only block type, `myapp.typed_send`: a leaf step that writes one
  `<send>` with a literal `type`, a literal `target` and a literal `event`.

  The block vocabulary this app registers has no step that writes a
  `<send>` with a `type`: `core.send` names an event and a delay and
  nothing else, and this app's own types are invokes. A host that hands
  events to its own send processors - the router's among them - writes a
  step like this one for its own palette. The refusal suite under
  `test/fixtures/publish_refusals/` needs one, because two of its charts are
  refused for what a `<send>` names in `type` and `target`, so the suite
  registers this type on top of this app's palette through
  `StatifierExamples.Charts.palette/1`, the seam a host registers its own
  types through. Nothing outside the tests registers it.

  It compiles to a compound state whose entry sends and immediately goes
  final, the shape `core.send` compiles to:

      <state id="s_blk_X" initial="s_blk_X__done">
        <onentry>
          <send event="loan.overdue" target="overdue_notices" type="myapp:sink"/>
        </onentry>
        <final id="s_blk_X__done"/>
      </state>
  """

  @behaviour StatifierBlocks.BlockType

  alias StatifierBlocks.Block
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierBlocks.Emission

  @type_name "myapp.typed_send"

  @keys ["type", "target", "event"]

  @doc "The name the tests register this type under."
  @spec type_name() :: String.t()
  def type_name, do: @type_name

  @doc "This app's palette with this type registered on top of it."
  @spec palette() :: StatifierBlocks.Palette.t()
  def palette, do: StatifierExamples.Charts.palette([{@type_name, __MODULE__}])

  @impl true
  def current_version, do: 1

  @impl true
  def slots(_config), do: []

  @impl true
  def config_schema(_config) do
    for key <- @keys do
      %{key: key, type: :string, label: String.capitalize(key), required?: true, default: ""}
    end
  end

  @impl true
  def validate_config(config) do
    case for(key <- @keys, not filled?(Map.get(config, key)), do: {key, "must not be empty"}) do
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
      Emission.element("send", [
        {"event", config["event"]},
        {"target", config["target"]},
        {"type", config["type"]}
      ])

    onentry = Emission.element("onentry", [], [send_element])

    {:ok, Emit.state(context.state_id, done, [onentry, Emit.final(done)])}
  end

  defp filled?(value), do: is_binary(value) and value != ""
end
