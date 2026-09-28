defmodule Mix.Tasks.StatifierExamples.MigrateWaiting do
  @shortdoc "Moves waiting library loans onto a new revision of their document, and back"

  @moduledoc """
  Runs the path `docs/guides/migrating-waiting-executions.md` walks, against
  this app's own database, and prints what each step answered.

      mix statifier_examples.migrate_waiting

  Two library loans wait in `awaiting_return` on revision 1 of a loan
  document, each with its 21-day due-date timer stored as an Oban job.
  Revision 2 renames that step to `on_loan` - a new block id - and gives the
  check-in step after it a `damaged` arm. The task publishes revision 2,
  diffs the two charts, builds the migration plan from the blocks mapping
  and completes it by hand for the renamed step, previews it with a dry
  run, applies it, reads the old chart drained, asks to retire the old
  chart, and rolls the loans back with the reverse plan. It then cancels
  the two loans it opened, so the next run starts from an empty chart:
  `StatifierPersistence.Executions.migrate_batch/3` takes every waiting
  execution on a chart, not only this run's.

  The retirement is refused on this database, and the task says so rather
  than stopping: a retirement nulls the chart's two blob columns, which
  stay `NOT NULL` on SQLite. That refusal is also why the rollback stays
  available here - a reverse plan cannot target a retired chart.

  A step that does not answer as the guide says stops the task with a
  non-zero exit and names the step: an error or a refusal from a call, and
  also a batch or a count that answered but not with what the guide shows
  (`expect/3` holds each one to its expected counts). Run
  `mix ecto.migrate` first.
  """

  use Mix.Task

  import Ecto.Query, only: [from: 2]

  alias Statifier.{Chart, Machine}
  alias StatifierBlocks.{Compiler, Decode, Migration}
  alias StatifierExamples.{Charts, FirstWorkflow, Publish}
  alias StatifierExamples.Charts.ExecutionLock
  alias StatifierPersistence.{Driver, Executions, Storage}
  alias StatifierPersistence.Migration.Plan

  @requirements ["app.start"]

  # The one step revision 2 renames: its block id, old to new.
  @renamed {"blk_awaiting_return", "blk_on_loan"}

  @serialization {ExecutionLock, ExecutionLock}

  @impl Mix.Task
  def run(_argv) do
    if Logger.compare_levels(Logger.level(), :info) == :lt, do: Logger.configure(level: :info)

    case walk() do
      {:ok, lines} ->
        Enum.each(lines, &Mix.shell().info/1)

      {:error, step, reason} ->
        Mix.raise("migrate waiting: #{step} did not hold: #{inspect(reason)}")
    end
  end

  @doc """
  Walks the path once and answers the lines `run/1` prints, or the first
  step that did not hold. `opts` takes `:loans`, the two execution ids to
  open (default two fresh ones).
  """
  @spec walk(keyword()) :: {:ok, [String.t()]} | {:error, atom(), term()}
  def walk(opts \\ []) do
    loans = Keyword.get_lazy(opts, :loans, fn -> Enum.map(1..2, &"loan_#{suffix()}_#{&1}") end)
    store = FirstWorkflow.store()
    n = length(loans)

    with {:ok, old} <- step(:registered, register(document(1))),
         :ok <- step(:waiting, open(store, old, loans)),
         {:ok, new, warnings} <- step(:published, publish(document(2))),
         {:ok, mapping} <- step(:mapped, Migration.plan(old.compiled, new.compiled)),
         plan =
           completed_plan(old, new, mapping, [{:add, "damaged", false}, {:add, "repair", false}]),
         {:ok, blocks_only} <- step(:planned, plan(old, new, mapping["states"], [], [])),
         {:ok, forward} <- step(:planned, plan),
         {:ok, preview_blocks} <- step(:dry_run, batch(store, blocks_only, old, new, true)),
         :ok <- expect(:dry_run, preview_blocks, %{would_migrate: 0, would_refuse: n}),
         {:ok, preview} <- step(:dry_run, batch(store, forward, old, new, true)),
         :ok <- expect(:dry_run, preview, %{would_migrate: n, would_refuse: 0}),
         {:ok, applied} <- step(:applied, batch(store, forward, old, new, false)),
         :ok <- expect(:applied, applied, %{migrated: n, refused: 0, parked: 0}),
         {:ok, drained} <- step(:drained, Executions.executions_on(store, old.hash)),
         :ok <- expect(:drained, drained, %{active: 0, needs_migration: 0}),
         {:ok, landed} <- step(:drained, Executions.executions_on(store, new.hash)),
         :ok <- expect(:drained, landed, %{active: n, needs_migration: 0}),
         timers = scheduled_timers(loans),
         :ok <- expect(:timers, %{scheduled: timers}, %{scheduled: n}),
         {:error, retire} <- retire(store, old.hash),
         {:ok, reverse_map} <- step(:rollback, Migration.plan(new.compiled, old.compiled)),
         {:ok, reverse} <-
           step(
             :rollback,
             completed_plan(new, old, reverse_map, [{:remove, "damaged"}, {:remove, "repair"}])
           ),
         {:ok, reverse_preview} <- step(:rollback, batch(store, reverse, new, old, true)),
         :ok <- expect(:rollback, reverse_preview, %{would_migrate: n, would_refuse: 0}),
         {:ok, rolled_back} <- step(:rollback, batch(store, reverse, new, old, false)),
         :ok <- expect(:rollback, rolled_back, %{migrated: n, refused: 0, parked: 0}),
         :ok <- step(:tidied, tidy(store, loans)) do
      {:ok,
       [
         "migrate waiting on statifier_persistence #{Application.spec(:statifier_persistence, :vsn)}",
         "waiting      #{length(loans)} loan(s) on revision 1, #{old.hash}, each with its due-date timer",
         "published    revision 2, #{new.hash}, #{length(warnings)} warning(s)",
         "diff         #{diff_line(old, new, mapping["states"])} with the blocks mapping, " <>
           "#{diff_line(old, new, forward.states)} with the plan",
         "plan         the blocks mapping maps #{map_size(mapping["states"])} state(s) and leaves " <>
           "#{length(mapping["unmapped"])} unmapped; the plan maps those to #{elem(@renamed, 1)}",
         "dry run      blocks mapping alone: #{counts(preview_blocks)}; the plan: #{counts(preview)}",
         "applied      #{counts(applied)}",
         "drained      revision 1: #{on(drained)}; revision 2: #{on(landed)}",
         "timers       #{timers} due-date timer(s) still scheduled, untouched by the move",
         "retire       revision 1: #{inspect(retire)}; this store cannot tombstone a chart",
         "rollback     the reverse plan, revision 2 to 1: #{counts(reverse_preview)}, " <>
           "then #{counts(rolled_back)}",
         "tidied       cancelled the #{length(loans)} loan(s) this run opened"
       ]}
    else
      {:error, _step, _reason} = error -> error
      {:ok, retired} -> {:error, :retire, {:unexpectedly_retired, retired}}
      other -> {:error, :unexpected, other}
    end
  end

  @doc """
  Holds one step's answer to the counts the guide shows for it: `:ok` when
  every key of `expected` has its value in `answer`, and
  `{:error, step, {:unexpected, counts}}` otherwise, naming the step and
  every count it did answer.

  `answer` is a `StatifierPersistence.Executions.migrate_batch/3` report,
  whose `counts` are read, or a plain map of counts such as
  `StatifierPersistence.Executions.executions_on/2` answers. A batch
  answers `{:ok, report}` whatever each execution's outcome was, so an
  apply that refuses every loan is still `{:ok, report}`; this is what
  stops the task on it.
  """
  @spec expect(atom(), map(), %{atom() => non_neg_integer()}) ::
          :ok | {:error, atom(), {:unexpected, map()}}
  def expect(step, %{counts: counts}, expected), do: expect(step, counts, expected)

  def expect(step, counts, expected) when is_map(counts) do
    if Map.take(counts, Map.keys(expected)) == expected,
      do: :ok,
      else: {:error, step, {:unexpected, counts}}
  end

  # ------------------------------------------------------------ the loan

  # Two revisions of one loan document. Revision 2 renames the waiting step
  # (a new block id) and gives the check-in step a `damaged` arm.
  @spec document(1 | 2) :: map()
  defp document(revision) do
    {old_id, new_id} = @renamed
    two? = revision == 2
    damaged = if two?, do: [%{"slot" => "arm_damaged", "cond" => "damaged"}], else: []
    repair = if two?, do: %{"arm_damaged" => [assign("blk_send_to_repair", "repair")]}, else: %{}

    %{
      "schema_version" => 1,
      "id" => "bdoc_loan_waiting",
      "revision" => revision,
      "metadata" => %{"name" => "Library loan (waiting)", "domain" => "library"},
      "datamodel" =>
        Enum.map(
          ~w(returned closed overdue) ++ if(two?, do: ~w(damaged repair), else: []),
          &flag/1
        ),
      "accepts" => ["copy.returned"],
      "root" =>
        block("core.sequence", "blk_loan", %{}, %{
          "body" => [
            block("core.group", if(two?, do: new_id, else: old_id), %{}, %{
              "body" => [block("core.wait", "blk_due_date", %{"duration" => "21d"}, %{})],
              "interrupts" => [
                block(
                  "core.on_event",
                  "blk_returned",
                  %{"event" => "copy.returned", "outcome" => "abandon"},
                  %{}
                )
              ]
            }),
            block(
              "core.branch",
              "blk_check_in",
              %{"arms" => damaged ++ [%{"slot" => "arm_returned", "cond" => "returned"}]},
              Map.merge(
                %{
                  "arm_returned" => [assign("blk_close", "closed")],
                  "otherwise" => [assign("blk_overdue", "overdue")]
                },
                repair
              )
            )
          ]
        })
    }
  end

  defp block(type, id, config, slots),
    do: %{"type" => type, "id" => id, "type_version" => 1, "config" => config, "slots" => slots}

  defp assign(id, path), do: block("core.assign", id, %{"path" => path, "value" => "true"}, %{})
  defp flag(id), do: %{"id" => id, "expr" => "false"}

  # ----------------------------------------------------------- the steps

  defp step(_step, :ok), do: :ok
  defp step(_step, {:ok, _} = ok), do: ok
  defp step(_step, {:ok, _, _} = ok), do: ok
  defp step(step, {:refused, refusal}), do: {:error, step, refusal}
  defp step(step, {:error, reason}), do: {:error, step, reason}

  # Compiles and stores the chart, so an execution and a fired timer can
  # rebuild it from its content hash alone.
  defp register(map) do
    with {:ok, document} <- map |> Jason.encode!() |> Decode.decode(),
         {:ok, compiled} <- Compiler.compile(document, Charts.palette(), terminate: true),
         {:ok, machine} <- Statifier.compile(compiled.scxml),
         :ok <- Storage.save_chart(FirstWorkflow.store(), machine, compiled.scxml) do
      {:ok, %{compiled: compiled, machine: machine, hash: Machine.identity(machine).content_hash}}
    end
  end

  # The host's publish step over revision 2, then the same registration.
  defp publish(map) do
    {:ok, router} =
      StatifierRouter.Config.new(
        repo: StatifierExamples.Repo,
        delivery: FirstWorkflow.NoRoute,
        send_type: "myapp:route",
        route_adapters: %{}
      )

    with {:ok, document} <- map |> Jason.encode!() |> Decode.decode(),
         {:ok, _compiled, _accepts, warnings} <-
           Publish.check(document, %{
             palette: Charts.palette(),
             datamodel: nil,
             send_types: %{},
             router_config: router,
             accepts_lookup: fn _document -> {:error, :not_published} end,
             document_resolver: fn _document -> {:error, :not_published} end
           }),
         {:ok, chart} <- register(map) do
      {:ok, chart, warnings}
    end
  end

  # Each loan enters `awaiting_return`, and the driver's executor stores
  # its due-date timer as a scheduled Oban job.
  defp open(store, chart, loans) do
    Enum.reduce_while(loans, :ok, fn loan, :ok ->
      case store |> FirstWorkflow.driver(chart.machine) |> Driver.create(loan) do
        {:ok, %{status: :active}, _state} -> {:cont, :ok}
        other -> {:halt, {:error, {loan, other}}}
      end
    end)
  end

  # The blocks mapping, completed by hand: every state of the renamed step
  # is mapped to the same role of its new block id, and every other state
  # the mapping leaves unmapped is dropped on purpose.
  defp completed_plan(from, to, mapping, datamodel) do
    {renames, drops} =
      Enum.reduce(mapping["unmapped"], {%{}, []}, fn %{"state_id" => id}, {renames, drops} ->
        case renamed_state(id, to.machine) do
          nil -> {renames, [id | drops]}
          target -> {Map.put(renames, id, target), drops}
        end
      end)

    plan(from, to, Map.merge(mapping["states"], renames), Enum.sort(drops), datamodel)
  end

  defp renamed_state(id, machine) do
    target =
      Enum.find_value([@renamed, swap(@renamed)], fn {old, new} ->
        if String.starts_with?(id, "s_" <> old),
          do: String.replace_prefix(id, "s_" <> old, "s_" <> new)
      end)

    if target && Map.has_key?(machine.id_to_index, target), do: target
  end

  defp swap({a, b}), do: {b, a}

  defp plan(from, to, states, drop, datamodel) do
    Plan.new(from: from.hash, to: to.hash, states: states, drop: drop, datamodel: datamodel)
  end

  defp batch(store, plan, from, to, dry_run?) do
    Executions.migrate_batch(store, plan,
      from_machine: from.machine,
      to_machine: to.machine,
      dry_run: dry_run?,
      serialization: @serialization
    )
  end

  # This database cannot carry a tombstone, so the retirement answers its
  # refusal; any other answer stops the task.
  defp retire(store, hash) do
    case Executions.retire_chart(store, hash, [],
           retired_by: "mix statifier_examples.migrate_waiting"
         ) do
      {:error, :chart_retirement_unsupported} -> {:error, :chart_retirement_unsupported}
      {:ok, retired} -> {:ok, retired}
      {:error, reason} -> {:error, :retire, reason}
    end
  end

  # The loans' timer jobs still waiting to fire. A migration writes no
  # timer: a plan that maps the state around one keeps it (`keep_mapped`).
  defp scheduled_timers(loans) do
    StatifierExamples.Repo.all(
      from(j in Oban.Job,
        where: j.worker == "StatifierOban.Timer.Worker" and j.state == "scheduled",
        select: j.args
      )
    )
    |> Enum.count(&(&1["scope"] in loans))
  end

  defp tidy(store, loans) do
    Enum.reduce_while(loans, :ok, fn loan, :ok ->
      case Executions.cancel(store, loan, serialization: @serialization) do
        {:ok, _execution} -> {:cont, :ok}
        other -> {:halt, {:error, {loan, other}}}
      end
    end)
  end

  # ---------------------------------------------------------- the output

  defp diff_line(from, to, states) do
    %{class: class, reasons: reasons} = Chart.diff(from.machine, to.machine, mapping: states)
    unresolved = Enum.count(reasons, &match?({:state_unresolved, _}, &1))
    "#{class} (#{unresolved} unresolved)"
  end

  defp counts(%{counts: counts}),
    do: counts |> Enum.sort() |> Enum.map_join(", ", fn {outcome, n} -> "#{outcome} #{n}" end)

  defp on(counts), do: "active #{counts.active}, needs_migration #{counts.needs_migration}"

  defp suffix, do: 4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
