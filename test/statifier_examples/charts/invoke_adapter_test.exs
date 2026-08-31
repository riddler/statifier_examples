defmodule StatifierExamples.Charts.InvokeAdapterTest do
  @moduledoc """
  What `StatifierExamples.Charts` owns now that the invoke adapter is the
  engine's.

  This file used to assert the four `Statifier.Invoke.Handler` callbacks
  the app wrote by hand in `StatifierExamples.Charts.InvokeHandler`:
  planning one instruction, planning nothing for cancel and forward,
  answering rather than raising when a session id resolves to nothing.
  Those are `Statifier.Invoke.SyncHandler.Adapter`'s now, tested where they
  live, and re-asserting them here would test the dependency (se-4dt.2).

  `dispatch/3` is the exception and stays asserted here: it is the app's
  own routing for `StatifierExamples.Charts.Durable`, which drives the pure
  core with no session to report to and so never reaches the adapter's
  `perform/2` at all.

  What is still this app's is the handler **list** the adapter is generated
  over, and what falls out of it: which names this app answers, that the
  compiler's set and the session's map are two readings of that one list,
  and which module answers a given name. Every sabotage below is therefore
  a mutation of that list or of a domain module's own `invoke_types/0` -
  app code, not the dependency's.
  """

  use ExUnit.Case, async: true

  alias StatifierExamples.Charts

  # Sabotage: dropped `Signup.Handlers` from the `use ... handlers:` list in
  # `StatifierExamples.Charts`; this went red on the key-set assertion, with
  # the two signup names missing from both readings. Reverted from a backup
  # copy.
  test "the compiler's set and the session's map are two readings of one handler list" do
    handlers = Charts.invoke_handlers()

    assert handlers |> Map.keys() |> Enum.sort() == Charts.invoke_types()
    assert Enum.all?(Map.values(handlers), &(&1 == Charts))
  end

  # The list is what the adapter routes against, in the order this app
  # wrote it.
  #
  # Sabotage: dropped `Messaging.Handlers` from the `use ... handlers:`
  # list; this went red on the list assertion. Reverted from a backup copy.
  #
  # What this does NOT prove is that the ORDER is load-bearing: it is not,
  # today. `dispatch/4` resolves a type to the first module claiming it,
  # and no name here is claimed twice, so reordering the list changes
  # nothing observable. The order is asserted because it is what the app
  # wrote, not because a behaviour hangs off it.
  test "sync_handlers/0 is the three domain modules the adapter is generated over" do
    assert Charts.sync_handlers() == [
             StatifierExamples.CardAuth.Handlers,
             StatifierExamples.Charts.Messaging.Handlers,
             StatifierExamples.Signup.Handlers
           ]
  end

  # A name no domain module registered is routed nowhere, and the refusal
  # comes before any module is called - which is the half worth pinning,
  # because the domain modules would answer their own
  # `{:error, {:unknown_invoke_type, _}}` only if they were reached at all.
  #
  # Sabotage: made `dispatch/3`'s `nil` branch answer `{:ok, %{}}`; this
  # went red. Making it fall through to the first handler module instead
  # would NOT have gone red - the modules answer the same refusal - which
  # is why the mutation is the one that swallows it. Reverted from a backup
  # copy.
  test "dispatch refuses a name no handler module registered" do
    assert Charts.dispatch("myapp:nobody", %{}) ==
             {:error, {:unknown_invoke_type, "myapp:nobody"}}
  end

  # Sabotage: dropped "myapp:signup" from `Signup.Handlers`' `@invoke_types`;
  # this went red on the routing assertion, which then refused the name
  # nothing claimed. Reverted from a backup copy.
  test "dispatch routes a registered name to the module that registered it" do
    assert Charts.dispatch("myapp:signup", %{"step" => "confirm"}) == {:ok, %{}}
    assert Charts.dispatch("myapp:authorize", %{}) == {:ok, %{}}
  end

  # The durable driver is the only caller that passes a context, and it is
  # the one the run-keyed clause in `Signup.Handlers` matches on. The
  # session driver reaches the same handlers through the adapter with the
  # engine's plan context, which names no run - so the run-less clause is
  # what a session gets, and that is the branch this asserts.
  #
  # Sabotage: made the run-less `myapp:provision` clause answer
  # `{:ok, %{"provisioned" => "created"}}`; this went red. Reverted from a
  # backup copy.
  test "a driver with no run to name gets the clause that says so" do
    ExUnit.CaptureLog.capture_log(fn ->
      assert Charts.dispatch("myapp:provision", %{}, %{session_id: "sess_test"}) ==
               {:ok, %{"provisioned" => "skipped"}}
    end)
  end
end
