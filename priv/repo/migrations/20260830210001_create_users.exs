defmodule StatifierExamples.Repo.Migrations.CreateUsers do
  @moduledoc """
  The signup example's accounts table: what a completed signup chart has
  to have produced for the run to have meant anything.

  Minimal on purpose. The chart owns the wizard's state; this table owns
  only the account the wizard exists to create, so it carries an address
  and the moment the row appeared and nothing else until a bead needs
  more.
  """

  use Ecto.Migration

  def change do
    create table(:users) do
      add(:email, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:users, [:email]))
  end
end
