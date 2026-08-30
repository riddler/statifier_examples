defmodule StatifierExamples.ChartsTest do
  use ExUnit.Case, async: true

  alias StatifierBlocks.Palette
  alias StatifierExamples.Charts

  # Sabotage: pointed palette/0 at Palette.new(); the core.sequence assertion
  # went red, then reverted.
  test "the palette carries statifier_blocks' core vocabulary" do
    assert %Palette{types: types} = Charts.palette()
    assert Map.has_key?(types, "core.sequence")
    assert Map.has_key?(types, "core.invoke")
  end

  # Sabotage: dropped Messaging.block_types() from registrations/0; this went
  # red, then reverted.
  test "the palette carries every host type both domains register" do
    assert %Palette{types: types} = Charts.palette()

    host =
      types
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "myapp."))
      |> Enum.sort()

    assert host == [
             "myapp.authorize",
             "myapp.balance_check",
             "myapp.capture",
             "myapp.intake",
             "myapp.manual_flag",
             "myapp.notify",
             "myapp.park",
             "myapp.provision",
             "myapp.receipt",
             "myapp.resolve_review",
             "myapp.risk_rating",
             "myapp.signup_step",
             "myapp.three_ds_challenge"
           ]
  end

  # Sabotage: registered "core.wait" against a host module in registrations/0;
  # this went red, then reverted.
  test "no host registration claims a core name" do
    assert %Palette{types: types} = Charts.palette()

    for {name, module} <- types, String.starts_with?(name, "core.") do
      assert inspect(module) =~ "StatifierBlocks.Core."
    end
  end

  # Sabotage: dropped :brand from @themes; this went red, then reverted.
  test "the host offers three theme tokens" do
    assert Charts.themes() == [:light, :dark, :brand]
  end

  # Sabotage: made icon/1 return the name it was given; this went red, then
  # reverted.
  test "the icon seam resolves nothing yet" do
    assert Charts.icon("core.sequence") == nil
    assert Charts.icon(:compile) == nil
  end

  # Sabotage: made fixtures/0 read only Signup.fixtures(); this went red, then
  # reverted.
  test "the fixture list is both domains', card processing first" do
    assert [
             %{key: "card_processing", name: "Card processing"},
             %{key: "signup_wizard"},
             %{key: "signup_invitations"}
           ] = Charts.fixtures()
  end

  # Sabotage: dropped Signup.Handlers from invoke_types/0; this went red, then
  # reverted.
  test "the invoke-type list is every handler all three registries answer" do
    assert Charts.invoke_types() == [
             "myapp:authorize",
             "myapp:balance_check",
             "myapp:capture",
             "myapp:intake",
             "myapp:manual_flag",
             "myapp:notify",
             "myapp:park",
             "myapp:provision",
             "myapp:receipt",
             "myapp:resolve_review",
             "myapp:risk_rating",
             "myapp:signup",
             "myapp:three_ds"
           ]
  end

  # Sabotage: made fixture/1 raise on an unknown key; this went red, then
  # reverted.
  test "a fixture is found by key, and an unknown key is an ordinary answer" do
    assert {:ok, %{key: "card_processing"}} = Charts.fixture("card_processing")
    assert Charts.fixture("no_such_document") == :error
  end
end
