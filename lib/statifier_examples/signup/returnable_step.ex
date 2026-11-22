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
    * `outcomes` - the outcomes of the screen's buttons. Pressing any of
      them finishes the step; the press raises
      `StatifierExamples.Signup.Screen.outcome_event/1` of the outcome,
      the same event a `myapp.screen` button raises.
    * `responses` - the keys of the questions on the screen. Each press
      writes `responses.<key>` from the key of the same name in the
      press's data, and only where the press carried it, so a response the
      chart already holds is not overwritten by a press that left it out.

  The step finishes as `done` whichever button was pressed: it has one
  outcome, and a Path that wants to branch on a button reads what the
  press recorded rather than which outcome the step finished with.

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

  # An outcome becomes an event name and a response key a datamodel path,
  # so both are held to one segment of either.
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
        key: "outcomes",
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
      |> check_names("outcomes", Map.get(config, "outcomes"), :required)
      |> check_names("responses", Map.get(config, "responses", []), :optional)

    case findings do
      [] -> :ok
      findings -> {:error, Enum.reverse(findings)}
    end
  end

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
      for outcome <- Map.get(config, "outcomes", []) do
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
