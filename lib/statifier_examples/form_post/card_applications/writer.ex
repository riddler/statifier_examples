defmodule StatifierExamples.FormPost.CardApplications.Writer do
  @moduledoc """
  The one module that updates a stored card application after the post is
  stored: it writes the outside system's reference back to the row.

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
end
