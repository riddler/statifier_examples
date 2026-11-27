defmodule StatifierExamples.Signup.ReturnableStep do
  @moduledoc """
  `myapp.step`: one screen of a Path, as a plain block type a reader may
  come back to.

  `myapp.screen` (`StatifierExamples.Signup.Screen`) is the other way this
  app shows a screen, and the two are worth reading together. That one is a
  **composite**: it expands to a group that presents the screen, parks on a
  `core.await` and holds one `core.on_event` per button, all derived from
  the signup screens fixture. This one is a **plain** block type that
  writes its own state, and it declares `returnable?/1`
  (`statifier_blocks` ADR-0002's Amendment of 2026-11-20, `C12`), so the
  compiler keeps a trail of the steps an execution entered and answers the
  reserved back event over it (ADR-0004's Amendment of the same date). A
  composite cannot be declared a returnable step (`C12b`), which is why the
  signup Path keeps its composite screens and the authored back edge on
  its plan screen, and why Back through the engine is this type's.

  ## What an author configures

  Three fields beside the `label` every host type leads with, and the
  screens document says the rest:

    * `screen` - the key of the screen this step shows, in the screens
      document the Journey runs with
      (`StatifierExamples.Signup.Journey`'s "A screens document the caller
      supplies"). It is not read here: the block type never sees the
      screens document, so one type serves every document that names it.
    * `buttons` - the screen's buttons, each named by the outcome it
      carries on the screen. Pressing any of them finishes the step; the
      press raises `StatifierExamples.Signup.Screen.outcome_event/1` of
      that outcome, the same event a `myapp.screen` button raises.
    * `responses` - the keys of the questions on the screen. Each press
      writes `responses.<key>` from the key of the same name in the
      press's data, and only where the press carried it, so a response the
      chart already holds is not overwritten by a press that left it out.

  `StatifierExamples.Signup.Journey.start/2` refuses a Path whose step
  disagrees with the screen it names: a configured button or response the
  screen does not carry, or a button or question on the screen the step
  does not configure, since that press would have no transition and that
  answer would never be recorded.

  ## One outcome, `done`

  The step finishes as `done` whichever button was pressed. The type
  declares no `outcomes/1`, so it has the one outcome every block has
  when it declares none (`StatifierBlocks.BlockType`'s `outcomes/1`), and
  a Path cannot route on which button was pressed; a Path that wants to
  branch on a button reads what the press recorded instead.

  That is why the key is `buttons` and not `outcomes`, its name before
  version 2: `outcomes` is the block type vocabulary's word for the ways a
  block can finish, and this list is not that; it is the screen's buttons.
  The other honest answer was open too: declare `outcomes/1` with one
  outcome per button, so the list would be what its old name said and a
  Path could route on the button. This type takes the rename instead, on
  that same ground: a step is one screen whose answers a Path reads from
  `responses`, and its buttons are how the reader leaves the screen, not
  ways the step can finish. `migrate_config/2` renames the key in a
  version 1 block as it resolves.

  ## What the compiled step is

      <state id="s_<id>" initial="s_<id>__waiting">
        <state id="s_<id>__waiting">
          one transition per outcome, on its event, to the done final,
          assigning each response the press carried
        </state>
        <final id="s_<id>__o_done"/>
      </state>

  The waiting state is where an execution rests while a reader looks at
  the screen, so it is the park `StatifierExamples.Signup.Journey` looks
  for: the step's own block id among the execution's active blocks.

  ## Coming back

  Every block of this type is a returnable step: `returnable?/1` answers
  `true` whatever the config. Delivering the reserved event
  `statifier_blocks.back` to an execution resting on a step re-enters the
  step entered before it, which shows that step's screen again with what
  the chart already holds; `StatifierBlocks.Runtime.Back.offered?/3` says
  whether there is such a step. A Path that should not let a reader back
  past some point puts a `core.checkpoint` there.
  """

  use StatifierBlocks.BlockType

  alias StatifierBlocks.{Block, Emission, InvokeStep}
  alias StatifierBlocks.Compiler.Context
  alias StatifierBlocks.Core.Emit
  alias StatifierExamples.Signup.Screen

  # A button's outcome becomes an event name and a response key a datamodel
  # path, so both are held to one segment of either.
  @name ~r/\A[a-z][a-z0-9_]*\z/

  @impl StatifierBlocks.BlockType
  def config_schema(_config) do
    [
      InvokeStep.label_field(),
      %{
        key: "screen",
        type: :string,
        label: "Screen",
        required?: true,
        default: ""
      },
      %{
        key: "buttons",
        type: {:list, :string},
        label: "Its buttons' outcomes",
        required?: true,
        default: []
      },
      %{
        key: "responses",
        type: {:list, :string},
        label: "Its questions' keys",
        required?: false,
        default: []
      }
    ]
  end

  @impl StatifierBlocks.BlockType
  def validate_config(config) do
    findings =
      []
      |> check_screen(Map.get(config, "screen"))
      |> check_names("buttons", Map.get(config, "buttons"), :required)
      |> check_names("responses", Map.get(config, "responses", []), :optional)

    case findings do
      [] -> :ok
      findings -> {:error, Enum.reverse(findings)}
    end
  end

  @doc """
  Version 2: the buttons' list is `buttons`, where version 1 called it
  `outcomes` (the moduledoc's "One outcome, `done`").
  """
  @impl StatifierBlocks.BlockType
  def current_version, do: 2

  @doc """
  The single hop from version 1's `outcomes` to version 2's `buttons`.

  Only the key moves. A version 1 config that carried no `outcomes`
  migrates to one with no `buttons`, which `validate_config/1` then refuses
  as it refused the missing key before.
  """
  @impl StatifierBlocks.BlockType
  def migrate_config(1, config) do
    case Map.pop(config, "outcomes") do
      {nil, rest} -> {:ok, rest}
      {buttons, rest} -> {:ok, Map.put(rest, "buttons", buttons)}
    end
  end

  def migrate_config(from, _config), do: {:error, {:no_migration_from, from}}

  @doc """
  Every block of this type is a returnable step (see the moduledoc).
  """
  @impl StatifierBlocks.BlockType
  def returnable?(_config), do: true

  @impl StatifierBlocks.BlockType
  def palette_entry do
    %{
      label: "Step",
      group: "Signup wizard",
      description: "Shows one screen and waits for a button; a reader may come back to it.",
      icon: "arrow-uturn-left",
      keywords: ["step", "screen", "back", "form"],
      order: 5
    }
  end

  @impl StatifierBlocks.BlockType
  def sentence(config) do
    case Map.get(config, "screen") do
      key when is_binary(key) and key != "" -> "Show the #{key} screen"
      _none -> "Show a screen"
    end
  end

  @impl StatifierBlocks.BlockType
  def emit(%Block{config: config}, context) do
    {:ok, waiting} = Context.role_id(context, "waiting")
    done = Context.done_id(context)
    assigns = Enum.map(Map.get(config, "responses", []), &assign/1)

    presses =
      for outcome <- Map.get(config, "buttons", []) do
        Emit.transition([event: Screen.outcome_event(outcome), target: done], assigns)
      end

    {:ok,
     Emit.state(context.state_id, waiting, [Emit.state(waiting, nil, presses), Emit.final(done)])}
  end

  # `responses.<key>` from the press's data, only where the press carried
  # the key (the moduledoc's "What an author configures").
  @spec assign(String.t()) :: Emission.t()
  defp assign(key) do
    source = "_event.data." <> key

    Emission.element("if", [{"cond", source <> " !== undefined"}], [
      Emission.element("assign", [{"expr", source}, {"location", "responses." <> key}])
    ])
  end

  @spec check_screen([{String.t(), String.t()}], term()) :: [{String.t(), String.t()}]
  defp check_screen(findings, key) when is_binary(key) and key != "", do: findings

  defp check_screen(findings, _key),
    do: [{"screen", "name the screen this step shows"} | findings]

  @spec check_names([{String.t(), String.t()}], String.t(), term(), :required | :optional) ::
          [{String.t(), String.t()}]
  defp check_names(findings, field, [_ | _] = names, _presence) do
    cond do
      not Enum.all?(names, &(is_binary(&1) and Regex.match?(@name, &1))) ->
        [{field, "each must be lower case letters, digits and underscores"} | findings]

      Enum.uniq(names) != names ->
        [{field, "each may be named once"} | findings]

      true ->
        findings
    end
  end

  defp check_names(findings, _field, [], :optional), do: findings
  defp check_names(findings, field, [], :required), do: [{field, "name at least one"} | findings]
  defp check_names(findings, field, _other, _presence), do: [{field, "must be a list"} | findings]
end
