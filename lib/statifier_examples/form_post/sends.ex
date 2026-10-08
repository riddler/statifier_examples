defmodule StatifierExamples.FormPost.Sends do
  @moduledoc """
  What the card application's two routes share: reading the application id
  off the event, spelling the router's key, and recording one hand-off.

  The event a route is handed carries the application's id and the chart's
  words, nothing else. `application_id/1` refuses any other shape with the
  event's keys, never its values.

  `record/5` writes the outbox row and the reference on the application
  together. A route runs inside the delivery's transaction, and a rollback
  inside a nested Ecto transaction marks the delivery's own transaction as
  rolled back. So every refusal is decided before the first write, and the
  writes here only raise.
  """

  alias StatifierExamples.FormPost.CardApplications.Writer
  alias StatifierExamples.FormPost.CardApplicationSend
  alias StatifierExamples.Repo

  @doc """
  The application id out of an event's data.

  Answers `{:ok, id}` when the data is a map holding an integer
  `"application_id"`; other keys, the chart's declared words, are allowed
  and ignored. Otherwise answers `{:error, {:no_application_id, keys}}`
  with the data's keys sorted (`[]` when the data is not a map). The
  refusal names keys and never values.
  """
  @spec application_id(Statifier.Event.t()) ::
          {:ok, integer()} | {:error, {:no_application_id, [term()]}}
  def application_id(%Statifier.Event{data: %{"application_id" => id}}) when is_integer(id),
    do: {:ok, id}

  def application_id(%Statifier.Event{data: data}) when is_map(data),
    do: {:error, {:no_application_id, data |> Map.keys() |> Enum.sort()}}

  def application_id(%Statifier.Event{}), do: {:error, {:no_application_id, []}}

  @doc """
  The router's key as one string: the scope half, where in the step the
  hand-off sat, and the ordinal, which the completion hook never carries.
  """
  @spec key(StatifierRouter.Route.idempotency_key()) :: String.t()
  def key({scope, position, ordinal}) do
    Enum.join(
      [scope, position.macrostep, position.microstep, position.round, ordinal || "-"],
      ":"
    )
  end

  @doc """
  Records that application `id` of the library system `scope` was handed
  to `route`, and that the outside system answered `reference`.

  The outbox row is inserted unique on `(route, router_key)`. When the row
  is new, the reference is written back to the application; when the key
  was already recorded (a redrive), nothing is written. Answers `:ok`.
  """
  @spec record(String.t(), String.t(), integer(), String.t(), String.t()) :: :ok
  def record(route, scope, id, reference, router_key) do
    # The struct is valid by construction, so the insert raises rather than
    # answering an error tuple: see the moduledoc on nested rollbacks.
    {:ok, :ok} =
      Repo.transaction(fn ->
        sent =
          Repo.insert!(
            %CardApplicationSend{
              application_id: id,
              route: route,
              outside_reference: reference,
              idempotency_key: router_key
            },
            on_conflict: :nothing,
            conflict_target: [:route, :idempotency_key]
          )

        case sent.id do
          nil -> :ok
          _id -> :ok = Writer.record_reference(scope, id, route, reference)
        end
      end)

    :ok
  end
end
