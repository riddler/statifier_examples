defmodule StatifierExamples.FormPost.IntakeJob do
  @moduledoc """
  The job that takes one stored card application into the library's
  workflow, enqueued by `StatifierExamples.FormPost.CardApplications` in
  the transaction that stored the application.

  Its arguments are `%{"application_id" => id}` and nothing else: a job's
  arguments sit in the jobs table, in plain sight of every dashboard and
  dead letter, and the posted values belong in the host's own table only.

  The browser was answered when the application was stored; this job does
  the engine work afterwards. It reads the application's library system,
  the row's `scope` column and nothing else, and hands the application to
  `statifier_router`'s webhook front, `StatifierRouter.Webhook.handle/3`,
  under `StatifierExamples.FormPost.Router.config/0`. The request carries
  the id three times and no posted value:

    * `:provider_id` is the id as a string, so it is the message id the
      router dedupes on. A second run of this job for the same application
      is that same message, and the router answers it as a duplicate
      without reaching the execution. The row's id is unique across every
      library system, so one binding serves them all;
    * `:raw_body` is the id as a string too. This app's `statifier_router`
      requires a raw body even when the provider id wins, and the id is
      the only body this host has: it never hands the router the posted
      values;
    * `:data` is `%{"application_id" => id}`, the event the binding keys by
      and projects into the execution.

  The router's answer becomes the job's through `StatifierRouter.Webhook.status/1`:
  a `200` is `:ok`, whatever the outcome (a delivery, a duplicate, a drop),
  because the router would answer the same message the same way again; a
  `500` is the router's `{:error, reason}`, which Oban retries. An
  application that is no longer stored is cancelled, since no retry can
  bring it back.
  """

  use Oban.Worker, queue: :card_application_intake

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.FormPost.{CardApplication, Router}
  alias StatifierExamples.Repo
  alias StatifierRouter.Webhook

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"application_id" => id}}) when is_integer(id) do
    case route(id) do
      {:error, {:application_not_found, ^id} = reason} ->
        {:cancel, reason}

      answer ->
        case Webhook.status(answer) do
          200 -> :ok
          500 -> answer
        end
    end
  end

  @doc """
  Routes stored application `id` through the webhook front and answers
  what `StatifierRouter.Webhook.handle/3` answered: `{:ok, outcomes}` or
  the router's `{:error, reason}`.

  Answers `{:error, {:application_not_found, id}}`, before anything is
  routed, when no application has that id.
  """
  @spec route(integer()) :: Webhook.answer() | {:error, {:application_not_found, integer()}}
  def route(id) when is_integer(id) do
    case library_system(id) do
      {:ok, scope} -> Webhook.handle(Router.config(), request(scope, id))
      :error -> {:error, {:application_not_found, id}}
    end
  end

  @doc """
  The webhook request for application `id` of the library system `scope`:
  the id and nothing else, as the moduledoc describes.
  """
  @spec request(String.t(), integer()) :: Webhook.request()
  def request(scope, id) when is_binary(scope) and is_integer(id) do
    message_id = Integer.to_string(id)

    %{
      scope: scope,
      source: Router.source(),
      provider_id: message_id,
      # The raw body is required on this app's statifier_router, even when
      # the provider id wins, so the id stands in for the body this host
      # never hands the router. statifier_router 0.12.0 makes it optional
      # beside a non-empty provider id; the line goes when this app moves
      # to that release.
      raw_body: message_id,
      data: %{"application_id" => id}
    }
  end

  # The library system the application was stored under: the row's
  # `scope` column, read alone. The personal fields are
  # `StatifierExamples.FormPost.CardApplications.Reader`'s to read.
  @spec library_system(integer()) :: {:ok, String.t()} | :error
  defp library_system(id) do
    case Repo.one(from(a in CardApplication, where: a.id == ^id, select: a.scope)) do
      scope when is_binary(scope) -> {:ok, scope}
      nil -> :error
    end
  end
end
