defmodule StatifierExamples.Repo.Migrations.CreateCardApplications do
  @moduledoc """
  The host's own table for the Riverbend Public Library's card application
  form: one row per application a visitor posted.

  The posted values live here and nowhere else. The state chart that works
  an application is handed this row's id, and a step that needs a value
  reads it back from this table by that id, so the engine's own rows never
  hold a name, an address or a phone number.

  `scope` is the library system the form belongs to. `idempotency_key` is
  the client's own key for one submission, unique within a library system,
  so a form posted twice is one application rather than two. `status`
  starts at `received`; `external_reference` is the outside system's
  reference for the application, empty until a step hands it there.
  """

  use Ecto.Migration

  def change do
    create table(:card_applications) do
      add(:scope, :string, null: false)
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:phone, :string)
      add(:street_address, :string, null: false)
      add(:wants_card, :boolean, null: false, default: false)
      add(:wants_newsletter, :boolean, null: false, default: false)
      add(:idempotency_key, :string, null: false)
      add(:status, :string, null: false)
      add(:external_reference, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:card_applications, [:scope, :idempotency_key]))
  end
end
