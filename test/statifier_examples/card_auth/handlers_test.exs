defmodule StatifierExamples.CardAuth.HandlersTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias StatifierExamples.CardAuth.Handlers

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

  @invoke_types [
    "myapp:authorize",
    "myapp:balance_check",
    "myapp:capture",
    "myapp:intake",
    "myapp:manual_flag",
    "myapp:park",
    "myapp:receipt",
    "myapp:resolve_review",
    "myapp:risk_rating",
    "myapp:three_ds"
  ]

  # Sabotage: dropped "myapp:park" from @invoke_types in the handler module;
  # this went red, then reverted.
  test "the handler registry names every invoke type the block types do" do
    assert Handlers.invoke_types() == @invoke_types

    named =
      StatifierExamples.CardAuth.block_types()
      |> Map.values()
      |> Enum.map(& &1.invoke_type())
      |> Enum.sort()

    assert named == @invoke_types
  end

  for invoke_type <- @invoke_types do
    # Sabotage: removed this clause from handle/2, so it fell through to the
    # unknown-type arm; this went red, then reverted.
    test "#{invoke_type} logs one line and completes" do
      log =
        capture_log(fn ->
          assert Handlers.handle(unquote(invoke_type), %{"amount_cents" => 42_350}, %{}) ==
                   {:ok, %{}}
        end)

      assert log =~ "#{unquote(invoke_type)} completed with 1 params"
    end
  end

  # Sabotage: made the fallback clause return {:ok, %{}}; this went red, then
  # reverted.
  test "an invoke type nobody registered is refused rather than answered" do
    assert Handlers.handle("myapp:nowhere", %{}, %{}) ==
             {:error, {:unknown_invoke_type, "myapp:nowhere"}}
  end
end
