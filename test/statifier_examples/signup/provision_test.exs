defmodule StatifierExamples.Signup.ProvisionTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType
  alias StatifierExamples.Signup.Provision

  defp config, do: %{"invoke_type" => "myapp:provision"}

  # Sabotage: added a second field to config_schema/1; this went red, then
  # reverted.
  test "provisioning has nothing to configure but the handler it names" do
    assert [%{key: "invoke_type", required?: true, default: "myapp:provision"}] =
             Provision.config_schema(config())

    assert Provision.slots(config()) == []
    assert Provision.current_version() == 1
  end

  # Sabotage: dropped the invoke_type check from validate_config/1; this
  # went red, then reverted.
  test "validate_config/1 refuses a missing handler name" do
    assert :ok == Provision.validate_config(config())
    assert {:error, [{"invoke_type", _message}]} = Provision.validate_config(%{})
  end

  # Sabotage: changed the group to "Structure"; this went red, then
  # reverted.
  test "palette_entry/0 puts provisioning in the wizard's group with the spike's icon" do
    entry = Provision.palette_entry()

    assert %{label: "Provision", group: "Signup wizard", icon: "sparkles", order: 1} = entry
    assert entry.accent_token == "--sb-accent-myapp"
  end

  # Sabotage: made outcomes/1 return only `done`; this went red, then
  # reverted.
  test "provisioning finishes two ways, done first" do
    assert BlockType.outcome_names(Provision, config()) == ["done", "error"]
  end
end
