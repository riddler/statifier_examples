defmodule StatifierExamples.CardAuth.ConfigTest do
  use ExUnit.Case, async: true

  alias StatifierExamples.CardAuth.{Authorize, Capture, Intake, Park}

  describe "the shared invoke_type check" do
    # se-4dt.1 moved this check onto `StatifierBlocks.InvokeStep`, and with
    # it onto the one `namespace:name` grammar ADR-0007 decision 2 gives
    # `core.invoke` and every host step alike. This app's types used to
    # narrow it further to `myapp:*`; they no longer do, because two
    # spellings of one field are two chances for a core block and a host
    # step to disagree about it. A stored value still has to be in the
    # grammar, which is what this asserts.
    #
    # Sabotage: overrode Intake.validate_config/1 to answer `:ok`; this went
    # red, then reverted from a backup copy.
    test "refuses a stored invoke type outside the namespace:name grammar" do
      assert {:error, [{"invoke_type", message}]} =
               Intake.validate_config(%{"invoke_type" => "not an invoke type"})

      assert message =~ "namespace:name"
    end

    # Sabotage: made the app's step types refuse an absent key; this went
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
    # se-6pn removed the optional `timeout` duration this type used to
    # declare, render and validate: it took `StatifierBlocks.InvokeStep`'s
    # default emit, so no compiled artifact ever carried the value. A
    # deadline in this vocabulary is the recorded pair of blocks around a
    # step (statifier_blocks ADR-0010), not a property on it, so the field
    # is gone rather than wired up. This is the flipped version of the test
    # that used to pin its validation: the palette must not offer the field
    # again, and nothing may validate a stored one as if it were honoured.
    #
    # Sabotage: put the timeout field back on the type's `fields:` list; this
    # went red, then reverted.
    test "declares no timeout field, and validates no stored one" do
      refute Enum.any?(Authorize.config_schema(%{}), &(&1.key == "timeout"))

      assert Authorize.validate_config(%{"assign_to" => "auth", "timeout" => "soon"}) == :ok
      assert Authorize.validate_config(%{"assign_to" => "auth"}) == :ok
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
