defmodule StatifierExamples.FormPost.CardApplications.Writer do
  @moduledoc """
  The one module that updates a stored card application after the post is
  stored: it writes the outside system's reference back to the row, it
  marks an application the screen turned away, and it clears the personal
  fields once the host's retention says so.

  One writer, as `StatifierExamples.FormPost.CardApplications.Reader` is
  one reader: a reviewer reads this module's callers to see every later
  write to the host's table. The update is always under a library system,
  so a route working for the wrong library system cannot write to a
  neighbour's application by guessing its id.
  """

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.FormPost.CardApplication
  alias StatifierExamples.Repo

  @doc """
  Records `reference` on application `id` stored by the library system
  `scope`, and marks the application `sent` once every route it asked for
  has its reference.

  `route` is `"patron_system"`, whose reference goes in
  `external_reference`, or `"newsletter"`, whose reference goes in
  `newsletter_reference`. Answers `:ok`, or `{:error, :not_found}` when no
  application with that id is stored under that library system.

  The status says that the application was handed on to every route it
  asked for: `wants_card` asks for the patron system and
  `wants_newsletter` for the newsletter list. An application that asked
  for both stays as it is while one route has answered, and the hand-off
  that completes it writes `sent`. Every hand-off moves `updated_at`, so
  the stamp the host's sent age is measured from is the last route's, and
  a second route still retrying never finds the first route's age already
  running and its fields cleared. Which hand-offs happened is read from
  the two reference columns, each written only by its own route.
  """
  @spec record_reference(String.t(), integer(), String.t(), String.t()) ::
          :ok | {:error, :not_found}
  def record_reference(scope, id, route, reference)
      when is_binary(scope) and is_integer(id) and route in ["patron_system", "newsletter"] and
             is_binary(reference) do
    query = from(a in CardApplication, where: a.scope == ^scope and a.id == ^id)

    case Repo.update_all(query, set: reference_set(route, reference)) do
      {0, _} ->
        {:error, :not_found}

      {_count, _} ->
        complete =
          from(a in query,
            where: not a.wants_card or not is_nil(a.external_reference),
            where: not a.wants_newsletter or not is_nil(a.newsletter_reference)
          )

        Repo.update_all(complete, set: [status: "sent"])
        :ok
    end
  end

  defp reference_set("patron_system", reference),
    do: [external_reference: reference, updated_at: DateTime.utc_now()]

  defp reference_set("newsletter", reference),
    do: [newsletter_reference: reference, updated_at: DateTime.utc_now()]

  @doc """
  Marks application `id` stored by the library system `scope` as
  `screened_out`, the outcome of an application the screen turned away,
  and stamps `updated_at` with the moment it was screened out: the stamp
  the host's retention measures the screened-out age from.

  An application already marked screened out is left as it is, its stamp
  included, so a delivery that writes the mark again (a retried job's)
  does not move the age the host's retention measures.

  Answers `:ok`, or `{:error, :not_found}` when no application with that
  id is stored under that library system.
  """
  @spec record_screened_out(String.t(), integer()) :: :ok | {:error, :not_found}
  def record_screened_out(scope, id) when is_binary(scope) and is_integer(id) do
    query = from(a in CardApplication, where: a.scope == ^scope and a.id == ^id)
    unmarked = from(a in query, where: a.status != "screened_out")

    case Repo.update_all(unmarked, set: [status: "screened_out", updated_at: DateTime.utc_now()]) do
      {0, _} -> if Repo.exists?(query), do: :ok, else: {:error, :not_found}
      {_count, _} -> :ok
    end
  end

  @doc """
  Clears the personal fields of every application the library system
  `scope` stored whose `status` is `status` and whose `updated_at` is
  strictly before `cutoff`, and answers how many it cleared.

  The personal fields are the name, the email address, the phone number
  and the street address. The name, the email address and the street
  address are `NOT NULL` columns, so they are written as empty strings;
  the phone number is written as `nil`. Everything else stays: the id,
  the library system, the client's idempotency key, the two interests,
  the status, the two outside references and both stamps. A repeat post
  of the same key is still matched by the `(scope, idempotency_key)`
  unique index and answers the first application, and `updated_at` stays
  the stamp of the outcome the age was measured from.

  An application already cleared is not selected again, so a second call
  with the same cutoff answers `{:ok, 0}`.

  `status` is `"screened_out"` or `"sent"`, the two outcomes the host's
  retention keys on (`StatifierExamples.FormPost.PurgeJob`).
  """
  @spec purge_personal_fields(String.t(), String.t(), DateTime.t()) :: {:ok, non_neg_integer()}
  def purge_personal_fields(scope, status, %DateTime{} = cutoff)
      when is_binary(scope) and status in ["screened_out", "sent"] do
    query =
      from(a in CardApplication,
        where: a.scope == ^scope and a.status == ^status,
        where: a.updated_at < ^cutoff and a.email != ""
      )

    {count, _} =
      Repo.update_all(query, set: [name: "", email: "", phone: nil, street_address: ""])

    {:ok, count}
  end
end
