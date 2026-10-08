defmodule UpgradeHost.Registrations.Patron do
  @moduledoc """
  A patron, as the host keeps one: its own id, the branch it registered
  at, and the personal fields the registration form posted. The id is
  the only one of these that leaves the host's table.

  `registration_execution_id` is the execution the patron's latest
  registration runs as, the id the router answered when it created it.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          branch_id: String.t() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          registration_execution_id: String.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "patrons" do
    field :branch_id, :string
    field :name, :string
    field :email, :string
    field :registration_execution_id, :string
    timestamps(type: :utc_datetime_usec)
  end
end
