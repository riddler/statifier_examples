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

  Telemetry is read the same way. A handler is attached, before the drive,
  to every event `statifier`, `statifier_persistence` and `statifier_oban`
  name in their `events/0` and to the router's one event, and each event's metadata and
  measurements go through the same search as a row column. The drive
  includes one message the router's binding does not take, so that event
  fires; a drive that emitted nothing from one of the four packages fails,
  rather than passes.

  The search is not only for the value as typed. Each posted value is also
  searched for by its distinctive fragments, case-folded: each token of at
  least six characters of a value (so each name token and each word of the
  street address), each token of the part of an email address before the
  "@" (never the domain), and a phone number's digits
  alone (so also the number as an integer, or with other punctuation). A
  charlist, or iodata mixing strings and bytes, is read as the text it
  prints as. A shorter fragment is left out, since it would also turn up in
  unrelated text. Every form of a fragment has a control that plants it in
  a copy of a row and of an event's metadata and shows the search find it,
  and a control that shows unrelated text is not a hit.

  The same search finds every value in `card_applications`, the host's own
  table, so a search that could find nothing is a failure, not a pass.

  Three of the tables below hold no row after the drive, so the scan reads
  nothing from them, and a leak into one would not be seen here:
  `statifier_positions` (no step of the drive writes a position snapshot;
  nothing calls `save_position/3`; the engine keeps the position as a blob
  on `statifier_executions`, which is scanned and decoded below), `statifier_router_subscriptions` (no chart in the
  drive subscribes to a source) and `statifier_router_locations` (the
  router writes one only on a configuration that sets `:basichttp`, and
  this recipe's `Router.config/0` does not). The test fails if that
  list changes.

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
    IntakeJob,
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

  # A fragment shorter than this is not searched for: a short run of
  # letters or digits would turn up in unrelated text and fail the test
  # for nothing.
  @min_fragment 6

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

  # The router names its one event in `StatifierRouter` (a module
  # attribute, no `events/0`): a route whose binding's match does not hold.
  @router_events [[:statifier_router, :route, :no_match]]

  # The tables the drive leaves without a row, so the scan reads nothing
  # from them (the moduledoc says why). One that gains a row fails the
  # assertion that uses this list, which is the cue to name it as scanned.
  @empty_tables ~w(
    statifier_positions
    statifier_router_locations
    statifier_router_subscriptions
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

    # The handler id is unique to this test, and the module is not async,
    # so no other test's events reach this mailbox.
    handler_id = "ids-only-#{inspect(make_ref())}"
    test_pid = self()

    :telemetry.attach_many(
      handler_id,
      telemetry_events(),
      fn event, measurements, metadata, pid ->
        send(pid, {:telemetry, event, measurements, metadata})
      end,
      test_pid
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Application.delete_env(:statifier_examples, ScreenApplication)
    end)

    :ok
  end

  # Sabotage (telemetry): the posted email address added to the metadata of
  # `StatifierRouter`'s no-match event, and the posted phone number to the
  # metadata of `StatifierOban`'s timer-scheduled event, each in a copy of
  # the dependency; each went red on the telemetry search, naming the
  # event. The same through the test: events emitted with a posted value
  # in metadata (nested in a list), in measurements, and Base64-wrapped in
  # JSON; each red. Reverted from a copy.
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

    # ... and a value nested in an event's metadata.
    assert @form["email"] in found(%{"event" => %{detail: [%{value: @form["email"]}]}})

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

    # A message the binding's match does not take: the router's one event.
    assert {:ok, [{:no_match, binding}]} =
             StatifierRouter.Webhook.handle(Router.config(), IntakeJob.request("riverbend", 0))

    assert binding == Router.binding_id()

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

    assert Enum.sort(for({table, []} <- scanned, do: table)) == @empty_tables,
           "the tables the drive leaves empty are the ones the moduledoc names"

    decoded = %{
      "the position's datamodel" => [%{"datamodel" => position.datamodel}],
      "the position" => [%{"state" => position |> Map.from_struct() |> Map.delete(:machine)}],
      "the input log" => [%{"inputs" => inputs}]
    }

    assert [] == hits(Map.merge(scanned, decoded))

    # Every event the drive emitted: metadata and measurements, searched
    # with the same decoder. Each package must have emitted something, or
    # the search proves nothing about it.
    events = drain_telemetry([])

    for family <- [:statifier, :statifier_persistence, :statifier_oban, :statifier_router] do
      assert Enum.any?(events, fn {name, _measurements, _metadata} -> hd(name) == family end),
             "the drive emitted no #{family} event"
    end

    telemetry = %{
      "telemetry metadata" =>
        for({name, _m, metadata} <- events, do: %{inspect(name) => metadata}),
      "telemetry measurements" =>
        for({name, measurements, _m} <- events, do: %{inspect(name) => measurements})
    }

    assert [] == hits(telemetry)

    # The same search finds every posted value in the host's own table.
    assert MapSet.new(Map.values(@form)) ==
             MapSet.new(
               for {_where, value} <- hits(%{@host_table => rows(@host_table)}), do: value
             )
  end

  # The ways a posted value could survive in part or reshaped, each as the
  # value a layer might hold and the posted value it must be found as.
  # The search is proved on each one, planted in a copy of a row and in a
  # map of event metadata, so a search that has lost a form fails here and
  # not silently in the real scan above.
  @fragment_controls [
    {"the first name alone", "Quillon", "name"},
    {"the last name alone", "Varrowmere", "name"},
    {"the name lowercased", "quillon varrowmere", "name"},
    {"the name uppercased", "QUILLON VARROWMERE", "name"},
    {"the name reversed", "Varrowmere, Quillon", "name"},
    {"the email's local part", "quillon.varrowmere", "email"},
    {"the email uppercased", "QUILLON.VARROWMERE@EXAMPLE.COM", "email"},
    {"the phone as digits only", "55501874410", "phone"},
    {"the phone as an integer", 55_501_874_410, "phone"},
    {"the phone with other separators", "(555) 018 7441 0", "phone"},
    {"the street address's distinctive word", "lantern", "street_address"},
    {"a charlist", ~c"Quillon Varrowmere", "name"},
    {"a charlist of the phone as digits", ~c"55501874410", "phone"},
    {"iodata of strings", ["Quil", [?l, ?o, "n Varrow"], "mere"], "name"},
    {"iodata of strings and bytes", ["quil", ~c"lon.varro", "wmere", ?@, "example.com"], "email"},
    {"a fragment inside longer text", "Dear quillon, thanks for writing", "name"},
    {"a fragment inside JSON", ~s({"to":"Quillon"}), "name"}
  ]

  # Sabotage: dropped in turn the tokens, the digits, the case-folding,
  # the separator strip, the charlist and iodata join and the integer read
  # from the search, and the minimum length; each went red on the controls
  # that name it. The whole value as a fragment is also kept, but the
  # tokens and digits find everything this fixture holds, so dropping it
  # alone stays green. Reverted from a copy.
  for {kind, planted, field} <- @fragment_controls do
    test "the search finds #{kind}, in a row and in event metadata" do
      posted = @form[unquote(field)]
      planted = unquote(Macro.escape(planted))

      row = %{"id" => 1, "kept" => "ordinary text", "column" => planted}

      assert posted in found_values(%{"control" => [row]})

      metadata = %{"event" => [%{detail: %{value: planted}}], "other" => 1}

      assert posted in found_values(%{"telemetry" => [metadata]})
    end
  end

  # Text that holds no posted value, or only a fragment under the
  # minimum, is not a hit: the other side of the controls above.
  for {kind, unrelated} <- [
        {"ordinary words", "A short, ordinary sentence."},
        {"a short fragment of the street address", "Court"},
        {"a short run of the phone's digits", "4410"},
        {"the email's domain", "example.com"},
        {"a charlist of unrelated text", ~c"nothing posted"},
        {"an unrelated integer", 42}
      ] do
    test "the search finds nothing in #{kind}" do
      assert [] == hits(%{"control" => [%{"column" => unquote(Macro.escape(unrelated))}]})
    end
  end

  # Every event name the three packages emit, from the packages' own lists
  # where they have one.
  defp telemetry_events do
    Statifier.Telemetry.events() ++
      StatifierPersistence.Telemetry.events() ++
      StatifierOban.Telemetry.events() ++ @router_events
  end

  # The events the handler sent this process, as `{name, measurements,
  # metadata}`, in the order they arrived.
  defp drain_telemetry(acc) do
    receive do
      {:telemetry, name, measurements, metadata} ->
        drain_telemetry([{name, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
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

  # The posted values a set of tables holds, wherever.
  defp found_values(tables), do: Enum.uniq(for {_where, value} <- hits(tables), do: value)

  # Each posted value found, with where: `{"table.column", value}`.
  defp hits(tables) do
    for {table, rows} <- tables,
        row <- rows,
        {column, value} <- row,
        found <- found(value),
        uniq: true,
        do: {"#{table}.#{column}", found}
  end

  # The posted values a stored value holds, raw or decoded, whole or in
  # part: a posted value is found when any of its fragments (see
  # `fragments/1`) is in any text the value holds, case-folded.
  defp found(value) do
    folded = value |> texts([]) |> Enum.map(&String.downcase/1)
    bare = Enum.map(folded, &String.replace(&1, ~r/[\s().-]/, ""))

    for posted <- Map.values(@form),
        Enum.any?(fragments(posted), &fragment_in?(&1, folded, bare)),
        do: posted
  end

  # Digits are looked for with a phone number's separators taken out of
  # the text (`bare`); a word is looked for as it is.
  defp fragment_in?(fragment, folded, bare) do
    texts = if fragment =~ ~r/\A\d+\z/, do: bare, else: folded
    Enum.any?(texts, &String.contains?(&1, fragment))
  end

  # What would identify a posted value if a layer kept only part of it,
  # all case-folded: the value itself; each token of it (a run of letters
  # and digits) of at least `@min_fragment` characters, which covers each
  # name token and the part of an email address before the "@" (never the
  # domain, which any address shares); and,
  # for a value holding at least `@min_fragment` digits, those digits
  # alone (the phone number without its punctuation, which is also what
  # the number as an integer prints as). A shorter token is left out: it
  # would also be found in unrelated text.
  defp fragments(posted) do
    local = posted |> String.split("@") |> hd()
    tokens = ~r/[[:alnum:]]+/u |> Regex.scan(local) |> List.flatten()
    digits = String.replace(posted, ~r/\D/, "")

    ([posted] ++ tokens ++ [digits])
    |> Enum.filter(&(String.length(&1) >= @min_fragment))
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
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
  # A list is read as it is stored (element by element) and as the text it
  # would print as: a charlist, or iodata mixing strings and bytes.
  defp texts([_head | _tail] = list, acc) do
    acc = list |> chardata() |> texts_of_chardata(acc)
    Enum.reduce(improper_free(list), acc, &texts/2)
  end

  defp texts(value, acc) when is_integer(value), do: [Integer.to_string(value) | acc]
  defp texts(_other, acc), do: acc

  defp texts_of_chardata(nil, acc), do: acc
  defp texts_of_chardata(text, acc), do: texts(text, acc)

  # The list as one string, or nil when it is not text.
  defp chardata(list) do
    IO.chardata_to_string(list)
  rescue
    _not_chardata -> nil
  end

  # A list's elements, an improper tail kept as the last element.
  defp improper_free([head | tail]) when is_list(tail), do: [head | improper_free(tail)]
  defp improper_free([head | tail]), do: [head, tail]
  defp improper_free([]), do: []

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
