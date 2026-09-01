defmodule StatifierExamples.Charts.AsyncCallsTest do
  @moduledoc """
  The one call in this app that outlives the step that made it, end to
  end: started as a stored job, rested on durably, answered from a process
  that has never seen the run, and cancelled by the clock the chart armed
  around it.

  Not async: durable runs step through the application's named
  `StatifierExamples.Charts.RunLock`, and the jobs are rows.
  """

  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Run, Timers}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup.{Accounts, User}
  alias StatifierPersistence.Storage

  # The wait event the wizard's verification window answers to. Pressing it
  # is how a test says "the day elapsed" without waiting one, and it is
  # what drives the run as far as the asynchronous call.
  @wait "statifier_blocks.wait.blk_su_verify_wait"

  # The event the onboarding group's own deadline carries - a `core.send`
  # at the head of its body, two hours out in the fixture, and the
  # interrupt on its rail listens for it. That pair is the timeout that
  # makes cancelling an invocation mean something.
  @deadline "signup.abandoned"

  @invoke_worker "StatifierOban.Invoke.Worker"

  # Where the wizard rests while the company-details call is running: the
  # invoking state, and the interrupt armed beside it.
  @resting ["blk_su_company", "blk_su_onboarding_abandoned"]

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run_id: "async-#{System.unique_integer([:positive])}"}
  end

  defp wizard do
    {:ok, fixture} = Charts.fixture("signup_wizard")
    {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)

    {compiled, fixture.document, fixture.key}
  end

  # Drives a fresh run as far as the asynchronous call and leaves it there.
  # The fixture key is passed because a cold answer rebuilds the chart from
  # it, exactly as a fired timer does.
  defp park!(run_id) do
    {compiled, document, key} = wizard()
    {:ok, {durable, run}} = Durable.start(compiled, document, run_id, key)
    {:ok, driven} = Durable.send_event(durable, run, @wait)

    driven
  end

  defp jobs(run_id) do
    from(job in "oban_jobs", select: %{worker: job.worker, state: job.state, args: job.args})
    |> Repo.all()
    |> Enum.map(&decode_args/1)
    |> Enum.filter(&(&1.args["scope"] == run_id))
  end

  defp decode_args(%{args: args} = job) when is_binary(args),
    do: %{job | args: Jason.decode!(args)}

  defp decode_args(job), do: job

  defp invoke_jobs(run_id), do: Enum.filter(jobs(run_id), &(&1.worker == @invoke_worker))

  # The invocation's own id, read off the stored job rather than guessed:
  # it is the string the chart, the job and both re-entry doors all name
  # the same invocation by.
  defp invoke_id!(run_id) do
    [job] = invoke_jobs(run_id)

    job.args["invoke_id"]
  end

  defp store! do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])

    store
  end

  defp record!(run_id) do
    {:ok, record} = Storage.fetch_run(store!(), run_id)

    record
  end

  # The stored position, decoded the way a cold node decodes it: recompile
  # the shipped fixture, then load. Nothing of the run that wrote it is in
  # reach here, which is the point.
  defp position!(run_id) do
    {compiled, _document, _key} = wizard()
    {:ok, machine} = Statifier.compile(compiled.scxml)
    {:ok, machine_state} = Storage.load_run_position(store!(), run_id, machine)

    machine_state
  end

  defp accounts(run_id) do
    email = Accounts.email_for(run_id)

    Repo.one!(from(u in User, where: u.email == ^email, select: count()))
  end

  defp details(run), do: run |> Run.entries() |> Enum.map(& &1.detail)

  # A bare invoke effect, for the two functions that take one without a run
  # behind them. The position row is zeros because nothing here reads it -
  # what `run/1` is handed is the type and the params.
  defp invoke(type, params) do
    %Statifier.Effect.Invoke{
      invoke_id: "inv_1",
      type: type,
      params: params,
      state_index: 0,
      invoke_index: 0,
      macrostep: 0,
      microstep: 0,
      round: 0
    }
  end

  # The predicate both halves of the seam read, asserted on its own because
  # it is the whole of this app's async policy: one block, named by the
  # invoke type its step declares and the `step` param the block emits.
  #
  # Sabotage: made the true clause match on `"preferences"` instead; this
  # went red on the first assertion, and every test below it went red too.
  # Reverted from a backup copy.
  test "only the wizard's company-details step is asynchronous" do
    assert AsyncCalls.async?("myapp:signup", %{"step" => "company_details"})
    refute AsyncCalls.async?("myapp:signup", %{"step" => "account"})
    refute AsyncCalls.async?("myapp:provision", %{})
    refute AsyncCalls.async?(nil, %{"step" => "company_details"})
  end

  # The gap a suite that drains by name cannot see. Every test here reaches
  # the queue through `queue/0`, so a `config/config.exs` that named it
  # differently - or did not name it at all - would strand every invocation
  # in the running app while this file stayed green. The deployment's queue
  # list and the module's own name are therefore asserted against each
  # other, exactly as `mix.exs` and `mix.lock` are.
  #
  # Sabotage: renamed the queue in `config/config.exs` to
  # `statifier_invokes` and left the module alone; this went red on the
  # membership assertion. Reverted from a backup copy.
  test "the app configures an Oban queue for the invocations this module names" do
    queues = Application.get_env(:statifier_examples, Oban)[:queues]

    assert Keyword.has_key?(queues, AsyncCalls.queue())
    assert Keyword.has_key?(queues, Timers.queue())

    config = AsyncCalls.config()

    assert config.invoke_queue == AsyncCalls.queue()
    assert config.invoke_delivery == AsyncCalls.Delivery
  end

  # What the job actually runs. It is the same call
  # `StatifierExamples.Charts.dispatch/3` would have made inline, routed to
  # the same handler over the same registry - which is what makes this an
  # example of WHEN a host defers a call rather than of a second way to
  # answer one. A type nobody registered is refused rather than answered,
  # so a job for one fails permanently instead of lying to the chart.
  #
  # Sabotage: made `run/1` answer `{:ok, %{}}` without dispatching; the
  # unknown-type assertion went red. Reverted from a backup copy.
  test "the job's work is this app's own dispatch" do
    assert AsyncCalls.run(invoke("myapp:signup", %{"step" => "company_details"})) ==
             {:ok, %{}}

    assert AsyncCalls.run(invoke("myapp:nope", %{})) ==
             {:error, {:unknown_invoke_type, "myapp:nope"}}
  end

  # The bead's first beat, and the one nothing in this app could do before
  # it: a run at rest in the MIDDLE of a call. Three facts, and the run
  # needs all three to be resumable - a live record, a position that still
  # holds the invocation, and the work stored somewhere that outlives this
  # process.
  #
  # Sabotage: made the durable driver executor drop its
  # `AsyncCalls.consume/2` call, so the dispatch fun still answered
  # `:pending` but no job was ever stored; the run rested on a call nobody
  # was running and this went red on the job. Reverted from a backup copy.
  test "a run rests mid-invocation: an active record, a live invocation, a stored job",
       %{run_id: run_id} do
    {_durable, run} = park!(run_id)

    assert run.status == :running
    assert run.active == @resting
    assert record!(run_id).status == :active

    invoke_id = invoke_id!(run_id)

    assert position!(run_id).active_invocations |> Map.values() == [invoke_id]

    assert [job] = invoke_jobs(run_id)
    assert job.state == "available"
    assert job.args["type"] == "myapp:signup"
    assert job.args["handler"] == "Elixir.StatifierExamples.Charts.AsyncCalls"
  end

  # The feed says so too, in the row a reader watching the page sees: the
  # call was dispatched and started, and no answer followed it.
  #
  # Sabotage: made the driver's `pending/3` skip its `note/4` call; the
  # `Invoke dispatched` row stood alone and this went red. Reverted from a
  # backup copy.
  test "the feed says the call was started rather than performed", %{run_id: run_id} do
    {_durable, run} = park!(run_id)

    details = Enum.filter(details(run), &is_binary/1)

    assert Enum.any?(details, &(&1 =~ "myapp:signup on Collect the company details"))
    assert List.last(details) =~ "myapp:signup: running as a job, answer to follow"
  end

  # The restart, and the whole reason the arm exists. Nothing of the
  # process that started the call is in reach of the drain: the worker is
  # handed a run id and an invocation id off the job row, and the chart,
  # the position and the run all come back out of SQLite. The run finishes
  # on the far side, and `myapp:provision` - the step AFTER the
  # asynchronous one - runs and writes.
  #
  # `position!/1` before the drain is the restart said explicitly: a cold
  # decode of the stored bytes, holding the invocation, on a machine that
  # shares nothing with the drive that wrote them.
  #
  # Sabotage: made `AsyncCalls.Delivery.deliver/3` answer `:delivered`
  # without calling `Durable.complete_invocation/3`; the job drained as a
  # success, the run stayed `:active` and this went red on the status.
  # Reverted from a backup copy.
  test "the job answers the invocation from a cold process and the run completes",
       %{run_id: run_id} do
    park!(run_id)

    :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(run_id))

    assert position!(run_id).active_invocations != %{}
    assert accounts(run_id) == 0

    assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

    assert record!(run_id).status == :completed
    assert accounts(run_id) == 1

    assert_receive {:run_advanced, ^run_id, {%Durable{}, %Run{status: :done} = run}}

    assert Enum.any?(details(run), fn detail ->
             is_binary(detail) and detail =~ "myapp:provision"
           end)
  end

  # At-least-once is the job queue's contract, so the second delivery of
  # one completed invocation is an ordinary event. It is discarded because
  # the chart LEFT the invoking state on the first answer, which is the
  # condition statifier_persistence's ADR-0007 names in its Consequences -
  # and the reason this app's one asynchronous call is a step that leaves.
  #
  # Sabotage: made `Durable.answer/3` report the driver's
  # `{:discarded, _}` as a delivery; this went red on the second answer,
  # and so did the cancel-race test below it. Reverted from a backup copy.
  test "answering the same invocation twice is discarded the second time", %{run_id: run_id} do
    park!(run_id)
    invoke_id = invoke_id!(run_id)

    assert Durable.complete_invocation(run_id, invoke_id, %{}) == :delivered
    assert record!(run_id).status == :completed

    assert Durable.complete_invocation(run_id, invoke_id, %{}) == {:discarded, :completed}
  end

  # The timeout beat. Nothing in the document authors a cancel: the
  # onboarding group arms `signup.abandoned` at the head of its own body
  # and listens for it on its interrupt rail, so the deadline firing exits
  # the invoking state - and THAT is what the interpreter turns into a
  # `{:cancel_invoke, _}` effect, which this app hands to the package. The
  # stored job is cancelled, and the chart routes its abandon outcome.
  #
  # Sabotage: made `AsyncCalls.consume/2`'s `CancelInvoke` clause fall
  # through to the catch-all `:ok`; the job stayed `available` and this
  # went red on the state. Reverted from a backup copy.
  test "the abandonment deadline cancels the invocation and routes the outcome",
       %{run_id: run_id} do
    park!(run_id)

    assert [%{state: "available"}] = invoke_jobs(run_id)

    assert Durable.deliver(run_id, @deadline) == :delivered

    assert [%{state: "cancelled"}] = invoke_jobs(run_id)
    assert record!(run_id).status == :completed
    assert position!(run_id).active_invocations == %{}
  end

  # The race the seam was granted to make safe, from the losing side: the
  # job was already running when the deadline fired, so its answer arrives
  # for an invocation the chart has stopped waiting for. Spec 6.4.3 says
  # discard, and the decision is taken from the loaded position inside the
  # run's own serialization strategy rather than before the call.
  #
  # Asked directly rather than through a drain, because a job that
  # `Oban.cancel_all_jobs/2` reached never runs at all - the race this
  # guards is the one where it was already past that point.
  #
  # Sabotage: made `Durable.answer/3` report the driver's
  # `{:discarded, _}` as a delivery; this went red on the tuple. Reverted
  # from a backup copy.
  test "a completion that arrives after the deadline fired is discarded", %{run_id: run_id} do
    park!(run_id)
    invoke_id = invoke_id!(run_id)

    assert Durable.deliver(run_id, @deadline) == :delivered

    assert Durable.complete_invocation(run_id, invoke_id, %{}) == {:discarded, :completed}
  end

  # The other door. A permanently failed invocation - the host's retries
  # exhausted, in st-ADR-0068's sense - reaches the chart as
  # `error.communication.invoke.<invoke_id>`, and the step's own error
  # outcome routes it. That is what makes a failed call something a chart
  # can be authored around rather than something a run hangs on.
  #
  # Sabotage: made `Durable.reenter/3`'s failing clause call
  # `Driver.done_invocation/5` instead; the chart took the step's DONE
  # outcome and this went red on both assertions. Reverted from a backup
  # copy.
  test "a permanently failed invocation reaches the chart as error.communication",
       %{run_id: run_id} do
    park!(run_id)
    invoke_id = invoke_id!(run_id)

    :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(run_id))

    assert Durable.fail_invocation(run_id, invoke_id,
             reason: "run_failed",
             attempts: 3,
             detail: "the vendor never answered"
           ) == :delivered

    assert_receive {:run_advanced, ^run_id, {%Durable{}, %Run{} = run}}

    details = Enum.filter(details(run), &is_binary/1)

    assert Enum.any?(details, &(&1 == "error.communication.invoke.#{invoke_id}"))
    assert Enum.any?(details, &(&1 =~ "error on Collect the company details"))
  end

  # A run this app can no longer name a chart for is a discard, with the
  # reason saying which half is missing - `StatifierExamples.Charts.Timers`'
  # delivery seam answers the same way for the same reason. Started without
  # a fixture key, which is what a run of a document that is not a shipped
  # fixture looks like.
  #
  # Sabotage: renamed the reason `Durable.answer/3` gives a `fixture_for/1`
  # miss; this went red on the tuple. Reverted from a backup copy.
  test "an answer for a run with no chart to rebuild is discarded", %{run_id: run_id} do
    {compiled, document, _key} = wizard()
    {:ok, {durable, run}} = Durable.start(compiled, document, run_id)
    {:ok, _driven} = Durable.send_event(durable, run, @wait)

    assert Durable.complete_invocation(run_id, invoke_id!(run_id), %{}) ==
             {:discarded, :chart_unknown}
  end

  # And a run nobody stored is refused before anything else is read - the
  # storage layer's own answer, passed through rather than eaten.
  #
  # Sabotage: made `Durable.answer/3` discard every storage error under one
  # constant reason; this went red on the tuple. Reverted from a backup
  # copy.
  test "an answer for a run that was never stored is discarded", %{run_id: run_id} do
    assert Durable.complete_invocation(run_id, "inv_1", %{}) == {:discarded, :run_not_found}
  end
end
