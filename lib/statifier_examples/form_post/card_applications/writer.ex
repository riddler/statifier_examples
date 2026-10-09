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
  `scope`, and marks the application `sent`.

  `route` is `"patron_system"`, whose reference goes in
  `external_reference`, or `"newsletter"`, whose reference goes in
  `newsletter_reference`. Answers `:ok`, or `{:error, :not_found}` when no
  application with that id is stored under that library system.
  """
  @spec record_reference(String.t(), integer(), String.t(), String.t()) ::
          :ok | {:error, :not_found}
  def record_reference(scope, id, route, reference)
      when is_binary(scope) and is_integer(id) and route in ["patron_system", "newsletter"] and
             is_binary(reference) do
    now = DateTime.utc_now()
    query = from(a in CardApplication, where: a.scope == ^scope and a.id == ^id)

    set =
      case route do
        "patron_system" -> [external_reference: reference, status: "sent", updated_at: now]
        "newsletter" -> [newsletter_reference: reference, status: "sent", updated_at: now]
      end

    case Repo.update_all(query, set: set) do
      {0, _} -> {:error, :not_found}
      {_count, _} -> :ok
    end
  end

  @doc """
  Marks application `id` stored by the library system `scope` as
  `screened_out`, the outcome of an application the screen turned away,
  and stamps `updated_at` with the moment it was screened out: the stamp
  the host's retention measures the screened-out age from.

  Answers `:ok`, or `{:error, :not_found}` when no application with that
  id is stored under that library system.
  """
  @spec record_screened_out(String.t(), integer()) :: :ok | {:error, :not_found}
  def record_screened_out(scope, id) when is_binary(scope) and is_integer(id) do
    query = from(a in CardApplication, where: a.scope == ^scope and a.id == ^id)

    case Repo.update_all(query, set: [status: "screened_out", updated_at: DateTime.utc_now()]) do
      {0, _} -> {:error, :not_found}
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
