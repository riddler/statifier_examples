defmodule StatifierExamples.CardAuthTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.CardAuth

  @types %{
    "myapp.authorize" => CardAuth.Authorize,
    "myapp.balance_check" => CardAuth.BalanceCheck,
    "myapp.capture" => CardAuth.Capture,
    "myapp.intake" => CardAuth.Intake,
    "myapp.manual_flag" => CardAuth.ManualFlag,
    "myapp.park" => CardAuth.Park,
    "myapp.receipt" => CardAuth.Receipt,
    "myapp.resolve_review" => CardAuth.ResolveReview,
    "myapp.risk_rating" => CardAuth.RiskRating,
    "myapp.three_ds_challenge" => CardAuth.ThreeDsChallenge
  }

  # Sabotage: dropped "myapp.receipt" from @block_types; this went red, then
  # reverted.
  test "the ten card-processing types register under their myapp names" do
    assert CardAuth.block_types() == @types
  end

  # Sabotage: added "myapp.legacy_check" to @block_types; this went red, then
  # reverted.
  test "myapp.legacy_check stays unregistered" do
    refute Map.has_key?(CardAuth.block_types(), "myapp.legacy_check")
  end

  # Sabotage: made every type file under the "Messaging" group; this went red,
  # then reverted.
  test "every type files under Card processing and points at the host accent" do
    for {_name, module} <- CardAuth.block_types() do
      assert %{group: "Card processing", accent_token: "--sb-accent-myapp"} =
               module.palette_entry()
    end
  end

  # Sabotage: made Step.config_schema/2 drop the invoke_type field; this went
  # red, then reverted.
  test "every type declares label then invoke_type, defaulted to its own" do
    for {_name, module} <- CardAuth.block_types() do
      assert [
               %{key: "label", type: :string, required?: false},
               %{key: "invoke_type", required?: true, default: default} | _rest
             ] = module.config_schema(%{})

      assert default == module.invoke_type()
    end
  end

  # Sabotage: made Step.outcomes/0 return only the done pair; this went red,
  # then reverted.
  test "every type declares the two call outcomes in compile order" do
    for {_name, module} <- CardAuth.block_types() do
      assert module.outcomes(%{}) == [{"done", "Done"}, {"error", "Error"}]
    end
  end

  # Sabotage: made ThreeDsChallenge.current_version/0 return 1; this went red,
  # then reverted.
  test "the two version-2 types say so" do
    assert CardAuth.Authorize.current_version() == 2
    assert CardAuth.ThreeDsChallenge.current_version() == 2
  end

  # Sabotage: pointed @documents at a file that does not exist; this went red,
  # then reverted.
  test "the card-processing fixture is registered and decoded" do
    assert [fixture] = CardAuth.fixtures()
    assert %{key: "card_processing", name: "Card processing"} = fixture

    assert File.exists?(fixture.path)
    assert fixture.document.id == "bdoc_cp_demo"
    assert fixture.document.revision == 43
  end
end
