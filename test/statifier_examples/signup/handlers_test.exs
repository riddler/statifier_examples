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
  test "myapp:signup logs the step it collected" do
    log =
      capture_log(fn ->
        assert {:ok, _answers} = Handlers.handle("myapp:signup", %{"step" => "confirm"}, %{})
      end)

    assert log =~ "myapp:signup"
    assert log =~ "confirm"
  end

  # se-dyo. The handler collects, and what it collects is what the chart
  # writes wherever the calling block's `assign_to` points. The wizard used
  # to carry these three values as a `core.assign` object literal in its own
  # bytes because this answered `{:ok, %{}}`, which taught the reader that a
  # chart invents its own data.
  #
  # Sabotage: made answers/1 answer `%{}` for "account"; this went red, and
  # took the two wizard run tests in `DurableTest` with it - the plan branch
  # had nothing to guard on again. Reverted.
  test "myapp:signup answers with what the account step collected" do
    capture_log(fn ->
      assert {:ok, answers} = Handlers.handle("myapp:signup", %{"step" => "account"}, %{})

      assert answers == %{"plan" => "business", "seats" => 5, "email_verified" => false}
    end)
  end

  # The steps whose answer the chart keeps nothing of. Their blocks carry no
  # `assign_to`, so an answer here would be discarded on the way past, and
  # inventing one would put values in the handler that no chart reads.
  #
  # Sabotage: made answers/1's catch-all clause return the account map; this
  # went red, then reverted.
  test "the steps the wizard keeps nothing from answer with nothing" do
    capture_log(fn ->
      for step <- ["send_verification", "company_details", "preferences", "confirm"] do
        assert {:ok, %{}} == Handlers.handle("myapp:signup", %{"step" => step}, %{})
      end
    end)
  end

  # Sabotage: dropped the run-less provisioning clause's "skipped" answer to
  # `{:ok, %{}}`; this went red, then reverted.
  test "myapp:provision with no run to key on writes nothing and says so" do
    log =
      capture_log(fn ->
        assert {:ok, %{"provisioned" => "skipped"}} ==
                 Handlers.handle("myapp:provision", %{"email" => "someone@example.com"}, %{})
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
    assert Handlers.handle("myapp:park", %{}, %{}) ==
             {:error, {:unknown_invoke_type, "myapp:park"}}
  end
end
