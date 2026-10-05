defmodule StatifierExamples.ObanPrunerTest do
  @moduledoc """
  The retention this app sets on its jobs table: Oban's pruner deletes a
  finished job seven days after it finished.

  A hold desk's POST job carries the hold's location in its arguments
  (`StatifierExamples.HoldDesk.DeskPost`), so this age is how long a
  location stays at rest in the jobs table after its POST is done. The
  suite runs Oban in `testing: :manual`, which starts no plugin, so the
  pruner never runs here on its own: these tests read the configured age
  and run Oban's prune with it over rows they place either side of it.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias StatifierExamples.HoldDesk.DeskPost
  alias StatifierExamples.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
  end

  # Sabotage: delete the `pruner:` key from config/config.exs -> red, no
  # Oban.Pruner among the plugins.
  test "the app's Oban configuration prunes finished jobs after seven days" do
    conf =
      :statifier_examples
      |> Application.fetch_env!(Oban)
      |> Keyword.delete(:testing)
      |> Oban.Config.new()

    assert {Oban.Pruner, [max_age: {7, :days}]} in conf.plugins
  end

  # Sabotage: set the pruner's max_age to {9, :days} -> red, the row
  # finished eight days ago is kept; to {5, :days} -> red, the row finished
  # six days ago is pruned too.
  test "a desk post job, and the location in it, outlives its finish by the configured age" do
    old = finished_desk_post("finished-eight-days-ago", days_ago: 8)
    recent = finished_desk_post("finished-six-days-ago", days_ago: 6)

    prune()

    assert job_ids() == [recent.id]
    refute old.id in job_ids()
  end

  # Sabotage: set the pruner's max_age to {9, :days} -> red, the job
  # finished eight days ago is kept and the second insert still conflicts.
  test "pruning a finished desk post job lifts its uniqueness guard" do
    finished_desk_post("re-emitted", days_ago: 8)

    assert {:ok, %Oban.Job{conflict?: true}} = Oban.insert(DeskPost.new(%{"key" => "re-emitted"}))

    prune()

    assert {:ok, %Oban.Job{conflict?: false}} =
             Oban.insert(DeskPost.new(%{"key" => "re-emitted"}))
  end

  defp finished_desk_post(key, days_ago: days) do
    {:ok, job} = Oban.insert(DeskPost.new(%{"key" => key}))
    finished_at = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    Repo.update_all(where(Oban.Job, id: ^job.id),
      set: [state: "completed", completed_at: finished_at]
    )

    job
  end

  defp prune do
    max_age =
      :statifier_examples
      |> Application.fetch_env!(Oban)
      |> Keyword.fetch!(:pruner)
      |> Keyword.fetch!(:max_age)
      |> Oban.Period.to_seconds()

    {:ok, _pruned} =
      Oban.Engine.prune_jobs(Oban.config(), Oban.Job, limit: 10_000, max_age: max_age)
  end

  defp job_ids, do: Repo.all(from(j in Oban.Job, select: j.id, order_by: j.id))
end
