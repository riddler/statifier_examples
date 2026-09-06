defmodule StatifierExamples.Signup.InviteOutcome do
  @moduledoc """
  One invitee a bulk chunk handler processed: the `invite_outcomes`
  table's schema.

  As minimal as `StatifierExamples.Signup.User`, and for the same reason.
  The chart owns the batch; this row owns one invitee's outcome, the run
  that wrote it, and - for the one row in a fan-out that needed chart
  semantics - the run that was started for it.

  `{chunk_id, email}` is the natural key, so the table carries a unique
  index on the pair and this module carries the constraint that names it.
  That index is what makes a redelivered chunk one row set rather than
  two.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          chunk_id: String.t() | nil,
          email: String.t() | nil,
          status: String.t() | nil,
          run_id: String.t() | nil,
          promoted_run_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "invite_outcomes" do
    field(:chunk_id, :string)
    field(:email, :string)
    field(:status, :string)
    field(:run_id, :string)
    field(:promoted_run_id, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The changeset for one processed invitee.

  `unique_constraint/3` is here even though
  `StatifierExamples.Signup.Invites` writes with an upsert that never
  reaches it: the constraint belongs to the schema that has the index,
  and a second writer added later should get a changeset error rather
  than a raised `Exqlite.Error`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(outcome, attrs) do
    outcome
    |> cast(attrs, [:chunk_id, :email, :status, :run_id, :promoted_run_id])
    |> validate_required([:chunk_id, :email, :status, :run_id])
    |> unique_constraint([:chunk_id, :email])
  end
end
