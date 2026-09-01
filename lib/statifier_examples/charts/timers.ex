defmodule StatifierExamples.Charts.Timers do
  @moduledoc """
  Where a durable run's `<send delay=...>` becomes a stored Oban job.

  `Statifier.Session` arms a delayed send with `Process.send_after/3`, so
  every pending timer dies with the node. The signup wizard's reminder is
  a human-timescale delay - a day or two in a real product - and a deploy
  in the middle of it must not silently drop the nudge. So this app
  consumes the effect instead and hands it to `statifier_oban`, which
  stores it as a row.

  ## The two effects, and only those two

  A durable run's executor sees every non-lifecycle effect the stepper
  produced (`StatifierExamples.Charts.Durable`'s executor). Two of them
  are ours:

    * `{:send_delayed, %SendDelayed{target: nil}}` - one job, scheduled at
      now plus the effect's relative `delay_ms`, unique on the effect's
      `{scope, ordinal}` pair. A send with any other target is left to the
      library: its route is resolved inside the session and does not
      travel on the effect (st-ADR-0055), so there is nothing here to
      schedule.
    * `{:cancel, %Cancel{}}` - every stored job under `{scope, send_id}`.
      Nothing in a block document authors a cancel: `StatifierBlocks`'
      compiler emits one in the `<onexit>` of the scope a delayed send was
      armed in, so leaving the enclosing group is what takes the reminder
      back down. A cancel matching nothing is `{:ok, 0}`, not an error -
      a real-time cancel is allowed to lose a race with a timer that
      already fired.

  Every other effect passes through untouched.

  ## The scope is the run id

  `StatifierOban.Timer.Key`'s scope is "the caller's to supply, never
  derived", and for a process-less host it is whatever that host calls a
  run. This app's is the durable run id, which is also what the page URL
  carries - so a stored job, a stored position and a link a reader can
  come back to all name the same thing.

  ## A schedule that fails raises

  Returning `:ok` for a job that was never inserted would lose the
  reminder silently, which is the exact failure this module exists to
  prevent, and answering `{:error, _}` would be worse: the stepper
  re-enters an executor failure as `error.communication` and would steer
  the chart with an infrastructure fact. So an insert that fails raises,
  the step fails loudly, and the run's position is not advanced past a
  send that was never armed.
  """

  alias Statifier.Effect.{Cancel, SendDelayed}
  alias StatifierExamples.Charts.Timers.Delivery
  alias StatifierOban.{Config, Timer}

  @oban Oban
  @queue :statifier_timers

  @doc """
  The `statifier_oban` configuration this app runs its timers under.

  Built on every call rather than held somewhere: it is four fields over
  values that are already constants, and a memoised copy would be one
  more thing that can be stale. `:delivery` is the seam that matters -
  the package's default answers run-liveness from `Statifier.Session`'s
  registry, and this app has no session process to ask.
  """
  @spec config() :: Config.t()
  def config do
    case Config.new(oban: @oban, timers_queue: @queue, delivery: Delivery) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc "The queue timer jobs are stored in."
  @spec queue() :: atom()
  def queue, do: @queue

  @doc """
  The Oban instance this app runs its statifier jobs on.

  Named here rather than in each caller so the instance is stated once:
  `StatifierExamples.Charts.AsyncCalls` builds a second
  `StatifierOban.Config` for the invoke half and reads the instance and
  the queue back through this module rather than repeating them.
  """
  @spec oban() :: atom()
  def oban, do: @oban

  @doc """
  Consumes one effect on behalf of the run named by `run_id`.

  Answers `:ok` for every effect, including the ones it does nothing
  with: the caller is an executor, whose whole vocabulary is `:ok` and
  `{:error, _}`, and "this effect is not a timer" is not an error.
  """
  @spec consume(String.t(), Statifier.Effect.t()) :: :ok
  def consume(run_id, {:send_delayed, %SendDelayed{target: nil} = effect})
      when is_binary(run_id) do
    case Timer.schedule(config(), run_id, effect) do
      {:ok, %Oban.Job{}} -> :ok
      {:error, reason} -> raise "could not arm #{effect.event} for #{run_id}: #{inspect(reason)}"
    end
  end

  def consume(run_id, {:cancel, %Cancel{} = effect}) when is_binary(run_id) do
    case Timer.cancel(config(), run_id, effect) do
      {:ok, count} when is_integer(count) -> :ok
      {:error, reason} -> raise "could not cancel #{effect.send_id}: #{inspect(reason)}"
    end
  end

  def consume(run_id, _other) when is_binary(run_id), do: :ok
end
