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

  ## The other Postgres-shaped surface, and why this one IS written here

  `list_runs_by_metadata/2` is the second callback the Ecto adapter writes
  Postgres-shaped: it issues a `jsonb @>` containment query, and SQLite
  stores the `metadata` column as JSON *text*, which has no such operator.

  Exporting that callback is how an adapter opts into the child listing a
  durable subchart needs (ADR-0008 decision 5): `StatifierPersistence.Driver`
  refuses to start a child at open with `:child_listing_unsupported` when
  the store cannot enumerate one, because a child that could never be
  found is a child that could never be cancelled. So the callback this
  app declined for its whole life until se-6ag is exactly the one a
  durable subchart cannot do without, and it is implemented below rather
  than delegated.

  It is implemented the honest way for a file-backed database and not a
  clever way: read the `run_id`/`metadata` pairs and apply the containment
  test in Elixir, then hand each match back through the Ecto adapter's own
  `fetch_run/2` so the record shape stays the package's. The semantics are
  `jsonb @>`'s, and `StatifierPersistence.Storage.InMemory` implements the
  same test the same way for the same reason.

  What it costs is a table scan per call, and that cost is stated rather
  than hidden: the query is per *cascade* rather than per step (the driver
  reaches it on a `cancel_invoke` effect and on `start_child`'s guard),
  and this app's database holds the runs of a demo. A deployment with a
  real run table wants Postgres and the delegated `jsonb` query, which is
  the same sentence `lock_run/3` gets above - and it is why this remains
  a property of the database this app chose for a one-command setup rather
  than a limitation of the package.

  `list_runs_by_metadata/2` is still not what makes metadata *work* here:
  the `metadata` column round-trips through the schema in full either way,
  which is what the storage contract's metadata cases assert.
  """

  @behaviour StatifierPersistence.Storage.Adapter

  import Ecto.Query, only: [from: 2]

  alias StatifierPersistence.Storage.Adapter
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

  @doc """
  Every stored run whose `metadata` contains `match` (the optional
  `c:StatifierPersistence.Storage.Adapter.list_runs_by_metadata/2`,
  ADR-0008 decision 5).

  Exporting this is what opts this adapter into durable subcharts; the
  moduledoc says why it is written here rather than delegated, and what
  the table scan costs.

  `match` is a containment map, and the semantics are `jsonb @>`'s: every
  pair in `match` is present in the stored map, and a map value contains
  rather than equals. `StatifierPersistence.Run.Linkage.parent_match/1`
  and `invocation_match/2` are the two the driver builds, both a single
  nested map under the package's reserved key.

  An empty map, or one with a non-string key, is an `ArgumentError` and
  not an answer: it would otherwise match every run in the table, and
  cascade-cancelling every run in the table is the one mistake this
  callback is able to make. That is the refusal both package adapters
  make, spelled the same way.
  """
  @impl StatifierPersistence.Storage.Adapter
  @spec list_runs_by_metadata(Adapter.opts(), Adapter.metadata()) ::
          {:ok, [Adapter.run_record()]} | {:error, Adapter.error()}
  def list_runs_by_metadata(opts, match) do
    validate_match!(match)

    StatifierExamples.Repo.all(from(r in __MODULE__.Run, select: {r.run_id, r.metadata}))
    |> Enum.filter(fn {_run_id, metadata} -> contains?(metadata || %{}, match) end)
    |> Enum.reduce_while({:ok, []}, fn {run_id, _metadata}, {:ok, acc} ->
      case fetch_run(opts, run_id) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      {:error, _reason} = error -> error
    end
  end

  # Recursive containment, the same test `StatifierPersistence.Storage.Ecto`
  # delegates to `jsonb @>` and `StatifierPersistence.Storage.InMemory`
  # writes out: every pair in `match` is present in `stored`, and a map
  # value contains rather than equals.
  @spec contains?(map(), map()) :: boolean()
  defp contains?(stored, match) when is_map(stored) and is_map(match) do
    Enum.all?(match, fn {key, value} ->
      case Map.fetch(stored, key) do
        {:ok, stored_value} when is_map(value) and is_map(stored_value) ->
          contains?(stored_value, value)

        {:ok, stored_value} ->
          stored_value == value

        :error ->
          false
      end
    end)
  end

  @spec validate_match!(term()) :: :ok
  defp validate_match!(match) when is_map(match) and map_size(match) > 0 do
    if Enum.all?(Map.keys(match), &is_binary/1) do
      :ok
    else
      raise ArgumentError,
            "list_runs_by_metadata/2 takes a map with string keys, got keys: " <>
              inspect(Map.keys(match))
    end
  end

  defp validate_match!(other) do
    raise ArgumentError,
          "list_runs_by_metadata/2 takes a non-empty map with string keys, " <>
            "got: #{inspect(other)}"
  end

  # No lock_run/3. See the moduledoc: not exporting it is how an adapter
  # declines the optional per-run lock, and SQLite cannot honour it.
end
