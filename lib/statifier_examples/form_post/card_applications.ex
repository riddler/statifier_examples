defmodule StatifierExamples.FormPost.CardApplications do
  @moduledoc """
  The host's write for the card application form: store the post, once per
  client key, and enqueue the job that hands it on.

  `receive_application/2` inserts the application and its
  `StatifierExamples.FormPost.IntakeJob` in one transaction, so the job
  commits with the row it names and a row that did not commit leaves no
  job behind. The job's arguments carry the row's id and nothing else:
  whatever works the application later reads the values back from the
  host's table by that id.

  A repeat of a client key within a library system answers the first
  application and inserts nothing, row or job. The repeat is found by the
  `(scope, idempotency_key)` unique index, not by a read before the write,
  so two posts of the same form racing each other still store one row.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias StatifierExamples.FormPost.{CardApplication, IntakeJob}
  alias StatifierExamples.Repo

  @doc """
  Stores one posted application for the library system `scope`.

  Answers `{:ok, application, :created}` for a new application,
  `{:ok, first, :repeat}` when the client key was already stored in that
  library system, and `{:error, changeset}` for a form that cannot be
  stored.
  """
  @spec receive_application(String.t(), map()) ::
          {:ok, CardApplication.t(), :created | :repeat} | {:error, Ecto.Changeset.t()}
  def receive_application(scope, form) when is_binary(scope) and is_map(form) do
    changeset = CardApplication.changeset(%CardApplication{scope: scope}, form)

    Multi.new()
    |> Multi.insert(:application, changeset,
      on_conflict: :nothing,
      conflict_target: [:scope, :idempotency_key]
    )
    |> Multi.run(:outcome, fn repo, %{application: application} -> enqueue(repo, application) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{outcome: outcome}} -> outcome
      {:error, :application, changeset, _changes} -> {:error, changeset}
    end
  end

  # An insert the unique index turned away comes back with no id: the
  # application is the first row stored under that key, and nothing is
  # enqueued for it again.
  @spec enqueue(Ecto.Repo.t(), CardApplication.t()) ::
          {:ok, {:ok, CardApplication.t(), :created | :repeat}}
  defp enqueue(repo, %CardApplication{id: nil, scope: scope, idempotency_key: key}) do
    first =
      repo.one!(
        from(a in CardApplication, where: a.scope == ^scope and a.idempotency_key == ^key)
      )

    {:ok, {:ok, first, :repeat}}
  end

  # A job that cannot be inserted raises, and the transaction takes the
  # application with it: a stored application always has its intake job.
  defp enqueue(_repo, %CardApplication{id: id} = application) do
    Oban.insert!(IntakeJob.new(%{"application_id" => id}))

    {:ok, {:ok, application, :created}}
  end
end
