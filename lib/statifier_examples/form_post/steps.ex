defmodule StatifierExamples.FormPost.Steps do
  @moduledoc """
  What the card application's two steps share: the `statifier_oban`
  configuration their jobs run under, the library system they read under,
  and the hook a test uses to make a step slow or fail.

  The steps are `StatifierExamples.FormPost.ScreenApplication`
  (`myapp:screen_application`) and
  `StatifierExamples.FormPost.CheckServiceArea`
  (`myapp:check_service_area`). Each is handed the application's id and
  nothing else, reads the stored row through
  `StatifierExamples.FormPost.CardApplications.Reader`, and answers one
  word.

  ## The delay and failure hook

  Each step is bounded in the chart: a screen or an area check that has
  not answered in time is passed over, and the flow goes on without it.
  To show that path a step has to outlast its bound, so each one reads an
  application-env setting under its own module name when it runs:

      config :statifier_examples, StatifierExamples.FormPost.ScreenApplication,
        delay_ms: 5_000,
        fail: false

  `:delay_ms` sleeps that long before the step does its work, and
  `fail: true` makes the step answer `{:error, :failure_hook}`, which the
  job retries like any other failure. Neither is set in any config file:
  absent, a step neither waits nor fails. The hook is a test's knob and a
  demo's, not something a host ships.
  """

  alias StatifierOban.Config

  # The library system this example's form belongs to, which the form's
  # controller also fixes.
  @library_system "riverbend"

  @invoke_queue :statifier_invocations
  @timers_queue :statifier_timers

  @doc """
  The library system the steps read applications under.

  This example serves one library system, the one
  `StatifierExamplesWeb.CardApplicationController` stores every post
  under. A multi-tenant host carries the library system with the
  execution instead and reads it from there, never from the invocation's
  params, which a chart author could change.
  """
  @spec library_system() :: String.t()
  def library_system, do: @library_system

  @doc """
  The `statifier_oban` configuration both steps' jobs run under: this
  app's Oban instance and its invocations queue, which
  `config/config.exs` already defines.

  No delivery module is named yet, so a finished step's answer goes to
  the package's default. The recipe's own delivery, which steps the
  stored execution, is named here when the chart runs on the app's Oban.
  """
  @spec config() :: Config.t()
  def config do
    case Config.new(oban: Oban, timers_queue: @timers_queue, invoke_queue: @invoke_queue) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  Runs the delay and failure hook configured for `step`, then `work`.

  Answers `{:error, :failure_hook}` without running `work` when the hook
  says to fail; otherwise whatever `work` answers.
  """
  @spec hooked(module(), (-> result)) :: result | {:error, :failure_hook} when result: term()
  def hooked(step, work) when is_atom(step) and is_function(work, 0) do
    hook = Application.get_env(:statifier_examples, step, [])

    case Keyword.get(hook, :delay_ms, 0) do
      0 -> :ok
      delay_ms when is_integer(delay_ms) and delay_ms > 0 -> Process.sleep(delay_ms)
    end

    if Keyword.get(hook, :fail, false), do: {:error, :failure_hook}, else: work.()
  end

  @doc """
  The application id out of a step's params, which must hold that id and
  nothing else.

  A param beyond the id is refused, and the refusal names the params'
  keys and never their values: a value a chart author put there is
  exactly what must not reach a job's errors.
  """
  @spec application_id(map()) :: {:ok, integer()} | {:error, term()}
  def application_id(%{"application_id" => id} = params)
      when is_integer(id) and map_size(params) == 1,
      do: {:ok, id}

  def application_id(params) when is_map(params),
    do: {:error, {:params_not_an_application_id, params |> Map.keys() |> Enum.sort()}}
end
