defmodule StatifierExamples.HoldDesk.DeskPost do
  @moduledoc """
  The job that tells a branch desk a hold was placed: one BasicHTTP POST,
  made after the delivery that planned it has committed.

  `StatifierExamples.HoldDesk.execute/2` plans the hold's `<send
  type="basichttp">` with `StatifierRouter.BasicHTTP.deliver/3` and
  inserts one of these jobs for the POST it planned, through `new/3`. The
  executor runs inside the delivery's transaction, and this app's Oban
  writes through the same repo, so the job commits with the step that
  sent and a delivery that rolls back takes the job with it. The job
  carries the planned instruction and the plan context as they were
  planned, written out with `:erlang.term_to_binary/1`, since the
  instruction holds a struct and a module that job arguments cannot.

  The job is unique on `key`, the send's dedup key written out: a
  redriven step re-emits the same send with the same fields and inserts
  nothing new.

  `perform/1` makes the POST with `StatifierRouter.BasicHTTP.perform/2`.
  It runs outside every delivery, so a slow desk holds no transaction, no
  execution lock and no SQLite write lock while it answers. A POST the
  desk does not take is retried; once the third POST has failed too, the
  job delivers `error.communication`, carrying the send's id, back into
  the hold through `StatifierRouter.Delivery.deliver_event/4`, over the
  hold's address row, with `create: :never`. That is the only way back in
  `statifier_router` sanctions for a send performed after the commit (its
  ADR-0002, the Amendment on the outbound BasicHTTP send). A delivery
  that does not settle is retried on the attempts left, without posting
  again; a failure that reaches no execution - a hold already finished, or an
  address row already reaped - is cancelled, which keeps the job and its
  reason in the jobs table as the dead letter.
  """

  use Oban.Worker,
    queue: :desk_posts,
    max_attempts: 5,
    unique: [keys: [:key], period: :infinity]

  # The attempts that POST; the ones after them only deliver the failure.
  @post_attempts 3

  alias Statifier.Effect.Send
  alias StatifierExamples.HoldDesk
  alias StatifierRouter.{Addresses, BasicHTTP, Delivery}

  # The plan the failure is delivered under. The id is this app's own and
  # is neither `execution`, `basichttp` nor a binding's, so the ledger and
  # dedupe rows it writes are told apart from theirs; the horizon is the
  # router's default dedupe horizon, 72 hours.
  @failure_plan %{
    id: "desk_post_failure",
    create: :never,
    dedupe: %{by: :message_id, horizon_ms: 259_200_000}
  }

  @doc """
  The job for one planned instruction's `payload`, sent by `send` from the
  execution `ctx.session_id` names.
  """
  @spec new(term(), map(), Send.t()) :: Oban.Job.changeset()
  def new(payload, %{session_id: execution_id} = ctx, %Send{} = send) do
    new(%{
      "execution_id" => execution_id,
      "send_id" => send.send_id,
      "key" => key(execution_id, send),
      "instruction" => Base.encode64(:erlang.term_to_binary({payload, ctx}))
    })
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) when attempt <= @post_attempts do
    {payload, ctx} = args["instruction"] |> Base.decode64!() |> :erlang.binary_to_term([:safe])

    case BasicHTTP.perform(payload, ctx) do
      :ok -> :ok
      {:error, reason} when attempt < @post_attempts -> {:error, reason}
      {:error, reason} -> failed(args, reason)
    end
  end

  # Every POST attempt failed and the failure's delivery did not settle:
  # deliver it again, without posting again.
  def perform(%Oban.Job{args: args}), do: failed(args, :desk_post_attempts_spent)

  # The POST has failed for good: tell the hold, or keep a dead letter.
  @spec failed(map(), term()) :: :ok | {:error, term()} | {:cancel, term()}
  defp failed(%{"execution_id" => execution_id} = args, reason) do
    config = HoldDesk.config()

    case Addresses.by_execution(config, execution_id) do
      nil ->
        {:cancel, {:desk_unreached_without_execution, reason}}

      row ->
        event =
          Statifier.Event.external("error.communication",
            sendid: args["send_id"],
            data: %{"reason" => inspect(reason)}
          )

        config
        |> Delivery.deliver_event(Map.put(@failure_plan, :document, row.document), row.key, %{
          event: event,
          message_id: args["key"],
          scope: row.scope,
          now: DateTime.utc_now()
        })
        |> settled(reason)
    end
  end

  @spec settled(StatifierRouter.outcome() | {:error, term()}, term()) ::
          :ok | {:error, term()} | {:cancel, term()}
  defp settled({:delivered, _plan, _execution_id}, _reason), do: :ok
  defp settled({:duplicate, _plan}, _reason), do: :ok
  defp settled({:dropped, _plan, why}, reason), do: {:cancel, {:desk_unreached, why, reason}}
  defp settled({:error, _reason} = error, _reason_sent), do: error

  # The send's dedup key, the fields the `scxml-send-key` header carries,
  # each nil written as "-".
  @spec key(String.t(), Send.t()) :: String.t()
  defp key(execution_id, send) do
    Enum.map_join(
      [
        execution_id,
        send.send_id,
        send.macrostep,
        send.microstep,
        send.round,
        send.c_index,
        owner(send.owner),
        send.ordinal
      ],
      "/",
      &field/1
    )
  end

  @spec field(String.t() | non_neg_integer() | nil) :: String.t()
  defp field(nil), do: "-"
  defp field(value) when is_integer(value), do: Integer.to_string(value)
  defp field(value), do: URI.encode_www_form(value)

  @spec owner(Send.owner() | nil) :: String.t() | nil
  defp owner({kind, state, block}), do: "#{kind}.#{state}.#{block}"
  defp owner({:transition, transition}), do: "transition.#{transition}"
  defp owner(nil), do: nil
end
