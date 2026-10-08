defmodule StatifierExamples.FormPost.NewsletterRoute do
  @moduledoc """
  The card application form's route to the events newsletter list,
  `newsletter`: the sink an application's execution reaches through a
  typed send.

  The route runs inside the delivery's transaction, under the execution's
  serialization, so it may only hand off durably. Here the list is a
  stand-in: it assigns a fictional subscription reference from the
  application's id. This stand-in is in the app and writes through the
  same repo, so its outbox row and the write-back commit or roll back with
  the delivery. A host whose system is truly outside inserts a job here,
  as `StatifierExamples.RoutedWorkflow.DoorstepRoute` does, and calls the
  outside system from that job, never from the route.

  The application id comes from the event's data, which carries the id and
  the chart's words only. The route reads the application through
  `StatifierExamples.FormPost.CardApplications.Reader` under the library
  system, and answers `{:error, reason}` before any write when it cannot
  hand the application on:

    * `{:no_application_id, keys}` - the event's data holds no application id
    * `{:application_not_found, id}` - no such application in this library system
    * `{:newsletter_not_requested, id}` - the application did not ask for the newsletter

  A reason carries the application id or the data's keys, never a value the
  visitor typed. An adapter that swallowed its error would remove
  `error.communication` from the chart.

  A route owes at-most-once on the router's key. The outbox row is unique
  on `(route, key)`, so a redriven delivery writes nothing new.
  """

  @behaviour StatifierRouter.Route

  alias StatifierExamples.FormPost.CardApplication
  alias StatifierExamples.FormPost.CardApplications.Reader
  alias StatifierExamples.FormPost.{Sends, Steps}

  @route "newsletter"

  @doc "The route's name in the outbox and in the router configuration."
  @spec route_name() :: String.t()
  def route_name, do: @route

  @impl StatifierRouter.Route
  @spec deliver(map(), Statifier.Event.t(), StatifierRouter.Route.idempotency_key()) ::
          :ok | {:error, term()}
  def deliver(_route_config, %Statifier.Event{} = event, key) do
    scope = Steps.library_system()

    with {:ok, id} <- Sends.application_id(event),
         {:ok, application} <- fetch(scope, id),
         :ok <- requested(application) do
      Sends.record(@route, scope, id, reference(id), Sends.key(key))
    end
  end

  @spec fetch(String.t(), integer()) ::
          {:ok, CardApplication.t()} | {:error, {:application_not_found, integer()}}
  defp fetch(scope, id) do
    case Reader.fetch(scope, id) do
      {:ok, application} -> {:ok, application}
      {:error, :not_found} -> {:error, {:application_not_found, id}}
    end
  end

  @spec requested(CardApplication.t()) :: :ok | {:error, {atom(), integer()}}
  defp requested(%CardApplication{wants_newsletter: true}), do: :ok
  defp requested(%CardApplication{id: id}), do: {:error, {:newsletter_not_requested, id}}

  # A subscription reference, fictional and deterministic from the id.
  @spec reference(integer()) :: String.t()
  defp reference(id), do: "RPL-N-" <> String.pad_leading(Integer.to_string(id), 6, "0")
end
