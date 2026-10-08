defmodule UpgradeHost.KeyGenerator do
  @moduledoc """
  The host's own surrogate-key scheme for the persistence tables:
  k-sortable UXID strings, each prefixed with the table it keys, the way a
  host that already keys its own tables by UXID keeps one shape across the
  database.
  """

  @behaviour StatifierPersistence.Ecto.KeyGenerator

  @prefixes %{charts: "chart", positions: "position", executions: "execution", inputs: "input"}

  @impl StatifierPersistence.Ecto.KeyGenerator
  def ecto_type(_opts), do: :string

  @impl StatifierPersistence.Ecto.KeyGenerator
  def migration_type(_opts), do: :text

  @impl StatifierPersistence.Ecto.KeyGenerator
  def autogenerate(table, _opts),
    do: {UXID, :generate!, [[prefix: Map.fetch!(@prefixes, table)]]}
end
