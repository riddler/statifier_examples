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
  # that keeps something has to name a root the chart can read.
  #
  # Sabotage: made Step.check_assign_to/2 return its findings untouched;
  # the last assertion went red, then reverted.
  test "validate_config/1 passes a blank assign_to and refuses one that is not an identifier" do
    assert :ok == SignupStep.validate_config(config())
    assert :ok == SignupStep.validate_config(config(%{"assign_to" => ""}))
    assert :ok == SignupStep.validate_config(config(%{"assign_to" => "signup"}))

    assert {:error, findings} =
             SignupStep.validate_config(config(%{"assign_to" => "signup.plan"}))

    assert {"assign_to", message} = List.keyfind(findings, "assign_to", 0)
    assert message =~ "identifier"
  end

  # Sabotage: made check_step/2 accept any binary; this went red, then
  # reverted.
  test "validate_config/1 accepts a declared step and refuses one it does not know" do
    assert :ok == SignupStep.validate_config(config())

    assert {:error, [{"step", message}]} =
             SignupStep.validate_config(config(%{"step" => "pick_a_colour"}))

    assert message =~ "account"
  end

  # Sabotage: relaxed @invoke_type to accept any namespace; this went red,
  # then reverted.
  test "validate_config/1 refuses an invoke type outside the example namespace" do
    assert {:error, findings} =
             SignupStep.validate_config(config(%{"invoke_type" => "otherapp:signup"}))

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
