defmodule StatifierExamples.Signup.SignupStepTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType
  alias StatifierExamples.Signup.SignupStep

  defp config(overrides \\ %{}),
    do: Map.merge(%{"invoke_type" => "myapp:signup", "step" => "account"}, overrides)

  # Sabotage: dropped "confirm" from @steps; this went red, then reverted.
  test "the wizard has its five steps in order" do
    assert SignupStep.steps() == [
             "account",
             "send_verification",
             "company_details",
             "preferences",
             "confirm"
           ]
  end

  # Sabotage: made config_schema/1 return only the invoke_type field; this
  # went red, then reverted.
  test "config_schema/1 declares the label, the handler, the step and where the answers go" do
    assert [label, invoke_type, step, assign_to] = SignupStep.config_schema(config())

    assert %{key: "label", type: :string, required?: false, default: ""} = label
    assert %{key: "invoke_type", required?: true, default: "myapp:signup"} = invoke_type
    assert %{key: "step", required?: true, default: "account", type: {:select, options}} = step
    assert {"send_verification", "send verification"} in options

    assert %{key: "assign_to", type: :string, required?: false, default: ""} = assign_to
  end

  # se-dyo: the answers a step collects go where `assign_to` says, so the
  # key is a datamodel path in the sense ADR-0002 decision 7 means - an
  # author who writes a root the document does not declare gets the
  # editor's advisory rather than an `error.execution` at run time.
  #
  # Sabotage: dropped `datamodel_path?: true` from the declaration; this
  # went red, then reverted.
  test "the answers key is declared as a datamodel path" do
    [_label, _invoke_type, _step, assign_to] = SignupStep.config_schema(config())

    assert BlockType.datamodel_path?(assign_to)
  end

  # An optional key: a step that keeps nothing leaves it empty, and a step
  # that keeps something has to name a path the chart can write.
  #
  # `statifier_blocks` 0.21.0 widened what that means. `InvokeStep`'s
  # `assign_to` takes any datamodel path, dotted or not - the rule
  # `core.assign` and `core.subchart` already applied to the same
  # `<assign>` element - so `signup.plan` passes where it was refused
  # before, and what is still refused is a value that is no path at all.
  # The message moved with the rule, from naming an identifier to naming a
  # datamodel path, and is asserted on the word that actually distinguishes
  # the two.
  #
  # Sabotage: dropped the `InvokeStep.check_assign_to/2` step from
  # `validate_config/1` in signup_step.ex; the refusal assertions went red,
  # then reverted from a backup copy.
  test "validate_config/1 passes any datamodel path for assign_to and refuses what is not one" do
    assert :ok == SignupStep.validate_config(config())
    assert :ok == SignupStep.validate_config(config(%{"assign_to" => ""}))
    assert :ok == SignupStep.validate_config(config(%{"assign_to" => "signup"}))
    assert :ok == SignupStep.validate_config(config(%{"assign_to" => "signup.plan"}))

    assert {:error, findings} =
             SignupStep.validate_config(config(%{"assign_to" => "signup plan"}))

    assert {"assign_to", message} = List.keyfind(findings, "assign_to", 0)
    assert message =~ "datamodel path"
  end

  # Sabotage: made check_step/2 accept any binary; this went red, then
  # reverted.
  test "validate_config/1 accepts a declared step and refuses one it does not know" do
    assert :ok == SignupStep.validate_config(config())

    assert {:error, [{"step", message}]} =
             SignupStep.validate_config(config(%{"step" => "pick_a_colour"}))

    assert message =~ "account"
  end

  # Sabotage: dropped the `InvokeStep.check_invoke_type/2` step from
  # SignupStep.validate_config/1; this went red, then reverted from a backup
  # copy.
  test "validate_config/1 refuses an invoke type outside the namespace:name grammar" do
    assert {:error, findings} =
             SignupStep.validate_config(config(%{"invoke_type" => "not an invoke type"}))

    assert {"invoke_type", _message} = List.keyfind(findings, "invoke_type", 0)
  end

  # Sabotage: dropped :accent_token from palette_entry/0; this went red,
  # then reverted.
  test "palette_entry/0 declares the host accent and the spike's icon" do
    entry = SignupStep.palette_entry()

    assert %{label: "Signup step", group: "Signup wizard", icon: "user-plus"} = entry
    assert entry.accent_token == "--sb-accent-myapp"
  end

  # Sabotage: made outcomes/1 return only `done`; this went red, then
  # reverted.
  test "a step finishes two ways, done first" do
    assert BlockType.outcome_names(SignupStep, config()) == ["done", "error"]
  end

  # Sabotage: made current_version/0 return 2 while the fixtures still say
  # 1; this went red, then reverted.
  test "the config shape is at version 1, which is what the fixtures store" do
    assert SignupStep.current_version() == 1
  end

  # Sabotage: made slots/1 declare an "on_error" slot; this went red, then
  # reverted.
  test "a step is a leaf" do
    assert SignupStep.slots(config()) == []
    assert %{kinds: [:step], produces: :unknown} == SignupStep.io(config())
  end
end
