defmodule StatifierExamples.Charts.InvokeHandler do
  @moduledoc """
  The one `Statifier.Invoke.Handler` this app registers, for every
  `myapp:*` type its three handler modules answer.

  Two registries meet here, and they are still two. A block type **names**
  an invoke type and `StatifierExamples.Charts.invoke_types/0` is the union
  of the names; a handler **runs** one, and `Statifier.Session`'s
  `:invoke_handlers` is a `%{type => module}` map of the modules. This
  module is the join: `StatifierExamples.Charts.invoke_handlers/0` points
  every name at it, and it routes the call back to whichever domain module
  registered that name.

  One adapter rather than three behaviour implementations, because the
  three domain modules already share one shape - `invoke_types/0` and
  `handle/2` - and the difference between them is which names they answer,
  which is data. Three modules each implementing four callbacks identically
  would be the same adapter written three times.

  ## The split the behaviour asks for

  `start/2`, `cancel/2` and `forward/3` are pure planning callbacks: they
  return instructions and touch nothing. All the work this app's handlers
  do is therefore in one `{:handler, __MODULE__, payload}` instruction,
  performed later by whatever executor is driving - `Statifier.Session`
  here, and a durable host's own executor in the bead that makes these runs
  survive a restart. Nothing in `perform/2` reaches for a session pid or a
  `%MachineState{}`: the plan context carries neither by construction, and
  the way back to the session is `session_id` through `Statifier.Registry`,
  which is exactly the door a job running on some other machine would use.

  ## Idempotency

  `perform/2` may be called more than once for the same `invoke_id` - a
  host that crashed between performing and recording replays the drive -
  so the contract asks a handler to be idempotent on it. This one is, for
  the least interesting reason available: the domain handlers log a line
  and answer `{:ok, %{}}`, and `Statifier.Session.done_invocation/3` for an
  invocation already reported is documented as a harmless no-op. What a
  second call does duplicate is the log line, which is the honest cost of a
  handler with nothing durable to key on. A handler that created something
  would key its own dedup table on `invoke_id`, and the bead that writes a
  users row is where that first becomes a real obligation rather than a
  sentence.

  ## Reaching the session

  `perform/2` reports the answer with `Statifier.Session.done_invocation/3`
  (or `failed_invocation/3`), against the session `ctx.session_id` names.
  Resolving it needs `Statifier.Registry` running, which is why
  `StatifierExamples.Application` places `Statifier.Supervisor` in its
  tree. An unresolvable session id is `{:error, {:session_not_registered,
  id}}` rather than a raise: the library does not interpret `perform/2`'s
  return, and a session that went away while its call was out is an
  ordinary thing to observe, not an exception - errors are events here too.
  """

  @behaviour Statifier.Invoke.Handler

  alias Statifier.Effect.Invoke
  alias Statifier.Session
  alias StatifierExamples.Charts

  @doc """
  Plans one `{:handler, __MODULE__, payload}` instruction. Pure.

  The payload carries the three facts `perform/2` needs and nothing else:
  the `invoke_id` the answer is reported against, the type to route on, and
  the `<param>` values the block emitted. `params` is `:undefined` when the
  `<invoke>` carried none (`Statifier.EventData`'s own spelling for
  absence), and it is normalized to an empty map here so a handler never
  has to match on two shapes of "no arguments".
  """
  @impl Statifier.Invoke.Handler
  def start(%Invoke{} = invoke, _ctx) do
    payload = %{
      invoke_id: invoke.invoke_id,
      type: invoke.type,
      params: params(invoke.params)
    }

    {:ok, [{:handler, __MODULE__, payload}]}
  end

  @doc """
  Plans nothing. Pure.

  There is nothing to stop: this app's calls are answered inside the
  performing turn, so by the time a cancel could be planned the invocation
  is either already reported or never will be. The contract asks a handler
  to tolerate cancelling an `invoke_id` it does not know, and a handler
  that keeps no table of its own tolerates it by having nothing to look up.
  """
  @impl Statifier.Invoke.Handler
  def cancel(_invoke_id, _ctx), do: {:ok, []}

  @doc """
  Plans nothing. Pure.

  Autoforwarding delivers a parent's external events to a running
  invocation, which is a thing a child *session* has and a logged call does
  not. No block type in this app sets `autoforward`, so this callback is
  reached only by a document that asks for it explicitly, and the honest
  answer for a call with no inbox is to drop the copy.
  """
  @impl Statifier.Invoke.Handler
  def forward(_invoke_id, _event, _ctx), do: {:ok, []}

  @doc """
  Runs one call and reports the answer back to the session. The impure
  half; see the moduledoc on idempotency and on how the session is reached.
  """
  @impl Statifier.Invoke.Handler
  def perform(%{invoke_id: invoke_id, type: type, params: params}, ctx) do
    case Charts.dispatch(type, params) do
      {:ok, donedata} ->
        report(ctx, &Session.done_invocation(&1, invoke_id, donedata))

      {:error, reason} ->
        report(ctx, &Session.failed_invocation(&1, invoke_id, reason: reason(reason)))
    end
  end

  @spec params(term()) :: map()
  defp params(params) when is_map(params), do: params
  defp params(_absent), do: %{}

  # The failure class the chart reads as `_event.data.reason`. A string,
  # because that is what the door documents. One clause and no catch-all:
  # `StatifierExamples.Charts.dispatch/2` declares exactly one failure - a
  # name no domain module registered - so a fallback clause here would be
  # dead code today and a silent `inspect/1` of some future failure that
  # deserved a name of its own. Widening that return widens this, and
  # dialyzer is what says so.
  @spec reason({:unknown_invoke_type, String.t()}) :: String.t()
  defp reason({:unknown_invoke_type, type}), do: "unknown_invoke_type:#{type}"

  @spec report(Statifier.Invoke.Handler.ctx(), (pid() -> :ok)) ::
          :ok | {:error, {:session_not_registered, String.t()}}
  defp report(%{session_id: session_id}, deliver) do
    case whereis(session_id) do
      nil -> {:error, {:session_not_registered, session_id}}
      pid -> deliver.(pid)
    end
  end

  # `Registry.lookup/2` raises when the registry is not running, and this
  # app always runs it - but a test that starts a bare session without the
  # application would otherwise get an ArgumentError out of a reporting
  # path, which is the least useful place to learn that the supervisor is
  # missing. The guard turns it into the same absent-session answer.
  @spec whereis(String.t()) :: pid() | nil
  defp whereis(session_id) do
    if Process.whereis(Statifier.Registry) do
      case Registry.lookup(Statifier.Registry, session_id) do
        [{pid, _value}] -> pid
        [] -> nil
      end
    end
  end
end
