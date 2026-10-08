defmodule UpgradeHost.Repo.Migrations.AddStatifierPersistence do
  use Ecto.Migration

  # Capped at the version this host runs, with the rollback capped to
  # match, so a later package version's V09 arrives as a migration of its
  # own (`from: 9`) rather than through this one.
  def up, do: StatifierPersistence.Ecto.Migrations.up(for: UpgradeHost.Persistence, version: 8)
  def down, do: StatifierPersistence.Ecto.Migrations.down(for: UpgradeHost.Persistence, from: 8)
end
