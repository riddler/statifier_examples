# `mix test` has already created and migrated the database (the alias in
# mix.exs). Each test checks out its own sandboxed connection.
Ecto.Adapters.SQL.Sandbox.mode(UpgradeHost.Repo, :manual)

ExUnit.start()
