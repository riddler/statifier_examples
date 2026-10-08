defmodule StatifierExamples.Repo.Migrations.CreateCardApplicationSends do
  @moduledoc """
  The outbox for the card application form's two outside systems, the
  library's patron system and the events newsletter list, and the column
  that holds the newsletter list's reference.

  One row says that application `application_id` was handed to `route` and
  that the outside system answered `outside_reference`. `idempotency_key`
  is the key the router composed for the send, as one string, and the
  index on `(route, idempotency_key)` is what lets a redriven delivery
  write nothing new.

  The outbox holds ids, the route name, the outside system's reference and
  the router's key; never a value the visitor typed. The posted values stay
  in `card_applications`.

  `newsletter_reference` sits beside `external_reference`, which stays the
  patron system's reference: an application that asked for a card and the
  newsletter keeps both.
  """

  use Ecto.Migration

  def change do
    create table(:card_application_sends) do
      add(:application_id, references(:card_applications), null: false)
      add(:route, :string, null: false)
      add(:outside_reference, :string, null: false)
      add(:idempotency_key, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:card_application_sends, [:route, :idempotency_key]))

    alter table(:card_applications) do
      add(:newsletter_reference, :string)
    end
  end
end
