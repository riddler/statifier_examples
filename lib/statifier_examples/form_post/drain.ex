defmodule StatifierExamples.FormPost.Drain do
  @moduledoc """
  Runs the card application recipe's jobs on this app's Oban, in order,
  until none is left to run.

  The recipe's work lands in three queues, one per kind of work, all
  named in `config/config.exs`:

    * `card_application_intake` - the intake job that routes a stored
      application (`StatifierExamples.FormPost.IntakeJob`);
    * `statifier_invocations` - the three steps' jobs
      (`StatifierExamples.FormPost.Steps`);
    * `statifier_timers` - the deadline timers, `statifier_oban`'s timer
      jobs; the router holds no timer of its own here.

  `run/1` drains them in that order, each with `Oban.drain_queue/2`, and
  goes round again until a whole pass runs no job: a job one queue runs
  can store a job in another, as a step's answer stores the next step's
  job or arms a deadline. A timer runs only once it is due, so nothing
  fires early: `:until` says how far the clock may be taken, and a test
  that wants to show a deadline firing names the moment it is due.

  Under the test configuration (`testing: :manual`) nothing runs until
  something drains a queue, which is what makes the order this module's
  rather than the scheduler's. It lives here rather than in the test
  support so that a mix task can drive the recipe the same way the tests
  do; in the dev app the queues also run on their own, and draining them
  runs only what is already due.
  """

  @queues [:card_application_intake, :statifier_invocations, :statifier_timers]

  # How many passes `run/1` takes before it says the queues never
  # settled. A pass that runs nothing ends the drain; a chart that kept
  # storing due jobs forever would otherwise never return.
  @max_passes 50

  @typedoc "How many jobs ended each way across every pass."
  @type counts :: %{
          success: non_neg_integer(),
          failure: non_neg_integer(),
          cancelled: non_neg_integer(),
          discard: non_neg_integer(),
          snoozed: non_neg_integer()
        }

  @doc "The recipe's three queues, in the order `run/1` drains them."
  @spec queues() :: [atom()]
  def queues, do: @queues

  @doc """
  Drains the three queues in order, pass after pass, until a pass runs no
  job, and answers how many jobs ended each way.

  `opts` takes `:until`, a `DateTime`: every job scheduled at or before it
  is run, a timer included. It defaults to now, so a timer that is not
  yet due stays scheduled.

  Answers `{:error, {:unsettled, counts}}` when the queues still had jobs
  to run after #{@max_passes} passes.
  """
  @spec run(keyword()) :: {:ok, counts()} | {:error, {:unsettled, counts()}}
  def run(opts \\ []) do
    until = Keyword.get_lazy(opts, :until, &DateTime.utc_now/0)
    pass(until, zero(), @max_passes)
  end

  defp pass(_until, counts, 0), do: {:error, {:unsettled, counts}}

  defp pass(until, counts, passes_left) do
    ran = Enum.reduce(@queues, zero(), &add(&2, drain(&1, until)))

    case Enum.sum(Map.values(ran)) do
      0 -> {:ok, counts}
      _some -> pass(until, add(counts, ran), passes_left - 1)
    end
  end

  @spec drain(atom(), DateTime.t()) :: counts()
  defp drain(queue, until) do
    Oban.drain_queue(queue: queue, with_scheduled: until)
    |> Map.take(Map.keys(zero()))
  end

  @spec add(counts(), counts()) :: counts()
  defp add(left, right), do: Map.merge(left, right, fn _key, a, b -> a + b end)

  @spec zero() :: counts()
  defp zero, do: %{success: 0, failure: 0, cancelled: 0, discard: 0, snoozed: 0}
end
