defmodule StatifierExamples.Persistence do
  @moduledoc """
  This app's durable storage: both the `StatifierPersistence.Ecto` host
  declaration and the `StatifierPersistence.Storage.Adapter` built on it.

  As a host declaration it is the compile-time configuration that
  generates the `statifier_charts`, `statifier_positions` and
  `statifier_executions` schemas over `StatifierExamples.Repo` - that package
  puts every knob on this `use`, never in application env. `:blob_type`
  is `:binary`, the default, stated rather than inherited because it is
  the option deciding whether the three payload columns round-trip
  byte-identically. On SQLite they are `BLOB` columns, and they do.

  As an adapter it delegates every callback to
  `StatifierPersistence.Storage.Adapter`'s Ecto implementation, with one
  deliberate omission.

  ## Why this module exists rather than using the Ecto adapter directly

  The Ecto adapter's optional `lock_execution/3` is Postgres-shaped: it takes
  `pg_advisory_xact_lock` and then a `SELECT ... FOR UPDATE` on the execution
  row. SQLite has neither. Its writer exclusion is the whole database
  rather than one row, so there is no advisory lock to take and no row to
  lock, and calling that callback here fails outright with `no such
  function: hashtextextended`.

  So this adapter does not export `lock_execution/3` at all. That is the
  storage contract's own way of saying an adapter does not offer per-execution
  locking - exporting the optional callback is what opts an adapter into
  it - and it is checked rather than asserted: the conformance suite
  generates the per-execution lock cases only for an adapter that exports the
  callback, and this one passes the suite it is given.

  The consequence belongs to whoever runs charts on top of this, and is
  not hidden: `StatifierPersistence.Executions` defaults its serialization to
  the adapter lock, and that default over an adapter with no `lock_execution/3`
  refuses with `{:error, {:serialization, :not_supported}}`. Durable executions
  through this adapter therefore have to pass an explicit serialization
  strategy - one chosen deliberately for a single-writer, file-backed
  database - rather than take the default. A host that wants the default
  back wants Postgres; that is a property of the database this app chose
  for the sake of a one-command setup, not of the package.

  ## The other Postgres-shaped surface, and why this one IS written here

  `list_executions_by_metadata/2` is the second callback the Ecto adapter writes
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
  clever way: read the `execution_id`/`metadata` pairs and apply the containment
  test in Elixir, then hand each match back through the Ecto adapter's own
  `fetch_execution/2` so the record shape stays the package's. The semantics are
  `jsonb @>`'s, and `StatifierPersistence.Storage.InMemory` implements the
  same test the same way for the same reason.

  What it costs is a table scan per call, and that cost is stated rather
  than hidden: the query is per *cascade* rather than per step (the driver
  reaches it on a `cancel_invoke` effect and on `start_child`'s guard),
  and this app's database holds the executions of a demo. A deployment with a
  real execution table wants Postgres and the delegated `jsonb` query, which is
  the same sentence `lock_execution/3` gets above - and it is why this remains
  a property of the database this app chose for a one-command setup rather
  than a limitation of the package.

  `list_executions_by_metadata/2` is still not what makes metadata *work* here:
  the `metadata` column round-trips through the schema in full either way,
  which is what the storage contract's metadata cases assert.

  From `statifier_persistence` 0.7.1 the capability DECLARATION goes with
  the callback, for the same reason. The Ecto adapter's
  `supports_metadata?/1` answers `false` off Postgres - its own metadata
  queries are `jsonb` containment SQL - and
  `StatifierPersistence.Storage.child_listing_supported?/1` reads that
  declaration as well as the export, so delegating it here would refuse
  every durable subchart at open with `:child_listing_unsupported`. This
  adapter answers `true` for itself instead: it issues none of that SQL,
  because the query above is the Elixir one.
  """

  @behaviour StatifierPersistence.Storage.Adapter

  # The per-execution input-log cap this app declares at `init/1`; see there.
  @input_log_cap 2_000

  import Ecto.Query, only: [from: 2]

  alias StatifierPersistence.Execution.Linkage
  alias StatifierPersistence.Storage.Adapter
  alias StatifierPersistence.Storage.Ecto, as: EctoAdapter

  use StatifierPersistence.Ecto,
    repo: StatifierExamples.Repo,
    blob_type: :binary

  @doc """
  Resolves the adapter handle, naming this module as the persistence host
  so a caller opening the store never has to repeat it, and declaring the
  per-execution input-log cap.

  The cap is a retention decision rather than a tuning knob: an entry
  holds the verbatim `%Statifier.Event{}` a step was driven with, so a log
  is document payload at rest - a signup's email address, a capture's card
  number - and `statifier_persistence`'s ADR-0010 decision 6 puts the
  bound on the host for that reason. `:infinity` is deliberately not what
  this app declares: an unbounded log on a demo database is a file that
  grows for as long as anyone leaves the app running. It is
  `Keyword.put_new/3`, so a caller opening the store for a one-off read
  can still say otherwise.

  What the cap buys is the editor page's Run pane, which replays a stored
  execution out of this log (`StatifierExamples.Charts.Replay`). An execution that
  outgrows it keeps stepping - the log closes itself with a marker and
  the execution is unaffected, which is the record's decision 6 - and the page
  refuses to draw a truncated log as a whole execution rather than showing a
  partial one as complete.
  """
  @impl StatifierPersistence.Storage.Adapter
  def init(opts) do
    opts
    |> Keyword.put(:persistence, __MODULE__)
    |> Keyword.put_new(:input_log_cap, @input_log_cap)
    |> EctoAdapter.init()
  end

  @impl StatifierPersistence.Storage.Adapter
  defdelegate save_chart(opts, chart_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_chart(opts, content_hash), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate save_position(opts, position_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_position(opts, session_id), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate insert_execution(opts, execution_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate fetch_execution(opts, execution_id), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate update_execution(opts, execution_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate isolate(opts), to: EctoAdapter

  @doc """
  Declares the per-execution input log (the optional
  `c:StatifierPersistence.Storage.Adapter.supports_input_log?/1`), and the
  two callbacks behind it.

  All three are delegated rather than written here, which is the opposite
  of what `supports_metadata?/1` and the two callbacks below it had to do.
  The reason is the whole of ADR-0010 decision 9: the input log's table is
  four ordinary columns and one unique index, its append is an insert
  taking `seq` from the execution's current maximum under the exclusion the
  caller already holds, and its read is an ordered select. There is no
  `jsonb` predicate in it, no advisory lock, and no index type beyond a
  unique one - so the shipped Ecto adapter's implementation is correct on
  SQLite unchanged, and V05 in `priv/repo/migrations` creates the same
  table on either backend.

  Exporting `supports_input_log?/1` is what opts this app in. An adapter
  that does not export it stores no inputs and sees no behaviour change -
  no execution-lifecycle call refuses on the log, deliberately (decision 1) - so
  this is the one capability in this module whose absence would cost a
  feature rather than break an execution. What it costs to have is one insert per
  step, and what it buys is the only reading of a durable execution this app has
  ever been able to show whole: see `StatifierExamples.Charts.Replay`.

  Turning it on is a data-retention decision and not a debugging switch;
  `init/1` above declares the cap and says why.
  """
  @impl StatifierPersistence.Storage.Adapter
  defdelegate supports_input_log?(opts), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate append_input(opts, execution_id, input_record), to: EctoAdapter

  @impl StatifierPersistence.Storage.Adapter
  defdelegate list_inputs(opts, execution_id), to: EctoAdapter

  @doc """
  Declares metadata support (the optional
  `c:StatifierPersistence.Storage.Adapter.supports_metadata?/1`), which
  this adapter answers for itself rather than delegating.

  The Ecto adapter's own answer is `false` off Postgres, and that is
  right for it: what ADR-0006 decision 3's capability covers is the
  `metadata` column *and* the match query over it, and the Ecto adapter's
  query is `jsonb` containment SQL a SQLite backend does not parse
  (sp-11w). Delegating here would inherit that `false` and, through
  `StatifierPersistence.Storage.child_listing_supported?/1`, refuse every
  durable subchart this app starts - which is the refusal-at-open arm
  working exactly as designed, on an adapter that does not have the
  problem.

  This adapter does not have it because it does not issue that SQL: it
  reads the `execution_id`/`metadata` pairs and applies the containment test in
  Elixir, which is the whole of `list_executions_by_metadata/2` below and the
  reason that callback is written here rather than delegated. The column
  itself round-trips on SQLite as JSON text. So both halves of the
  capability hold, and this answers `true` on the same grounds the
  callback below exists on.

  The other two 0.7.0 capabilities are the same question one layer up, and
  as of se-j87 they are claimed here too: `supports_execution_outcome?/1` and
  `list_execution_states_by_metadata/2` are what a Tier A fan-out needs at open,
  and `StatifierPersistence.Driver.start_child_at/6` refuses a fan-out
  outright without both rather than half-starting one. They are answered
  below on exactly these grounds - the outcome payload is a blob column
  this schema already carries from V03, and the status projection is the
  same Elixir containment walk, selecting three values instead of
  materialising a record per child.
  """
  @impl StatifierPersistence.Storage.Adapter
  @spec supports_metadata?(Adapter.opts()) :: boolean()
  def supports_metadata?(_opts), do: true

  @doc """
  Every stored execution whose `metadata` contains `match` (the optional
  `c:StatifierPersistence.Storage.Adapter.list_executions_by_metadata/2`,
  ADR-0008 decision 5).

  Exporting this is what opts this adapter into durable subcharts; the
  moduledoc says why it is written here rather than delegated, and what
  the table scan costs.

  `match` is a containment map, and the semantics are `jsonb @>`'s: every
  pair in `match` is present in the stored map, and a map value contains
  rather than equals. `StatifierPersistence.Execution.Linkage.parent_match/1`
  and `invocation_match/2` are the two the driver builds, both a single
  nested map under the package's reserved key.

  An empty map, or one with a non-string key, is an `ArgumentError` and
  not an answer: it would otherwise match every execution in the table, and
  cascade-cancelling every execution in the table is the one mistake this
  callback is able to make. That is the refusal both package adapters
  make, spelled the same way.
  """
  @impl StatifierPersistence.Storage.Adapter
  @spec list_executions_by_metadata(Adapter.opts(), Adapter.metadata()) ::
          {:ok, [Adapter.execution_record()]} | {:error, Adapter.error()}
  def list_executions_by_metadata(opts, match) do
    validate_match!(match)

    StatifierExamples.Repo.all(
      from(r in __MODULE__.Execution, select: {r.execution_id, r.metadata})
    )
    |> Enum.filter(fn {_execution_id, metadata} -> contains?(metadata || %{}, match) end)
    |> Enum.reduce_while({:ok, []}, fn {execution_id, _metadata}, {:ok, acc} ->
      case fetch_execution(opts, execution_id) do
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

  @doc """
  Whether this adapter can store a child's terminal outcome (the optional
  `c:StatifierPersistence.Storage.Adapter.supports_execution_outcome?/1`).

  `true`, and the declaration costs nothing new: `outcome_blob` is an
  ordinary column on the executions schema from V03, written through the same
  delegated `update_execution/2` every other execution field goes through, and read
  back by the package. The shipped Ecto adapter answers `false` off
  Postgres for the reason `supports_metadata?/1` above answers `false`
  there - the queries beside it are `jsonb` SQL - and this adapter
  answers for itself for the reason it answers that one: it issues none
  of that SQL.

  Without it `StatifierPersistence.Driver.start_child_at/6` refuses every
  fan-out at open with `:execution_outcome_unsupported`, which is the refusal
  working: a child whose answer could never be stored is a child whose
  invocation could never be settled.
  """
  @impl StatifierPersistence.Storage.Adapter
  @spec supports_execution_outcome?(Adapter.opts()) :: boolean()
  def supports_execution_outcome?(_opts), do: true

  @doc """
  The indexed status projection of every stored execution whose `metadata`
  contains `match` (the optional
  `c:StatifierPersistence.Storage.Adapter.list_execution_states_by_metadata/2`).

  This is `list_executions_by_metadata/2`'s question asked cheaply. A fan-out's
  settlement runs on every child's completion and asks only "have all N
  settled, and at which indices" - so the package gives it a callback that
  answers `execution_id`, `status` and `child_index` rather than N identity and
  position blobs. On Postgres that is three columns under an indexed
  `jsonb` containment predicate; here it is the same Elixir containment
  walk `list_executions_by_metadata/2` does, selecting the three values instead
  of handing each match back through `fetch_execution/2`.

  The scan cost is the same table scan that callback's moduledoc states,
  and the saving is real anyway: the whole point of the projection is that
  it does not move a blob per child, and this app's answer does not
  either.

  `child_index` is `nil` for a matched execution carrying no linkage, which is
  what the callback's type says and what a match written wide enough to
  catch a parent would produce. `status` is the stored string read back as
  the atom the projection's type names, one clause per status the storage
  contract defines and no fall-through: a status this app does not know is
  a storage contract that grew, and it should fail here rather than be
  reported as something else.

  The refusal is `list_executions_by_metadata/2`'s, for its reason: an empty
  match, or one with a non-string key, would select every execution in the
  table, and a settlement that read every execution in the table as its own
  children is the one mistake this callback can make.
  """
  @impl StatifierPersistence.Storage.Adapter
  @spec list_execution_states_by_metadata(Adapter.opts(), Adapter.metadata()) ::
          {:ok, [Adapter.execution_state()]} | {:error, Adapter.error()}
  def list_execution_states_by_metadata(_opts, match) do
    validate_match!(match)

    states =
      StatifierExamples.Repo.all(
        from(r in __MODULE__.Execution, select: {r.execution_id, r.status, r.metadata})
      )
      |> Enum.filter(fn {_execution_id, _status, metadata} ->
        contains?(metadata || %{}, match)
      end)
      |> Enum.map(fn {execution_id, status, metadata} ->
        %{execution_id: execution_id, status: status(status), child_index: child_index(metadata)}
      end)

    {:ok, states}
  end

  # The five statuses `StatifierPersistence.Storage.Adapter` defines, read
  # off the string column the schema stores them in. No fall-through: see
  # the callback's doc. `needs_migration` is the fifth, from
  # `statifier_persistence` 0.14.0: a parked execution this app never
  # writes, since it calls no `migrate/4`, but one the storage contract
  # can hand back, so it is read like the other four (se-1tro).
  @spec status(String.t()) :: Adapter.execution_status()
  defp status("active"), do: :active
  defp status("completed"), do: :completed
  defp status("failed"), do: :failed
  defp status("cancelled"), do: :cancelled
  defp status("needs_migration"), do: :needs_migration

  # The child's own index, out of the linkage the package writes under its
  # reserved metadata key. `nil` for an execution carrying no linkage at all -
  # a root execution, or a parent caught by a match written wide enough to
  # include it - which is the case the callback's type names.
  @spec child_index(map() | nil) :: non_neg_integer() | nil
  defp child_index(metadata) when is_map(metadata) do
    metadata
    |> Map.get(Linkage.reserved_key(), %{})
    |> Map.get("child_index")
  end

  defp child_index(_absent), do: nil

  @spec validate_match!(term()) :: :ok
  defp validate_match!(match) when is_map(match) and map_size(match) > 0 do
    if Enum.all?(Map.keys(match), &is_binary/1) do
      :ok
    else
      raise ArgumentError,
            "list_executions_by_metadata/2 takes a map with string keys, got keys: " <>
              inspect(Map.keys(match))
    end
  end

  defp validate_match!(other) do
    raise ArgumentError,
          "list_executions_by_metadata/2 takes a non-empty map with string keys, " <>
            "got: #{inspect(other)}"
  end

  # No lock_execution/3. See the moduledoc: not exporting it is how an adapter
  # declines the optional per-execution lock, and SQLite cannot honour it.
end
