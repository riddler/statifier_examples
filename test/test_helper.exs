# The repo is started by the application; the suite only puts its sandbox
# into :manual mode, so every test checks out (and rolls back) its own
# connection. The `test` alias in mix.exs creates and migrates the database
# file first, which is why nothing here touches DDL.
Ecto.Adapters.SQL.Sandbox.mode(StatifierExamples.Repo, :manual)

ExUnit.start()
