defmodule UpgradeHost.Repo.Migrations.AddPatrons do
  use Ecto.Migration

  # The host's own patron table: where a registration form's personal
  # fields are kept. Nothing of the family's reads it; the router and the
  # execution are handed the patron's id and nothing else.
  def change do
    create table(:patrons, primary_key: false) do
      add :id, :text, primary_key: true
      add :branch_id, :text, null: false
      add :name, :text, null: false
      add :email, :text, null: false
      add :registration_execution_id, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:patrons, [:branch_id, :email])
  end
end
