defmodule StatifierExamples.Signup.HandlersTest do
  # `config/test.exs` puts the Logger at :warning, so capturing an :info
  # line means lowering the primary level for the duration - which is global
  # state, so this one module runs on its own.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias StatifierExamples.Signup.Handlers

  # `config/test.exs` puts the Logger at :warning, and `capture_log`'s own
  # `:level` does not lower the primary level, so a handler's :info line
  # never reaches the capture. Lowering it here is global state for the
  # duration, which is why this one module is not async.
  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)
  end

  # Sabotage: dropped "myapp:provision" from @invoke_types; this went red,
  # then reverted.
  test "invoke_types/0 answers every name the block types name, sorted" do
    assert Handlers.invoke_types() == ["myapp:provision", "myapp:signup"]
  end

  # Sabotage: made handle/2 log the invoke type without the step; this went
  # red, then reverted.
  test "myapp:signup logs the step it collected and answers an empty result" do
    log =
      capture_log(fn ->
        assert {:ok, %{}} == Handlers.handle("myapp:signup", %{"step" => "confirm"})
      end)

    assert log =~ "myapp:signup"
    assert log =~ "confirm"
  end

  # Sabotage: made the myapp:provision clause answer `:ok`; this went red,
  # then reverted.
  test "myapp:provision logs one line and answers an empty result" do
    log =
      capture_log(fn ->
        assert {:ok, %{}} ==
                 Handlers.handle("myapp:provision", %{"email" => "someone@example.com"})
      end)

    assert log =~ "myapp:provision"
  end

  # The half the map-of-functions shape could not express at all: a name
  # this module does not register is an answer, not a `FunctionClauseError`.
  #
  # Sabotage: dropped handle/2's catch-all clause; this went red with a
  # FunctionClauseError, then reverted.
  test "a name this module does not register is refused rather than raised" do
    assert Handlers.handle("myapp:park", %{}) == {:error, {:unknown_invoke_type, "myapp:park"}}
  end
end
