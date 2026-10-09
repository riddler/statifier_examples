defmodule StatifierExamples.FormPost.IdsOnlyTest do
  @moduledoc """
  The card application recipe's claim, checked row by row: no value a
  visitor typed on the form reaches a row the engine or the router owns.

  One application is posted with a name, an email address, a phone number
  and a street address no other row could hold by chance, and driven to
  completion on the app's Oban through `StatifierExamples.FormPost.Drain`:
  both routes (the patron system and the newsletter list) and the screen's
  deadline firing. Then every row of every engine-owned and router-owned
  table, and of the recipe's outbox, is read and every column searched, raw
  and decoded: a `term_to_binary` blob is decoded, a JSON column is parsed,
  and a Base64 string (how `statifier_oban` stores its opaque fields in a
  job's arguments) is unwrapped, all the way down. The execution's position
  is also decoded to its datamodel through the stored chart, and its input
  log read through the store.

  The same search finds every value in `card_applications`, the host's own
  table, so a search that could find nothing is a failure, not a pass.

  The tables are read from the migrated database and the engine's schemas,
  not from a list alone: a table a later dependency bump adds fails this
  test until it is named below, either as scanned or as excluded with a
  reason.

  Not async: writes to the repo, runs Oban jobs in the test process and
  sets the application environment.
  """
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.{FirstWorkflow, Repo}

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplications,
    CardApplicationSend,
    Drain,
    PublishedCharts,
    Router,
    ScreenApplication
  }

  alias StatifierOban.OpaqueTerm
  alias StatifierOban.Timer.Worker, as: TimerWorker
  alias StatifierPersistence.{Execution, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.{Address, Dedupe, Ledger, Location, Subscription}

  # What the visitor typed, each value one no other row holds by chance.
  # All of it is fiction.
  @form %{
    "name" => "Quillon Varrowmere",
    "email" => "quillon.varrowmere@example.com",
    "phone" => "555-0187-4410",
    "street_address" => "4417 Lantern Court"
  }

  # Every table the engine and the router own: statifier_persistence's
  # four, statifier_router's five and Oban's jobs table, where
  # statifier_oban's step jobs and deadline timers live.
  @engine_tables ~w(
    statifier_charts
    statifier_positions
    statifier_executions
    statifier_inputs
    statifier_router_addresses
    statifier_router_dedupe
    statifier_router_routing_ledger
    statifier_router_subscriptions
    statifier_router_locations
    oban_jobs
  )

  # The recipe's outbox: the host's, but it holds ids and the outside
  # systems' references, never a posted value.
  @outbox "card_application_sends"

  # The host's own table, where the posted values belong.
  @host_table "card_applications"

  # The tables neither scanned nor searched for the values, each with the
  # reason it holds none of them.
  @excluded %{
    "users" => "the signup fixtures' accounts; the recipe never writes one",
    "invite_outcomes" => "the signup fixtures' outcomes; the recipe never writes one",
    "schema_migrations" => "Ecto's applied migration versions",
    "sqlite_sequence" => "SQLite's own counters: a table name and an integer"
  }

  setup do
    :ok = Sandbox.checkout(Repo)
    {:ok, machine, scxml} = PublishedCharts.runtime_chart()
    :ok = Storage.save_chart(FirstWorkflow.store(), machine, scxml)

    on_exit(fn -> Application.delete_env(:statifier_examples, ScreenApplication) end)

    :ok
  end

  # Sabotage: put the email address into the intake job's request data
  # (`IntakeJob.route/1`) and widened the binding's `data:` in `Router` to
  # carry it; this went red on the input log, raw and decoded. The request
  # data alone stayed green: the binding projects `application_id` and
  # nothing else. Putting the email into the intake job's arguments
  # (`CardApplications`) went red on `oban_jobs.args`. Each reverted from
  # a copy.
  test "no posted value reaches an engine or router row, on both routes with the screen past its bound" do
    # Every table in the migrated database is named here, and every table
    # the engine's schemas read is one of the scanned ones.
    assert MapSet.new(database_tables()) ==
             MapSet.new(@engine_tables ++ [@outbox, @host_table] ++ Map.keys(@excluded)),
           "every table is scanned, or excluded with a reason"

    assert MapSet.subset?(MapSet.new(schema_tables()), MapSet.new(@engine_tables))

    # The search reaches a value however a layer stores it.
    for hidden <- hidden_values(@form["email"]) do
      assert @form["email"] in found(hidden), "the search missed #{inspect(hidden)}"
    end

    # The screen fails every time it runs, so its deadline fires and the
    # flow goes on without it; the application asks for both routes.
    Application.put_env(:statifier_examples, ScreenApplication, fail: true)

    {:ok, %CardApplication{id: id}, :created} =
      CardApplications.receive_application(
        "riverbend",
        Map.merge(@form, %{
          "wants_card" => "true",
          "wants_newsletter" => "true",
          "idempotency_key" => "form-#{System.unique_integer([:positive])}"
        })
      )

    assert {:ok, %{failure: 1}} = Drain.run()
    execution_id = execution_id(id)
    assert %Oban.Job{state: "scheduled", scheduled_at: due} = screen_deadline(execution_id)
    assert {:ok, %{discard: 0}} = Drain.run(until: due)

    store = FirstWorkflow.store()
    {:ok, record} = Storage.fetch_execution(store, execution_id)
    {:ok, machine} = PublishedCharts.chart(record.content_hash)
    {:ok, position} = Storage.load_execution_position(store, execution_id, machine)
    {:ok, inputs} = Storage.list_inputs(store, execution_id)

    assert %Execution{status: :completed} = Execution.from_record(record)

    assert %{
             "application_id" => ^id,
             "screen" => "unscreened",
             "sort" => "both",
             "area" => "inside"
           } = position.datamodel

    assert inputs != []
    assert ["newsletter", "patron_system"] == sends(id)

    # Every row of every scanned table, and the decoded position and input
    # log, hold none of the posted values.
    scanned = Map.new(@engine_tables ++ [@outbox], &{&1, rows(&1)})

    for table <- ~w(statifier_executions statifier_router_addresses statifier_router_dedupe
                    statifier_router_routing_ledger oban_jobs card_application_sends) do
      assert scanned[table] != [], "#{table} has no row to search"
    end

    decoded = %{
      "the position's datamodel" => [%{"datamodel" => position.datamodel}],
      "the position" => [%{"state" => position |> Map.from_struct() |> Map.delete(:machine)}],
      "the input log" => [%{"inputs" => inputs}]
    }

    assert [] == hits(Map.merge(scanned, decoded))

    # The same search finds every posted value in the host's own table.
    assert MapSet.new(Map.values(@form)) ==
             MapSet.new(
               for {_where, value} <- hits(%{@host_table => rows(@host_table)}), do: value
             )
  end

  # Every table SQLite holds, as migrated.
  defp database_tables do
    Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'").rows
    |> Enum.map(fn [name] -> name end)
  end

  # The table each engine schema reads, under this app's configuration.
  defp schema_tables do
    persistence =
      for name <- ~w(Chart Position Execution Input) do
        Module.concat(StatifierExamples.Persistence, name).__schema__(:source)
      end

    router =
      for schema <- [Address, Dedupe, Ledger, Location, Subscription] do
        %Ecto.Query{from: %{source: {table, _schema}}} =
          Config.queryable(Router.config(), schema)

        table
      end

    [Oban.Job.__schema__(:source) | persistence ++ router]
  end

  # Every row of `table`, as a map of column to value. The table name is
  # one of this module's own, checked against `sqlite_master` above.
  defp rows(table) do
    %{columns: columns, rows: rows} = Repo.query!("SELECT * FROM #{table}")
    Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
  end

  # Each posted value found, with where: `{"table.column", value}`.
  defp hits(tables) do
    for {table, rows} <- tables,
        row <- rows,
        {column, value} <- row,
        found <- found(value),
        uniq: true,
        do: {"#{table}.#{column}", found}
  end

  # The posted values a stored value holds, raw or decoded.
  defp found(value) do
    texts = texts(value, [])
    for {_field, posted} <- @form, Enum.any?(texts, &String.contains?(&1, posted)), do: posted
  end

  # The one value, stored the way each layer stores a value it is handed:
  # a term blob, a JSON column, and statifier_oban's Base64 opaque field
  # inside a job's JSON arguments.
  defp hidden_values(value) do
    {:ok, opaque} = OpaqueTerm.encode(%{"data" => %{"value" => value}})

    [
      :erlang.term_to_binary({:position, %{"datamodel" => %{"value" => value}}}),
      JSON.encode!(%{"data" => %{"value" => value}}),
      JSON.encode!(%{"params" => opaque})
    ]
  end

  # Every string a value holds, unwrapping each layer that can hide one.
  defp texts(value, acc) when is_binary(value) do
    [value | acc]
    |> unwrap_term(value)
    |> unwrap_json(value)
    |> unwrap_base64(value)
  end

  defp texts(value, acc) when is_atom(value), do: [Atom.to_string(value) | acc]
  defp texts(%_{} = value, acc), do: texts(Map.from_struct(value), acc)

  defp texts(value, acc) when is_map(value),
    do: Enum.reduce(value, acc, fn {k, v}, acc -> texts(v, texts(k, acc)) end)

  defp texts(value, acc) when is_tuple(value), do: texts(Tuple.to_list(value), acc)
  defp texts([head | tail], acc), do: texts(tail, texts(head, acc))
  defp texts(_other, acc), do: acc

  defp unwrap_term(acc, <<131, _rest::binary>> = blob) do
    texts(:erlang.binary_to_term(blob), acc)
  rescue
    ArgumentError -> acc
  end

  defp unwrap_term(acc, _value), do: acc

  defp unwrap_json(acc, <<first, _rest::binary>> = text) when first in ~c"{[" do
    case JSON.decode(text) do
      {:ok, decoded} -> texts(decoded, acc)
      {:error, _reason} -> acc
    end
  end

  defp unwrap_json(acc, _value), do: acc

  # Only a string that is Base64 and nothing else, long enough to hold a
  # term: every Base64 string unwrapped would also unwrap ordinary words.
  defp unwrap_base64(acc, text) when byte_size(text) >= 8 do
    with true <- String.match?(text, ~r/\A[A-Za-z0-9+\/]+={0,2}\z/),
         {:ok, decoded} <- Base.decode64(text) do
      texts(decoded, acc)
    else
      _not_base64 -> acc
    end
  end

  defp unwrap_base64(acc, _value), do: acc

  defp execution_id(id) do
    key = Integer.to_string(id)

    Repo.one!(
      from(a in Config.queryable(Router.config(), Address),
        where: a.document == ^Router.document_id() and a.key == ^key,
        select: a.execution_id
      )
    )
  end

  defp screen_deadline(execution_id) do
    worker = Oban.Worker.to_string(TimerWorker)

    Repo.one!(
      from(j in Oban.Job,
        where:
          j.worker == ^worker and j.args["scope"] == ^execution_id and
            j.args["event"] == "deadline.screen"
      )
    )
  end

  defp sends(id) do
    Repo.all(
      from(s in CardApplicationSend,
        where: s.application_id == ^id,
        order_by: s.route,
        select: s.route
      )
    )
  end
end
