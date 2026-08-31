defmodule StatifierExamples.Signup.ProvisionTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.BlockType
  alias StatifierExamples.Signup.Provision

  defp config, do: %{"invoke_type" => "myapp:provision"}

  # Sabotage: added a third field to config_schema/1; this went red, then
  # reverted.
  test "provisioning has nothing to configure but the label and the handler" do
    assert [
             %{key: "label", type: :string, required?: false},
             %{key: "invoke_type", required?: true, default: "myapp:provision"}
           ] = Provision.config_schema(config())

    assert Provision.slots(config()) == []
    assert Provision.current_version() == 1
  end

  # se-4dt.1 moved this type onto `StatifierBlocks.InvokeStep`, and with it
  # onto that base's rule for an absent `invoke_type`: a config that stores
  # none is naming the declared default, which is the one place "the usual
  # handler" is written down. A stored value is still checked, against the
  # shared `namespace:name` grammar rather than this app's old `myapp:*`
  # narrowing.
  #
  # Sabotage: overrode Provision.validate_config/1 to answer `:ok`; the
  # ungrammatical assertion went red, then reverted from a backup copy.
  test "validate_config/1 checks a stored handler name and passes an absent one" do
    assert :ok == Provision.validate_config(config())
    assert :ok == Provision.validate_config(%{})

    assert {:error, [{"invoke_type", _message}]} =
             Provision.validate_config(%{"invoke_type" => "not an invoke type"})
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
