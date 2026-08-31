defmodule StatifierExamples.Charts.InvokeHandlerTest do
  use ExUnit.Case, async: true

  alias Statifier.Effect.Invoke
  alias Statifier.Invoke.Types
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.InvokeHandler

  # The plan context the library hands a planning callback. Built here
  # rather than driven out of a session, which is the whole point of those
  # callbacks being pure: they can be asserted with no process at all.
  defp ctx(session_id \\ "sess_test") do
    %{
      session_id: session_id,
      invoke_types: Types.new(types: Charts.invoke_types()),
      invoke_handlers: Charts.invoke_handlers()
    }
  end

  defp invoke(params) do
    %Invoke{
      invoke_id: "s_blk__running.inv_1",
      type: "myapp:signup",
      params: params,
      state_index: 3,
      invoke_index: 0,
      macrostep: 1,
      microstep: 1,
      round: 1
    }
  end

  # Sabotage: made `start/2` return `{:ok, []}`; this went red on the
  # instruction match, then reverted.
  test "start plans one handler instruction carrying the id, the type and the params" do
    assert {:ok, [{:handler, InvokeHandler, payload}]} =
             InvokeHandler.start(invoke(%{"step" => "account"}), ctx())

    assert payload == %{
             invoke_id: "s_blk__running.inv_1",
             type: "myapp:signup",
             params: %{"step" => "account"}
           }
  end

  # `:undefined` is what `Statifier.EventData` produces for an `<invoke>`
  # with no `<param>` children, and a handler should never have to match on
  # two shapes of "no arguments".
  #
  # Sabotage: dropped the `params(_absent)` clause's normalization so the
  # payload carried `:undefined`; this went red, then reverted.
  test "start normalizes absent params to an empty map" do
    assert {:ok, [{:handler, InvokeHandler, %{params: %{}}}]} =
             InvokeHandler.start(invoke(:undefined), ctx())
  end

  # Sabotage: made `cancel/2` return `{:ok, [{:handler, __MODULE__, :x}]}`;
  # this went red, then reverted.
  test "cancel and forward plan nothing, for an id the handler never saw as much as one it did" do
    assert InvokeHandler.cancel("s_blk__running.inv_1", ctx()) == {:ok, []}
    assert InvokeHandler.cancel("never-existed", ctx()) == {:ok, []}

    assert InvokeHandler.forward("never-existed", Statifier.Event.external("x"), ctx()) ==
             {:ok, []}
  end

  # The reporting path's answer when `ctx.session_id` resolves to nothing -
  # the session died while its call was out, or a bare session was started
  # with no registry. An event, not a raise.
  #
  # Sabotage: made `report/2` raise on a nil lookup instead of answering;
  # this went red, then reverted.
  test "perform answers an error rather than raising when the session is not registered" do
    payload = %{invoke_id: "inv_1", type: "myapp:signup", params: %{"step" => "account"}}

    assert InvokeHandler.perform(payload, ctx("sess_nobody_registered")) ==
             {:error, {:session_not_registered, "sess_nobody_registered"}}
  end

  # A name no domain module registered is routed nowhere. What the adapter
  # does with that is report a permanent failure through
  # `failed_invocation/3`, and what `dispatch/2` does is refuse before any
  # module is called - which is the half worth pinning, because the domain
  # modules would answer their own `{:error, {:unknown_invoke_type, _}}`
  # only if they were reached at all.
  #
  # Sabotage: made `Charts.dispatch/2` answer `{:ok, %{}}` for a name
  # nothing registered; this went red, then reverted. Falling back to a
  # handler module instead would NOT have gone red - the modules answer the
  # same refusal - which is why the mutation is the one that swallows it.
  test "dispatch refuses a name no handler module registered" do
    assert Charts.dispatch("myapp:nobody", %{}) ==
             {:error, {:unknown_invoke_type, "myapp:nobody"}}
  end

  # Sabotage: dropped "myapp:signup" from `Signup.Handlers`' `@invoke_types`;
  # this went red on the routing assertion, then reverted.
  test "dispatch routes a registered name to the module that registered it" do
    assert Charts.dispatch("myapp:signup", %{"step" => "confirm"}) == {:ok, %{}}
    assert Charts.dispatch("myapp:authorize", %{}) == {:ok, %{}}
  end

  # Sabotage: made `invoke_handlers/0` answer `%{}`; this went red on the
  # key-set assertion, then reverted.
  test "every invoke type this app registers points at this adapter" do
    handlers = Charts.invoke_handlers()

    assert Map.keys(handlers) |> Enum.sort() == Charts.invoke_types()
    assert Enum.all?(Map.values(handlers), &(&1 == InvokeHandler))
  end
end
