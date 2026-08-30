defmodule StatifierExamples.Repo do
  @moduledoc """
  This app's one repo, on SQLite.

  SQLite is a deliberate choice for an example host rather than a
  convenience: the database is a file under `priv/`, so `mix setup` on a
  fresh clone starts no service, needs no container, and needs no
  credentials. An example a reader cannot run in one command is not much
  of an example.

  What it costs is spelled out in `StatifierExamples.Persistence`, which
  is where the cost actually lands.
  """

  use Ecto.Repo,
    otp_app: :statifier_examples,
    adapter: Ecto.Adapters.SQLite3
end
