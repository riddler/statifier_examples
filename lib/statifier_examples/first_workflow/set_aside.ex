defmodule StatifierExamples.FirstWorkflow.SetAside do
  @moduledoc """
  The act in the first-workflow recipe: the branch sets a held copy aside
  on its hold shelf. It runs inside a `statifier_oban` invoke job, under
  the `:invoke_timeout` bound `StatifierExamples.FirstWorkflow.config/0`
  names.

  At least once is the job queue's contract, so the work must be
  idempotent on the invocation. This one is a canned answer; a handler that
  wrote something would key the write on `invoke.invoke_id`.
  """

  @behaviour StatifierOban.Invoke.Handler

  alias Statifier.Effect.Invoke

  @impl StatifierOban.Invoke.Handler
  @spec config() :: StatifierOban.Config.t()
  def config, do: StatifierExamples.FirstWorkflow.config()

  @impl StatifierOban.Invoke.Handler
  @spec run(Invoke.t()) :: {:ok, map()} | {:error, term()}
  def run(%Invoke{params: %{"hold" => %{"copy" => copy, "branch" => branch}}}),
    do: {:ok, %{"copy" => copy, "shelf" => "#{branch} hold shelf"}}

  def run(%Invoke{params: params}), do: {:error, {:no_hold, params}}
end
