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

  # Sabotage: dropped "myapp:provision" from handlers/0; this went red, then
  # reverted.
  test "handlers/0 answers a function per invoke type the block types name" do
    handlers = Handlers.handlers()

    assert handlers |> Map.keys() |> Enum.sort() == ["myapp:provision", "myapp:signup"]
    assert Enum.all?(Map.values(handlers), &is_function(&1, 1))
  end

  # Sabotage: made signup/1 log the invoke type without the step; this went
  # red, then reverted.
  test "myapp:signup logs the step it collected and answers an empty result" do
    log =
      capture_log(fn ->
        assert {:ok, %{}} == Handlers.signup(%{"step" => "confirm"})
      end)

    assert log =~ "myapp:signup"
    assert log =~ "confirm"
  end

  # Sabotage: made provision/1 answer `:ok`; this went red, then reverted.
  test "myapp:provision logs one line and answers an empty result" do
    log =
      capture_log(fn ->
        assert {:ok, %{}} == Handlers.provision(%{"email" => "someone@example.com"})
      end)

    assert log =~ "myapp:provision"
  end
end
