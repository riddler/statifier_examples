defmodule StatifierExamples.Signup.HandlersTest do
  # `config/test.exs` puts the Logger at :warning, so capturing an :info
  # line means lowering the primary level for the duration - which is global
  # state, so this one module runs on its own.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Signup.Accounts
  alias StatifierExamples.Signup.Handlers

  # `config/test.exs` puts the Logger at :warning, and `capture_log`'s own
  # `:level` does not lower the primary level, so a handler's :info line
  # never reaches the capture. Lowering it here is global state for the
  # duration, which is why this one module is not async.
  setup do
    level = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: level) end)

    :ok = Sandbox.checkout(StatifierExamples.Repo)

    %{run: "handlers-#{System.unique_integer([:positive])}"}
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

  # Sabotage: dropped the run-less provisioning clause's "skipped" answer to
  # `{:ok, %{}}`; this went red, then reverted.
  test "myapp:provision with no run to key on writes nothing and says so" do
    log =
      capture_log(fn ->
        assert {:ok, %{"provisioned" => "skipped"}} ==
                 Handlers.handle("myapp:provision", %{"email" => "someone@example.com"})
      end)

    assert log =~ "myapp:provision"
    assert log =~ "skipped"
  end

  # The clause a durable run reaches: the context names the run, so the
  # write has a key and happens. The row itself is
  # `StatifierExamples.Signup.AccountsTest`'s subject; what this asserts is
  # that the handler routes on the context rather than ignoring it.
  #
  # Sabotage: narrowed the `%{run_id: run_id}` clause's guard to
  # `is_atom(run_id)`, so the call fell through to the run-less clause;
  # this went red, then reverted.
  test "myapp:provision with a run provisions the account and reports it", %{run: run_id} do
    log =
      capture_log(fn ->
        assert {:ok, %{"account" => account, "provisioned" => "created"}} =
                 Handlers.handle("myapp:provision", %{}, %{run_id: run_id})

        assert account == Accounts.email_for(run_id)
      end)

    assert log =~ "created the account"
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
