defmodule Mix.Tasks.StatifierExamples.FirstWorkflow do
  @shortdoc "Runs the first-workflow guide's recipe end to end and prints the trace"

  @moduledoc """
  Runs the recipe in `docs/guides/first-workflow.md` against this app's own
  database and Oban instance, checks every step, and prints the trace.

      mix statifier_examples.first_workflow

  The work is `StatifierExamples.FirstWorkflow.run/1`; this task starts the
  application, runs it, and prints each line it answers. A step that does
  not hold stops the task with a non-zero exit and names the step.

  Run `mix ecto.migrate` first: the recipe stores an execution, and the
  executions table needs every `statifier_persistence` migration this app
  ships, V08 included.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_argv) do
    # The dev configuration logs every query; the recipe's own lines are
    # what this task is for. A level already above `:info` is left alone.
    if Logger.compare_levels(Logger.level(), :info) == :lt do
      Logger.configure(level: :info)
    end

    case StatifierExamples.FirstWorkflow.run() do
      {:ok, lines} ->
        Enum.each(lines, &Mix.shell().info/1)

      {:error, step, reason} ->
        Mix.raise("first workflow: step #{step} did not hold: #{inspect(reason)}")
    end
  end
end
