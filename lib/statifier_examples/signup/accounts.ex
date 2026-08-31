defmodule StatifierExamples.Signup.Accounts do
  @moduledoc """
  The one write the signup wizard makes: the account row `myapp:provision`
  exists to create.

  ## Why the run id is the address

  The chart carries no datamodel and no personal data, so nothing in the
  wizard names the person signing up - and nothing should. What the host
  has instead is the run: one run of the signup chart is one signup, and
  the run id is stable across a restart because it is stored beside the
  position. So the account this example provisions is addressed
  `signup-<run id>@example.com`, which is fiction the way every value in
  this repo is fiction, and which is a *deterministic function of the run*
  rather than a value invented at the moment of writing.

  That determinism is what makes the next paragraph possible.

  ## Idempotency, honestly

  `StatifierPersistence.Executor`'s contract is at-least-once: a host that
  crashed between executing an effect and persisting the step re-drives
  the same event and gets the same `<invoke>` back with the same
  deterministic key, and the stepper never dedupes - "idempotency by that
  key is the implementer's". This is that implementation, and it does not
  keep a table of keys to do it.

  The address is the key. It is derived from the run id, the `users` table
  carries a unique index on `email`, and `provision/1` inserts with
  `on_conflict: :nothing` against that index. A replayed provision
  therefore finds the row already there and returns `{:existing, user}`
  rather than a second account or a raised constraint error, and the
  caller can say which happened - which is what the run feed prints, so
  the property is visible rather than asserted.

  What this does not claim: it is not idempotent across *different* runs
  that mean the same person, because nothing here knows they do. A host
  with a real signup keys on the address the person typed, and then this
  same upsert is the whole of the mechanism.
  """

  import Ecto.Query, only: [from: 2]

  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.User

  @typedoc """
  What provisioning did: created the account, or found the one a previous
  delivery of the same call already created.
  """
  @type outcome :: {:created, User.t()} | {:existing, User.t()}

  @doc """
  Provisions the account for `run_id`, or returns the one already
  provisioned for it.
  """
  @spec provision(String.t()) :: outcome()
  def provision(run_id) when is_binary(run_id) do
    email = email_for(run_id)
    now = DateTime.utc_now()

    {written, _returning} =
      Repo.insert_all(
        User,
        [%{email: email, inserted_at: now, updated_at: now}],
        on_conflict: :nothing,
        conflict_target: :email
      )

    {tag(written), Repo.one!(from(u in User, where: u.email == ^email))}
  end

  @doc """
  The fictional address `run_id`'s account is provisioned under.

  Public because it is the key: a test asserting that two deliveries wrote
  one row needs the same derivation the writer used, not a copy of it.
  """
  @spec email_for(String.t()) :: String.t()
  def email_for(run_id) when is_binary(run_id), do: "signup-#{run_id}@example.com"

  # `insert_all/3` under `on_conflict: :nothing` answers with the number of
  # rows it actually wrote, and that count is the only place the difference
  # between a first delivery and a replay is observable. Reading it here is
  # what lets the caller print which one happened; a second query could not
  # tell them apart.
  @spec tag(non_neg_integer()) :: :created | :existing
  defp tag(1), do: :created
  defp tag(0), do: :existing
end
