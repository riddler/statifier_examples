defmodule StatifierExamples.FormPost.CardApplications.Reader do
  @moduledoc """
  The one module that reads a stored card application's personal fields:
  the name, the email address, the phone number and the street address.

  Everything else in the recipe works with the application's id. The
  intake job's arguments, the chart's datamodel and every step's answer
  carry the id or a word, so a step that needs what the visitor typed
  comes here with the id and the library system and reads the row back
  from the host's own table. Keeping the read in one place is what makes
  "ids only" checkable: a reviewer reads this module's callers, not every
  query in the app.

  The read is always under a library system. An id stored by one library
  system answers not found to another, so a step working for the wrong
  library system cannot read a neighbour's applications by guessing ids.
  """

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.FormPost.CardApplication
  alias StatifierExamples.Repo

  @doc """
  Reads application `id` as stored by the library system `scope`.

  Answers `{:error, :not_found}` for an id that names no application, and
  for one stored by another library system.
  """
  @spec fetch(String.t(), integer()) :: {:ok, CardApplication.t()} | {:error, :not_found}
  def fetch(scope, id) when is_binary(scope) and is_integer(id) do
    case Repo.one(from(a in CardApplication, where: a.scope == ^scope and a.id == ^id)) do
      %CardApplication{} = application -> {:ok, application}
      nil -> {:error, :not_found}
    end
  end
end
