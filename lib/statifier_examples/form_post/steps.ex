defmodule StatifierExamples.FormPost.Steps do
  @moduledoc """
  What the card application's three steps share: the `statifier_oban`
  configuration their jobs and the chart's deadline timers run under, the
  executor half that stores those jobs, the library system they read
  under, and the hook a test uses to make a step slow or fail.

  The steps are `StatifierExamples.FormPost.ScreenApplication`
  (`myapp:screen_application`),
  `StatifierExamples.FormPost.SortApplication`
  (`myapp:sort_application`) and
  `StatifierExamples.FormPost.CheckServiceArea`
  (`myapp:check_service_area`). Each is handed the application's id and
  nothing else, reads the stored row through
  `StatifierExamples.FormPost.CardApplications.Reader`, and answers one
  word.

  ## The delay and failure hook

  The screen and the area check are bounded in the chart: one that has
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

  alias Statifier.Effect.{Cancel, CancelInvoke, Invoke, SendDelayed}
  alias Statifier.Invoke.Types

  alias StatifierExamples.FormPost.{
    CheckServiceArea,
    Delivery,
    ScreenApplication,
    SortApplication
  }

  alias StatifierOban.{Config, Timer}
  alias StatifierOban.Invoke.Handler

  # The library system this example's form belongs to, which the form's
  # controller also fixes.
  @library_system "riverbend"

  @invoke_queue :statifier_invocations
  @timers_queue :statifier_timers

  # Each invoke type the document calls, and the step that serves it.
  @handlers %{
    "myapp:screen_application" => ScreenApplication,
    "myapp:sort_application" => SortApplication,
    "myapp:check_service_area" => CheckServiceArea
  }

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
  The `statifier_oban` configuration every step's job and every deadline
  timer runs under: this app's Oban instance, its timers queue and its
  invocations queue, which `config/config.exs` already defines.

  A finished step's answer and a fired timer both go to
  `StatifierExamples.FormPost.Delivery`, which steps the stored execution.
  """
  @spec config() :: Config.t()
  def config do
    case Config.new(
           oban: Oban,
           timers_queue: @timers_queue,
           delivery: Delivery,
           invoke_queue: @invoke_queue,
           invoke_delivery: Delivery
         ) do
      {:ok, config} -> config
      {:error, reason} -> raise "statifier_oban is misconfigured: #{inspect(reason)}"
    end
  end

  @doc """
  The invoke types the card application document calls, the ones the
  router's configuration registers for every create and step.
  """
  @spec invoke_types() :: [String.t()]
  def invoke_types, do: Map.keys(@handlers)

  @doc """
  Hands one effect of a card application's step to `statifier_oban`: an
  `<invoke>` of one of the three steps becomes that step's job, a cancelled
  invocation cancels its job, a delayed `<send>` with no target becomes a
  timer job, and a `<cancel>` cancels that timer. Every other effect is
  answered `:ok` and left to the router's handler.

  Each job is stored under the execution's id, with the invocation's
  params or the timer's event as the chart wrote them: the application's
  id, or nothing. A job that cannot be stored raises, as
  `StatifierExamples.FirstWorkflow` does: answering `{:error, _}` here
  would steer the chart with an infrastructure fact.
  """
  @spec execute(Statifier.Effect.t(), map()) :: :ok
  def execute({:invoke, %Invoke{type: type} = invoke}, %{execution_id: scope})
      when is_map_key(@handlers, type) do
    :ok = Handler.perform_start(Map.fetch!(@handlers, type), invoke, handler_ctx(scope))
  end

  # An invocation's id is all a cancel carries. Every step's jobs run
  # under the same configuration, so any one of the steps cancels it.
  def execute({:cancel_invoke, %CancelInvoke{invoke_id: invoke_id}}, %{execution_id: scope}) do
    :ok = Handler.perform_cancel(ScreenApplication, invoke_id, handler_ctx(scope))
  end

  def execute({:send_delayed, %SendDelayed{target: nil} = effect}, %{execution_id: scope}) do
    {:ok, %Oban.Job{}} = Timer.schedule(config(), scope, effect)
    :ok
  end

  def execute({:cancel, %Cancel{} = effect}, %{execution_id: scope}) do
    {:ok, _count} = Timer.cancel(config(), scope, effect)
    :ok
  end

  def execute(_effect, _context), do: :ok

  @spec handler_ctx(String.t()) :: Statifier.Invoke.Handler.ctx()
  defp handler_ctx(scope),
    do: %{session_id: scope, invoke_types: Types.new(types: []), invoke_handlers: %{}}

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
