defmodule StatifierExamples.FormPost.PruneJob do
  @moduledoc """
  The engine's own leftovers, cleared on this app's crontab: an Oban job
  that calls `StatifierPersistence.Retention.prune/3` with a cutoff the
  host computes from `:ended_after_days`.

  An execution that has ended still keeps its last position blob and its
  input log. The prune clears both for every execution that ended before
  the cutoff and keeps the execution row, with its status, its answer and
  its end stamp. The card application's executions hold ids and words,
  never a posted value, so what this clears is the engine's state, not
  the visitor's: the visitor's values are
  `StatifierExamples.FormPost.PurgeJob`'s. It covers every execution in
  the app's store, the card application's and the other examples' alike,
  so an execution older than the age can no longer be replayed from its
  input log.

  ## Why no `scope:`

  The call passes no `scope:`, so the prune covers the whole store. A
  scope is a list of column equalities over the host's own leading columns
  on the engine's tables (`:leading_columns` on `use
  StatifierPersistence.Ecto`), and `StatifierExamples.Persistence` places
  none: the library system lives on the host's `card_applications` table,
  not on the engine's rows, so there is no column a scope could name, and
  the Ecto adapter refuses a scope column that is not a leading column. A
  host whose engine tables carry a tenant column passes that column here,
  one call per tenant.

  The age is application config, in days, under this module's name in
  `config/config.exs`; the value there is this example's, not a
  recommendation. `perform/1` reads the clock and hands it to `prune/1`,
  which a test calls with a clock of its own.
  """

  use Oban.Worker, queue: :retention

  alias StatifierPersistence.{Retention, Storage}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case prune(DateTime.utc_now()) do
      {:ok, _counts} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Prunes every execution in the app's store that ended more than
  `:ended_after_days` before `now`, and answers
  `StatifierPersistence.Retention.prune/3`'s counts.
  """
  @spec prune(DateTime.t()) ::
          {:ok, StatifierPersistence.Storage.Adapter.prune_counts()} | {:error, term()}
  def prune(%DateTime{} = now) do
    {:ok, store} = Storage.new(StatifierExamples.Persistence, [])
    Retention.prune(store, DateTime.add(now, -age!() * 86_400, :second))
  end

  @spec age!() :: pos_integer()
  defp age! do
    case :statifier_examples
         |> Application.fetch_env!(__MODULE__)
         |> Keyword.fetch!(:ended_after_days) do
      days when is_integer(days) and days > 0 ->
        days

      other ->
        raise ArgumentError,
              "ended_after_days must be a positive number of days, got: #{inspect(other)}"
    end
  end
end
