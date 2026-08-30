defmodule StatifierExamples.CardAuth.ConfigTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.CardAuth.{Authorize, Capture, Intake, Park}

  describe "the shared invoke_type check" do
    # Sabotage: made Step.check_invoke_type/2 pass every stored value; this
    # went red, then reverted.
    test "refuses a stored invoke type outside the myapp namespace" do
      assert {:error, [{"invoke_type", message}]} =
               Intake.validate_config(%{"invoke_type" => "other:intake"})

      assert message =~ "myapp:"
    end

    # Sabotage: made Step.check_invoke_type/2 refuse an absent key; this went
    # red, then reverted.
    test "reads an absent invoke type through the declared default" do
      assert Intake.validate_config(%{}) == :ok
    end
  end

  describe "myapp.park" do
    # Sabotage: made Park.validate_config/1 skip the queue check; this went
    # red, then reverted.
    test "needs a queue that is a bare lowercase identifier" do
      assert Park.validate_config(%{"queue" => "manual_review"}) == :ok
      assert {:error, [{"queue", _message}]} = Park.validate_config(%{"queue" => "Manual Review"})
      assert {:error, [{"queue", _message}]} = Park.validate_config(%{})
    end
  end

  describe "myapp.capture" do
    # Sabotage: made Capture.check_retries/2 accept any stored value; this
    # went red, then reverted.
    test "accepts a whole retry count and refuses anything else" do
      assert Capture.validate_config(%{"amount_key" => "amount_cents", "retries" => 3}) == :ok
      assert Capture.validate_config(%{"amount_key" => "amount_cents"}) == :ok

      assert {:error, [{"retries", _message}]} =
               Capture.validate_config(%{"amount_key" => "amount_cents", "retries" => true})
    end

    # Sabotage: renamed Capture's @invoke_type to "myapp:settle"; this went
    # red, then reverted.
    test "the retry block's config carries no invoke type and still names one" do
      assert {:ok, module} =
               StatifierBlocks.Palette.fetch(StatifierExamples.Charts.palette(), "myapp.capture")

      assert module == Capture
      assert Capture.invoke_type() == "myapp:capture"
      assert Capture.validate_config(%{"amount_key" => "amount_cents"}) == :ok
    end
  end

  describe "myapp.authorize" do
    # Sabotage: made check_timeout/2 skip a stored value; this went red, then
    # reverted.
    test "checks a stored timeout and reads an absent one through the default" do
      assert Authorize.validate_config(%{"assign_to" => "auth", "timeout" => "1h30m"}) == :ok
      assert Authorize.validate_config(%{"assign_to" => "auth", "timeout" => "PT30S"}) == :ok
      assert Authorize.validate_config(%{"assign_to" => "auth"}) == :ok

      assert {:error, [{"timeout", _message}]} =
               Authorize.validate_config(%{"assign_to" => "auth", "timeout" => "soon"})
    end

    # Sabotage: made migrate_config/2 keep the "field" key; this went red, then
    # reverted.
    test "migrates version 1's field key to version 2's assign_to" do
      assert {:ok, migrated} =
               Authorize.migrate_config(1, %{
                 "field" => "auth",
                 "invoke_type" => "myapp:authorize"
               })

      assert migrated == %{"assign_to" => "auth", "invoke_type" => "myapp:authorize"}
    end

    # Sabotage: made migrate_config/2 default to an empty assign_to; this went
    # red, then reverted.
    test "a version 1 config with no field key migrates to the declared default" do
      assert {:ok, %{"assign_to" => "authorization"}} = Authorize.migrate_config(1, %{})
    end

    # Sabotage: made migrate_config/2 answer {:ok, config} for every version;
    # this went red, then reverted.
    test "refuses a version it has no hop from" do
      assert Authorize.migrate_config(4, %{}) == {:error, {:no_migration_from, 4}}
    end
  end
end
