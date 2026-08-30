defmodule StatifierExamples.Charts.MessagingTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias StatifierExamples.Charts.Messaging
  alias StatifierExamples.Charts.Messaging.{Handlers, Notify}

  # The test environment logs at :warning, so an `info` line never reaches a
  # handler to be captured. Raising the level for this module is why it is not
  # async: `Logger.configure/1` is global, and a sibling module running
  # concurrently would see the change.
  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    :ok
  end

  # Sabotage: pointed "myapp.notify" at StatifierExamples.CardAuth.Receipt;
  # this went red, then reverted.
  test "myapp.notify is the messaging vocabulary" do
    assert Messaging.block_types() == %{"myapp.notify" => Notify}
  end

  # Sabotage: changed Notify's group to "Card processing"; this went red, then
  # reverted.
  test "notify files under its own heading, not under either domain" do
    assert %{group: "Messaging", label: "Notify", icon: "megaphone"} = Notify.palette_entry()
  end

  # Sabotage: made Notify.validate_config/1 skip the template check; this went
  # red, then reverted.
  test "notify needs a template that is a bare lowercase identifier" do
    assert Notify.validate_config(%{"template" => "receipt_ready"}) == :ok
    assert {:error, [{"template", _message}]} = Notify.validate_config(%{"template" => ""})
    assert {:error, [{"template", _message}]} = Notify.validate_config(%{})
  end

  # Sabotage: made the notify handler return {:ok, %{"sent" => true}}; this
  # went red, then reverted.
  test "myapp:notify logs one line and completes" do
    log =
      capture_log(fn ->
        assert Handlers.handle("myapp:notify", %{"template" => "receipt_ready"}) == {:ok, %{}}
      end)

    assert log =~ "myapp:notify completed with 1 params"
  end

  # Sabotage: made the fallback clause return {:ok, %{}}; this went red, then
  # reverted.
  test "an invoke type this module does not register is refused" do
    assert Handlers.invoke_types() == ["myapp:notify"]
    assert Handlers.handle("myapp:park", %{}) == {:error, {:unknown_invoke_type, "myapp:park"}}
  end
end
