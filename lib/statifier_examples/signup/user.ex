defmodule StatifierExamples.Signup.User do
  @moduledoc """
  The account a finished signup produced: the `users` table's schema.

  As minimal as the migration that made it, and for the same reason - the
  chart owns the wizard, this row owns only the account. The address is
  the natural key, so the table carries a unique index on it and this
  module carries the constraint that names it; that index is what makes
  provisioning idempotent rather than a second row.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "users" do
    field(:email, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  The changeset for a provisioned account.

  `unique_constraint/3` is here even though
  `StatifierExamples.Signup.Accounts` provisions with an upsert that never
  reaches it: the constraint belongs to the schema that has the index, and
  a second writer added later should get a changeset error rather than a
  raised `Exqlite.Error`.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end
end
