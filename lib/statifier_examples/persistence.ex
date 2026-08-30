defmodule StatifierExamples.Persistence do
  @moduledoc """
  This app's durable storage: both the `StatifierPersistence.Ecto` host
  declaration and the `StatifierPersistence.Storage.Adapter` built on it.

  As a host declaration it is the compile-time configuration that
  generates the `statifier_charts`, `statifier_positions` and
  `statifier_runs` schemas over `StatifierExamples.Repo` - that package
  puts every knob on this `use`, never in application env. `:blob_type`
  is `:binary`, the default, stated rather than inherited because it is
  the option deciding whether the three payload columns round-trip
  byte-identically. On SQLite they are `BLOB` columns, and they do.

  As an adapter it delegates every callback to
  `StatifierPersistence.Storage.Adapter`'s Ecto implementation, with one
  deliberate omission.

  ## Why this module exists rather than using the Ecto adapter directly

  The Ecto adapter's optional `lock_run/3` is Postgres-shaped: it takes
  `pg_advisory_xact_lock` and then a `SELECT ... FOR UPDATE` on the run
  row. SQLite has neither. Its writer exclusion is the whole database
  rather than one row, so there is no advisory lock to take and no row to
  lock, and calling that callback here fails outright with `no such
  function: hashtextextended`.

  So this adapter does not export `lock_run/3` at all. That is the
  storage contract's own way of saying an adapter does not offer per-run
  locking - exporting the optional callback is what opts an adapter into
  it - and it is checked rather than asserted: the conformance suite
  generates the per-run lock cases only for an adapter that exports the
  callback, and this one passes the suite it is given.

  The consequence belongs to whoever runs charts on top of this, and is
  not hidden: `StatifierPersistence.Runs` defaults its serialization to
  the adapter lock, and that default over an adapter with no `lock_run/3`
  refuses with `{:error, {:serialization, :not_supported}}`. Durable runs
  through this adapter therefore have to pass an explicit serialization
  strategy - one chosen deliberately for a single-writer, file-backed
  database - rather than take the default. A host that wants the default
  back wants Postgres; that is a property of the database this app chose
  for the sake of a one-command setup, not of the package.

  One other Postgres-shaped surface goes with it, and needs no code here
  because nothing in this app calls it: `list_runs_by_metadata/2` issues
  a `jsonb` containment query. SQLite stores the `metadata` column as
  JSON text, so metadata round-trips through the schema in full - the
  storage contract's metadata cases pass here - but that one query does
  not run.
  """

  @behaviour StatifierPersistence.Storage.Adapter

  alias StatifierPersistence.Storage.Ecto, as: EctoAdapter

  use StatifierPersistence.Ecto,
    repo: StatifierExamples.Repo,
    blob_type: :binary

  @doc """
  Resolves the adapter handle, naming this module as the persistence host
  so a caller opening the store never has to repeat it.
  """
  @impl StatifierPersistence.Storage.Adapter
  def init(opts), do: EctoAdapter.init(Keyword.put(opts, :persistence, __MODULE__))

  @impl StatifierPersistence.Storage.Adapter
  defdelegate save_chart(opts, chart_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_chart(opts, content_hash), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate save_position(opts, position_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_position(opts, session_id), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate insert_run(opts, run_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_run(opts, run_id), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate update_run(opts, run_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate isolate(opts), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate supports_metadata?(opts), to: EctoAdapter

  # No lock_run/3. See the moduledoc: not exporting it is how an adapter
  # declines the optional per-run lock, and SQLite cannot honour it.
end
