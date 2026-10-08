defmodule StatifierExamples.FormPost.CardApplicationSend do
  @moduledoc """
  One row of the card application form's outbox: the `card_application_sends`
  table's schema.

  A row says that an application was handed to a route (`patron_system` or
  `newsletter`), what the outside system answered, and the router's key for
  the send as one string. It holds ids and the outside system's reference,
  never a value the visitor typed. The table is unique on `(route,
  idempotency_key)`, so a redriven delivery writes no second row.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          application_id: integer() | nil,
          route: String.t() | nil,
          outside_reference: String.t() | nil,
          idempotency_key: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "card_application_sends" do
    field(:application_id, :integer)
    field(:route, :string)
    field(:outside_reference, :string)
    field(:idempotency_key, :string)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
