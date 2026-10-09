defmodule StatifierExamples.FormPost do
  @moduledoc """
  The recipe `docs/guides/first-workflow-form-post.md` walks, as code: the
  Riverbend Public Library's card application form, stored first and
  routed from a job, with every effect on this app's own Oban.

  A visitor posts the form. The host stores the post in its own
  `card_applications` table and answers before any engine work; a job
  hands the stored row's id, and nothing else, to `statifier_router`'s
  webhook front; the chart screens the application, sorts it, checks the
  address against the library's service area, and hands it to the patron
  system and the newsletter list. `run/1` takes it through nine steps and
  checks each one before the next:

    1. `:registered` - the card application document compiled for
       running, stored under its content hash, and the resolver
       (`StatifierExamples.FormPost.PublishedCharts`) answering that hash.
    2. `:stored` - `StatifierExamples.FormPost.CardApplications.receive_application/2`
       stores one application and enqueues one intake job whose arguments
       are the row's id alone.
    3. `:repeat` - the same form posted again, with the same client key,
       answers the first application and stores nothing, row or job.
    4. `:routed` - `StatifierExamples.FormPost.Drain` runs the intake job,
       the three steps' jobs and the deadline timers until the execution
       completes with the steps' three words.
    5. `:sent` - the two routes wrote one outbox row each, and the
       application carries both references and the status `"sent"`.
    6. `:duplicate` - the intake job's routing, run a second time for the
       same application, is answered as a duplicate, and the routing
       ledger holds one row per attempt.
    7. `:ids_only` - none of the four posted personal values is in the
       execution's datamodel, its input log, or any of the application's
       jobs' arguments, with every `statifier_oban` opaque field in them
       decoded first.
    8. `:screened_out` - an application whose street address is a post
       office box ends at the screen: the execution completes with the
       sort never asked, nothing is sent, and the stored application's
       status is `"screened_out"`.
    9. `:traced` - the first execution's input log, oldest first.

  `run/1` answers `{:ok, lines}`, the lines the mix task prints, or
  `{:error, step, reason}` naming the first step that did not hold.

  Every value posted here is fictional, and each run stores two new
  applications under client keys of its own.
  """

  import Ecto.Query, only: [from: 2]

  alias Statifier.Machine
  alias StatifierExamples.{FirstWorkflow, Repo}

  alias StatifierExamples.FormPost.{
    CardApplication,
    CardApplications,
    CardApplicationSend,
    Drain,
    IntakeJob,
    PublishedCharts,
    Router
  }

  alias StatifierOban.OpaqueTerm
  alias StatifierPersistence.{Execution, Executions, Storage}
  alias StatifierRouter.Config
  alias StatifierRouter.Schema.{Address, Ledger}

  # The library system the form belongs to, as the form's controller
  # fixes it.
  @scope "riverbend"

  # Two applicants, both made up. The first asks for a card and the
  # newsletter from a Riverbend street; the second gives a post office box,
  # which the screen turns away.
  @applicant %{
    "name" => "Wren Halloway",
    "email" => "wren.halloway@example.com",
    "phone" => "555-0187",
    "street_address" => "7 Ferry Street",
    "wants_card" => "true",
    "wants_newsletter" => "true"
  }

  @screened_applicant %{
    "name" => "Tobias Fenn",
    "email" => "tobias.fenn@example.com",
    "phone" => "555-0163",
    "street_address" => "PO Box 14",
    "wants_card" => "true",
    "wants_newsletter" => "false"
  }

  # The values the visitor typed that the engine must never hold.
  @personal_fields ~w(name email phone street_address)

  # The routing ledger's outcomes for one application: the intake job's
  # routing, then the same routing again.
  @ledger_outcomes ["created_and_delivered", "duplicate"]

  # How long the recipe drains and polls for a step's work before it names
  # the step that never finished.
  @deadline_ms 15_000
  @poll_ms 50

  @typedoc "The step `run/1` names when it stops; see the moduledoc."
  @type step ::
          :registered
          | :stored
          | :repeat
          | :routed
          | :sent
          | :duplicate
          | :ids_only
          | :screened_out
          | :traced
          | :unexpected

  @doc """
  Runs the recipe once, for two fresh applications, and answers the lines
  the mix task prints or the first step that did not hold.

  `opts` takes `:idempotency_key` (default a fresh key) for the first
  application, for a caller that wants to name it; the screened-out
  application's key is that key with `-po-box` added.
  """
  @spec run(keyword()) :: {:ok, [String.t()]} | {:error, step(), term()}
  def run(opts \\ []) do
    key = Keyword.get_lazy(opts, :idempotency_key, &new_key/0)

    with {:ok, content_hash} <- step(:registered, register()),
         {:ok, id} <- step(:stored, stored(key)),
         :ok <- step(:repeat, repeat(key, id)),
         {:ok, execution_id, words} <- step(:routed, routed(id)),
         {:ok, references} <- step(:sent, sent(id)),
         {:ok, outcomes} <- step(:duplicate, duplicate(id)),
         {:ok, places} <- step(:ids_only, ids_only(id, execution_id)),
         {:ok, screened} <- step(:screened_out, screened_out(key <> "-po-box")),
         {:ok, inputs} <- step(:traced, traced(execution_id)) do
      {:ok,
       [
         "first workflow from a form post on " <> pins(),
         "registered   chart #{content_hash}, the resolver's answer for #{Router.document_id()}",
         "stored       application #{id} in #{@scope}; one intake job, its arguments the id alone",
         "repeat       the same client key again: application #{id}, no second row or job",
         "routed       execution #{execution_id} completed: " <> words_line(words),
         "sent         patron_system #{references.external_reference}, " <>
           "newsletter #{references.newsletter_reference}; status sent",
         "duplicate    the intake routing run again: duplicate; the ledger reads " <>
           Enum.join(outcomes, ", "),
         "ids only     no posted value in the " <> Enum.join(places, ", "),
         "screened out application #{screened.id}: completed at the screen, " <>
           words_line(screened.words) <> "; nothing sent, status screened_out",
         "trace        the input log, oldest first:"
       ] ++ Enum.map(inputs, &trace_line/1)}
    else
      {:error, _step, _reason} = error -> error
      other -> {:error, :unexpected, other}
    end
  end

  defp step(_step, :ok), do: :ok
  defp step(_step, {:ok, _} = ok), do: ok
  defp step(_step, {:ok, _, _} = ok), do: ok
  defp step(step, {:error, reason}), do: {:error, step, reason}

  # ------------------------------------------------------------ the steps

  # The runtime compile, stored under its content hash, is the chart the
  # resolver answers for the document.
  @spec register() :: {:ok, String.t()} | {:error, term()}
  defp register do
    with {:ok, machine, scxml} <- PublishedCharts.runtime_chart(),
         :ok <- Storage.save_chart(FirstWorkflow.store(), machine, scxml),
         content_hash = Machine.identity(machine).content_hash,
         {^content_hash, %Machine{}} <- PublishedCharts.resolve(@scope, Router.document_id()) do
      {:ok, content_hash}
    else
      {:error, _reason} = error -> error
      other -> {:error, {:resolver, other}}
    end
  end

  # The post is stored, and its one intake job carries the id and nothing
  # else.
  @spec stored(String.t()) :: {:ok, integer()} | {:error, term()}
  defp stored(key) do
    with {:ok, %CardApplication{id: id}, :created} <-
           CardApplications.receive_application(@scope, form(@applicant, key)),
         [%{"application_id" => ^id} = args] when map_size(args) == 1 <- intake_args(id) do
      {:ok, id}
    else
      other -> {:error, other}
    end
  end

  # The same post again answers the first application and adds nothing.
  @spec repeat(String.t(), integer()) :: :ok | {:error, term()}
  defp repeat(key, id) do
    with {:ok, %CardApplication{id: ^id}, :repeat} <-
           CardApplications.receive_application(@scope, form(@applicant, key)),
         1 <- Repo.aggregate(stored_under(key), :count),
         [_one] <- intake_args(id) do
      :ok
    else
      other -> {:error, other}
    end
  end

  # The jobs run until the application's execution has completed.
  @spec routed(integer()) :: {:ok, String.t(), map()} | {:error, term()}
  defp routed(id) do
    with :ok <- await(fn -> completed?(id) end),
         execution_id when is_binary(execution_id) <- execution_id(id),
         {:ok, %{"screen" => "ok", "sort" => "both", "area" => "inside"} = words} <-
           words(execution_id) do
      {:ok, execution_id, words}
    else
      other -> {:error, other}
    end
  end

  # Both routes handed the application on, and wrote their references back.
  @spec sent(integer()) :: {:ok, map()} | {:error, term()}
  defp sent(id) do
    with ["newsletter", "patron_system"] <- sends(id),
         %{status: "sent", external_reference: "RPL-" <> _, newsletter_reference: "RPL-" <> _} =
           references <- references(id) do
      {:ok, references}
    else
      other -> {:error, other}
    end
  end

  # The intake job's routing again is the same message, answered as a
  # duplicate without reaching the execution.
  @spec duplicate(integer()) :: {:ok, [String.t()]} | {:error, term()}
  defp duplicate(id) do
    binding_id = Router.binding_id()

    with {:ok, [{:duplicate, ^binding_id}]} <- IntakeJob.route(id),
         @ledger_outcomes = outcomes <- Enum.map(ledger(id), & &1.outcome) do
      {:ok, outcomes}
    else
      other -> {:error, other}
    end
  end

  # What the engine holds for the application, read back, carries none of
  # the posted personal values.
  @spec ids_only(integer(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  defp ids_only(id, execution_id) do
    with {:ok, datamodel} <- datamodel(execution_id),
         {:ok, inputs} <- Executions.inputs(FirstWorkflow.store(), execution_id),
         {:ok, job_args} <- job_args(id, execution_id) do
      no_posted_value([
        {"datamodel", datamodel},
        {"input log", Enum.map(inputs, &(&1.event && &1.event.data))},
        {"job arguments", job_args}
      ])
    end
  end

  # The names of the places read, or the ones that hold a posted value.
  @spec no_posted_value([{String.t(), term()}]) :: {:ok, [String.t()]} | {:error, term()}
  defp no_posted_value(places) do
    case Enum.filter(places, fn {_place, held} -> holds_personal_value?(held) end) do
      [] -> {:ok, Enum.map(places, &elem(&1, 0))}
      found -> {:error, {:posted_value_in, Enum.map(found, &elem(&1, 0))}}
    end
  end

  # A post office box is screened out: the execution completes at the
  # screen, the sort is never asked, no route is reached, and the stored
  # application is marked screened out, which is the status the host's
  # retention measures its age from.
  @spec screened_out(String.t()) :: {:ok, map()} | {:error, term()}
  defp screened_out(key) do
    with {:ok, %CardApplication{id: id}, :created} <-
           CardApplications.receive_application(@scope, form(@screened_applicant, key)),
         :ok <- await(fn -> completed?(id) and screened_out?(id) end),
         execution_id when is_binary(execution_id) <- execution_id(id),
         {:ok, %{"screen" => "screened_out", "sort" => "unsorted"} = words} <-
           words(execution_id),
         [] <- sends(id) do
      {:ok, %{id: id, words: words}}
    else
      other -> {:error, other}
    end
  end

  # The application's one input: the event the intake job routed, its data
  # the id alone.
  @spec traced(String.t()) :: {:ok, [Storage.input()]} | {:error, term()}
  defp traced(execution_id) do
    with {:ok, %Execution{status: :completed} = execution} <- fetch(execution_id),
         true <- Executions.ended?(execution),
         {:ok, [_ | _] = inputs} <- Executions.inputs(FirstWorkflow.store(), execution_id) do
      {:ok, inputs}
    else
      other -> {:error, other}
    end
  end

  # ------------------------------------------------------------ the reads

  @spec screened_out?(integer()) :: boolean()
  defp screened_out?(id), do: match?(%{status: "screened_out"}, references(id))

  @spec completed?(integer()) :: boolean()
  defp completed?(id) do
    with execution_id when is_binary(execution_id) <- execution_id(id),
         {:ok, %Execution{status: :completed}} <- fetch(execution_id) do
      true
    else
      _not_yet -> false
    end
  end

  # The execution the router's address row names for the application.
  @spec execution_id(integer()) :: String.t() | nil
  defp execution_id(id) do
    key = Integer.to_string(id)
    document = Router.document_id()

    Repo.one(
      from(a in Config.queryable(Router.config(), Address),
        where: a.scope == ^@scope and a.document == ^document and a.key == ^key,
        select: a.execution_id
      )
    )
  end

  @spec fetch(String.t()) :: {:ok, Execution.t()} | {:error, term()}
  defp fetch(execution_id) do
    with {:ok, record} <- Storage.fetch_execution(FirstWorkflow.store(), execution_id) do
      {:ok, Execution.from_record(record)}
    end
  end

  # The datamodel of the execution's stored position.
  @spec datamodel(String.t()) :: {:ok, map()} | {:error, term()}
  defp datamodel(execution_id) do
    store = FirstWorkflow.store()

    with {:ok, record} <- Storage.fetch_execution(store, execution_id),
         {:ok, machine} <- chart(record.content_hash),
         {:ok, state} <- Storage.load_execution_position(store, execution_id, machine) do
      {:ok, state.datamodel}
    end
  end

  @spec chart(String.t()) :: {:ok, Machine.t()} | {:error, term()}
  defp chart(content_hash) do
    case PublishedCharts.chart(content_hash) do
      {:ok, machine} -> {:ok, machine}
      :error -> {:error, {:chart_not_registered, content_hash}}
    end
  end

  # The three steps' words from the stored position.
  @spec words(String.t()) :: {:ok, map()} | {:error, term()}
  defp words(execution_id) do
    with {:ok, datamodel} <- datamodel(execution_id) do
      {:ok, Map.take(datamodel, ~w(screen sort area))}
    end
  end

  @spec intake_args(integer()) :: [map()]
  defp intake_args(id) do
    worker = Oban.Worker.to_string(IntakeJob)

    Repo.all(
      from(j in Oban.Job,
        where: j.worker == ^worker and j.args["application_id"] == ^id,
        select: j.args
      )
    )
  end

  # Every job stored for the application: the intake job, by the id in its
  # arguments, and the steps' jobs and timers, by the execution they run
  # under. `statifier_oban` stores a job's host-opaque fields (an invoke's
  # params, content and caller context, a timer's data and caller context)
  # as Base64 term payloads, which a search of the stored text would read
  # past, so each one is decoded first, all the way down.
  @spec job_args(integer(), String.t()) :: {:ok, [term()]} | {:error, term()}
  defp job_args(id, execution_id) do
    jobs =
      Repo.all(from(j in Oban.Job, where: j.args["scope"] == ^execution_id, select: j.args))

    opened(intake_args(id) ++ jobs)
  end

  # A term with every `statifier_oban` opaque payload in it decoded, or the
  # first payload that cannot be decoded.
  @spec opened(term()) :: {:ok, term()} | {:error, term()}
  defp opened(%{"t2b64" => _encoded} = payload) do
    case OpaqueTerm.decode_field(%{"payload" => payload}, "payload") do
      {:ok, term} -> opened(term)
      {:error, reason} -> {:error, {:undecodable_job_argument, reason}}
    end
  end

  defp opened(%_{} = struct), do: opened(Map.from_struct(struct))

  defp opened(map) when is_map(map) do
    with {:ok, pairs} <- opened(Map.to_list(map)), do: {:ok, Map.new(pairs)}
  end

  defp opened(tuple) when is_tuple(tuple) do
    with {:ok, items} <- opened(Tuple.to_list(tuple)), do: {:ok, List.to_tuple(items)}
  end

  defp opened(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case opened(item) do
        {:ok, term} -> {:cont, {:ok, [term | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp opened(other), do: {:ok, other}

  @spec stored_under(String.t()) :: Ecto.Query.t()
  defp stored_under(key) do
    from(a in CardApplication, where: a.scope == ^@scope and a.idempotency_key == ^key)
  end

  @spec sends(integer()) :: [String.t()]
  defp sends(id) do
    Repo.all(
      from(s in CardApplicationSend,
        where: s.application_id == ^id,
        order_by: s.route,
        select: s.route
      )
    )
  end

  # The application's status and references, and none of its personal
  # fields, which are the reader's to read.
  @spec references(integer()) :: map() | nil
  defp references(id) do
    Repo.one(
      from(a in CardApplication,
        where: a.scope == ^@scope and a.id == ^id,
        select: %{
          status: a.status,
          external_reference: a.external_reference,
          newsletter_reference: a.newsletter_reference
        }
      )
    )
  end

  @spec ledger(integer()) :: [Ledger.t()]
  defp ledger(id) do
    key = Integer.to_string(id)
    binding_id = Router.binding_id()

    Repo.all(
      from(l in Config.queryable(Router.config(), Ledger),
        where: l.binding_id == ^binding_id and l.key == ^key,
        order_by: l.id
      )
    )
  end

  @spec holds_personal_value?(term()) :: boolean()
  defp holds_personal_value?(held) do
    text = inspect(held, limit: :infinity, printable_limit: :infinity)
    Enum.any?(@personal_fields, &String.contains?(text, Map.fetch!(@applicant, &1)))
  end

  # ------------------------------------------------------------ the queues

  # Drains the recipe's queues until `done?` holds. Under the test
  # configuration nothing runs until something drains; in the dev app the
  # queues also run on their own, and draining runs what is already due.
  @spec await((-> boolean())) :: :ok | {:error, term()}
  defp await(done?), do: await(done?, System.monotonic_time(:millisecond) + @deadline_ms)

  defp await(done?, deadline) do
    {_ok_or_unsettled, _counts} = Drain.run()

    cond do
      done?.() ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, :timed_out}

      true ->
        Process.sleep(@poll_ms)
        await(done?, deadline)
    end
  end

  # ------------------------------------------------------------ the output

  @spec words_line(map()) :: String.t()
  defp words_line(words),
    do: Enum.map_join(~w(screen sort area), ", ", &"#{&1} #{Map.get(words, &1)}")

  @spec trace_line(Storage.input()) :: String.t()
  defp trace_line(%{seq: seq, door: door, event: nil}),
    do: "  #{seq} #{door} (the log was closed here)"

  defp trace_line(%{seq: seq, door: door, event: event}),
    do: "  #{seq} #{door} #{event.name} #{inspect(event.data)}"

  @spec pins() :: String.t()
  defp pins do
    ~w(statifier_router statifier_oban statifier_persistence statifier_blocks statifier)a
    |> Enum.map_join(", ", fn app -> "#{app} #{Application.spec(app, :vsn)}" end)
  end

  @spec form(map(), String.t()) :: map()
  defp form(applicant, key), do: Map.put(applicant, "idempotency_key", key)

  @spec new_key() :: String.t()
  defp new_key,
    do: "form-" <> (4 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower))
end
