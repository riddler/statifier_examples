defmodule StatifierExamples.Charts.TimersTest do
  @moduledoc """
  The abandonment reminder, end to end: armed as a stored job, taken back
  down when the wizard moves on, and fed back into the run from a process
  that has never seen it.

  Not async: durable runs step through the application's named
  `StatifierExamples.Charts.RunLock`, and the jobs are rows.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.Charts
  alias StatifierExamples.Charts.{AsyncCalls, Durable, Run, Timers}
  alias StatifierExamples.Repo
  alias StatifierExamples.Signup
  alias StatifierPersistence.Storage

  # The wait event the wizard's own `core.wait` answers to. Sending it is
  # how a test says "the verification window elapsed" without waiting a
  # day, and it is the only thing that advances past the wait (se-5ep).
  @wait "statifier_blocks.wait.blk_su_verify_wait"

  @timer_worker "StatifierOban.Timer.Worker"

  # The event the reminder's own job carries. It is not the only stored
  # job a parked wizard has: `core.wait` compiles to a delayed send too,
  # so the 24-hour verification wait is a row beside this one - which is
  # the same durability arriving for free, and the reason every query here
  # names the event it means.
  @reminder "signup.reminder_due"

  setup do
    :ok = Sandbox.checkout(Repo)

    %{run_id: "timer-#{System.unique_integer([:positive])}"}
  end

  defp wizard do
    {:ok, fixture} = Charts.fixture("signup_wizard")
    {:ok, compiled} = Durable.compile(fixture.document, fixture.declare)

    {compiled, fixture.document, fixture.key}
  end

  defp start!(run_id) do
    {compiled, document, key} = wizard()
    {:ok, driven} = Durable.start(compiled, document, run_id, key)

    driven
  end

  defp reminder_jobs(run_id) do
    Enum.filter(jobs(run_id), &(&1.args["event"] == @reminder))
  end

  defp jobs(run_id) do
    Repo.all(
      from(job in "oban_jobs",
        where: job.worker == ^@timer_worker,
        select: %{
          args: job.args,
          state: job.state,
          inserted_at: job.inserted_at,
          scheduled_at: job.scheduled_at
        }
      )
    )
    |> Enum.map(&decode_args/1)
    |> Enum.filter(&(&1.args["scope"] == run_id))
  end

  defp decode_args(%{args: args} = job) when is_binary(args),
    do: %{job | args: Jason.decode!(args)}

  defp decode_args(job), do: job

  # The raw `oban_jobs` query answers timestamps as the text SQLite stores.
  defp at(value) when is_binary(value) do
    {:ok, at, 0} = DateTime.from_iso8601(value)

    at
  end

  defp at(%DateTime{} = value), do: value

  # The suite runs Logger at `:warning`, and every handler in this app
  # reports at `:info` - so a test about what a handler logged has to lift
  # the level while it looks.
  defp at_info(fun) do
    level = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log(fun)
    after
      Logger.configure(level: level)
    end
  end

  defp record!(run_id) do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    {:ok, record} = Storage.fetch_run(store, run_id)

    record
  end

  # The whole point of the bead, asserted at the row: parking in the
  # verification window leaves a job behind, in this app's own queue, on
  # this app's own Oban instance, keyed on the run.
  #
  # Sabotage: made `Timers.consume/2`'s `SendDelayed` clause fall through to
  # the catch-all `:ok`; this went red with no job, then reverted.
  test "parking in the verification window arms the reminder as a stored job",
       %{run_id: run_id} do
    start!(run_id)

    assert [job] = reminder_jobs(run_id)
    assert job.state == "scheduled"
    assert job.args["event"] == "signup.reminder_due"
  end

  # The delay is the deployment's, not the chart's: the fixture ships `2d`
  # and the test environment configures `45s`, so a job scheduled two days
  # out would mean the config was never read.
  #
  # Sabotage: made `Signup.apply_reminder_delay/1` answer its argument
  # unchanged; the job came back scheduled 2 days out and this went red,
  # then reverted.
  test "the reminder is armed at the delay application config names", %{run_id: run_id} do
    start!(run_id)

    [job] = reminder_jobs(run_id)

    assert Signup.reminder_delay() == "45s"

    assert_in_delta DateTime.diff(at(job.scheduled_at), at(job.inserted_at), :millisecond),
                    45_000,
                    2_000
  end

  # Leaving the scope that armed it takes it down. Nothing in the document
  # authors that cancel - the compiler emits it in the reminder window's
  # `<onexit>` - so this is the compiler's cancellation reaching Oban.
  #
  # Sabotage: made `Timers.consume/2`'s `Cancel` clause fall through to the
  # catch-all `:ok`; the job stayed `scheduled` and this went red, then
  # reverted.
  test "moving past the verification window cancels the stored reminder", %{run_id: run_id} do
    {durable, run} = start!(run_id)

    {:ok, _driven} = Durable.send_event(durable, run, @wait)

    assert [job] = reminder_jobs(run_id)
    assert job.state == "cancelled"
  end

  # The cold path, and the one that says "survives a restart": everything
  # `deliver/2` is given is a run id and an event name, and it rebuilds the
  # chart, the position and the run from storage. All three halves of the
  # bead's acceptance are here - the nudge reaches `myapp:notify`, the run
  # goes on, and the feed a page would draw carries the row.
  #
  # Sabotage: made `Durable.deliver/2`'s `fixture_for/1` read the metadata
  # key "chart" instead of "fixture"; delivery answered
  # `{:discarded, :chart_unknown}` and this went red, then reverted.
  #
  # Sabotage: made `Durable.deliver/2` skip its `broadcast/2` call; the
  # `assert_receive` timed out and this went red, then reverted.
  test "a fired reminder drives the stored run, notifies, and reaches the feed",
       %{run_id: run_id} do
    start!(run_id)

    :ok = Phoenix.PubSub.subscribe(StatifierExamples.PubSub, Durable.topic(run_id))

    # Two drains, and se-d74 is why both counts moved.
    #
    # The first fires the two stored timers - the reminder and the
    # verification wait, both scheduled at the moment of the drain. It used
    # to report one success: whichever ran first drove the whole wizard to
    # completion, and the other then found a finished run and discarded.
    # Now the first one to run rests the wizard on its asynchronous
    # company-details call instead, so the run is still live when the
    # second arrives and both succeed.
    #
    # The second drain is that call's own job, which is in the app's OTHER
    # queue: invoke jobs run the host's actual work and are kept apart from
    # the timers for that reason (`config/config.exs`). Running it is what
    # finishes the run.
    log =
      at_info(fn ->
        assert %{success: 2} = Oban.drain_queue(queue: Timers.queue(), with_scheduled: true)
        assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())
      end)

    assert log =~ "myapp:notify"
    assert record!(run_id).status == :completed

    # Two broadcasts now, one per drive, and they carry different readings:
    # the fired timer's drive is the one that reaches `myapp:notify` and
    # rests on the asynchronous call, and the job's answer opens its own
    # reading from the resumed position and finishes. Both are asserted
    # because a page showing this run redraws on each.
    assert_receive {:run_advanced, ^run_id, {%Durable{}, %Run{status: :running} = nudged}}

    assert Enum.any?(Run.entries(nudged), fn entry ->
             is_binary(entry.detail) and entry.detail =~ "myapp:notify"
           end)

    assert_receive {:run_advanced, ^run_id, {%Durable{}, %Run{status: :done}}}
  end

  # Spec 6.2's discard, enforced at the delivery seam st-ADR-0054 decision 4
  # puts it behind: a run that finished before the delay elapsed does not
  # receive the event. The job is cancelled rather than completed, so the
  # discard is on the row rather than nowhere.
  #
  # Sabotage: deleted `deliver/2`'s `:active <- record.status` clause; the
  # job drained as a success against a finished run and this went red on
  # the cancelled count, then reverted.
  test "a reminder that fires after the run finished is discarded", %{run_id: run_id} do
    {durable, run} = start!(run_id)
    {:ok, _driven} = Durable.send_event(durable, run, @wait)

    # The wait leaves the run resting on se-d74's asynchronous
    # company-details call, so finishing it takes that call's job running -
    # in the app's other queue, which is why the reminder job's own state
    # is untouched by this drain.
    assert %{success: 1} = Oban.drain_queue(queue: AsyncCalls.queue())

    assert record!(run_id).status == :completed

    # Asked directly, because the race this guards is one a cancel cannot
    # win: a job already executing when its scope exited reaches delivery
    # with the run finished behind it.
    assert Durable.deliver(run_id, @reminder) == {:discarded, :completed}
  end

  # A run this app can no longer name a chart for is a discard too, with
  # the reason saying so. Started without a fixture key, which is what a
  # run of a document that is not a shipped fixture looks like.
  #
  # Sabotage: made `deliver/2` answer `:delivered` for a `:chart_unknown`
  # fixture lookup; it raised on the missing fixture instead of cancelling
  # and this went red, then reverted.
  test "a reminder for a run with no chart to rebuild is discarded", %{run_id: run_id} do
    {compiled, document, _key} = wizard()
    {:ok, _driven} = Durable.start(compiled, document, run_id)

    assert Durable.deliver(run_id, "signup.reminder_due") == {:discarded, :chart_unknown}
  end

  # The metadata a fired timer reads is written once, at create, and has to
  # still be there after the run has been stepped - `step/5` takes no
  # metadata option, so a stepper that dropped the column would leave every
  # long-delayed timer undeliverable.
  #
  # Sabotage: made `Durable.metadata/1` answer `%{}` for a binary key; this
  # went red on the fetch, then reverted.
  test "the fixture the run is a run of survives a step", %{run_id: run_id} do
    {durable, run} = start!(run_id)

    assert record!(run_id).metadata == %{"fixture" => "signup_wizard"}

    {:ok, _driven} = Durable.send_event(durable, run, @wait)

    assert record!(run_id).metadata == %{"fixture" => "signup_wizard"}
  end
end
